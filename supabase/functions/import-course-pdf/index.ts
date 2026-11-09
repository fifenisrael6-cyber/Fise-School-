import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import * as pdfjsLib from "npm:pdfjs-dist@4.10.38/legacy/build/pdf.mjs";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { ...cors, "Content-Type": "application/json" } });

function normalize(value: unknown): string {
  return String(value ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
}

async function extractPdf(bytes: Uint8Array): Promise<string> {
  const doc = await pdfjsLib.getDocument({ data: bytes, disableWorker: true, useSystemFonts: true }).promise;
  const pages: string[] = [];
  for (let n = 1; n <= doc.numPages; n++) {
    const page = await doc.getPage(n);
    const content = await page.getTextContent();
    // Keep the PDF's visual line structure instead of flattening every page
    // into one long sentence. This lets the lesson formatter recover headings,
    // numbered sections, formulas and table rows more faithfully.
    const lineGroups = new Map<number, Array<{ x: number; text: string }>>();
    for (const item of content.items as any[]) {
      const text = String(item?.str ?? "").trim();
      if (!text) continue;
      const transform = Array.isArray(item?.transform) ? item.transform : [];
      const x = Number(transform[4] ?? 0);
      const y = Number(transform[5] ?? 0);
      const key = Math.round(y / 2);
      const group = lineGroups.get(key) ?? [];
      group.push({ x, text });
      lineGroups.set(key, group);
    }
    const line = [...lineGroups.entries()]
      .sort((a, b) => b[0] - a[0])
      .map(([, parts]) => parts.sort((a, b) => a.x - b.x)
        .map((part) => part.text).join(" ").replace(/\s+/g, " ").trim())
      .filter(Boolean)
      .join("\n");
    if (line) pages.push(line);
  }
  return pages.join("\n\n").trim();
}

async function gemini(prompt: string, apiKey: string, pdfBytes?: Uint8Array): Promise<string> {
  const parts: any[] = [{ text: prompt }];
  if (pdfBytes?.length) {
    let binary = "";
    for (let i = 0; i < pdfBytes.length; i += 0x8000) {
      binary += String.fromCharCode(...pdfBytes.subarray(i, i + 0x8000));
    }
    parts.push({ inline_data: { mime_type: "application/pdf", data: btoa(binary) } });
  }
  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${"gemini-3.8-flash"}:generateContent`, {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts }],
      generationConfig: { temperature: 0.1, responseMimeType: "application/json" },
    }),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data?.error?.message ?? "Erreur Gemini.");
  const value = data?.candidates?.[0]?.content?.parts?.map((p: any) => p.text ?? "").join("").trim();
  if (!value) throw new Error("Gemini n'a retourné aucun contenu.");
  return value.replace(/^```json\s*/i, "").replace(/\s*```$/, "").trim();
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);
  let db: ReturnType<typeof createClient> | null = null;
  let resourceId = "";
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!url || !anon || !service || !geminiKey) return json({ error: "Configuration serveur incomplète (Supabase/Gemini)." }, 500);

    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return json({ error: "Connexion requise." }, 401);
    const token = auth.slice(7).trim();
    const userClient = createClient(url, anon, { global: { headers: { Authorization: `Bearer ${token}` } }, auth: { persistSession: false } });
    const { data: authData, error: authError } = await userClient.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Session invalide." }, 401);
    const { data: profile } = await userClient.from("profiles").select("role").eq("id", authData.user.id).maybeSingle();
    if (profile?.role !== "admin") return json({ error: "Import réservé à l'administrateur." }, 403);

    const body = await req.json();
    resourceId = String(body?.resource_id ?? "").trim();
    if (!resourceId) return json({ error: "resource_id manquant." }, 400);
    db = createClient(url, service);

    const { data: resource, error: resourceError } = await db.from("course_resources")
      .select("id,course_id,resource_type,storage_path,file_name,mime_type")
      .eq("id", resourceId).single();
    if (resourceError || !resource) return json({ error: "Fichier PDF introuvable." }, 404);
    if (resource.resource_type !== "pdf" && resource.mime_type !== "application/pdf") return json({ error: "Le fichier doit être un PDF." }, 400);

    const { data: sourceCourse, error: courseError } = await db.from("courses")
      .select("id,class_id,subject_id,curriculum_id,teacher_id,title_fr")
      .eq("id", resource.course_id).single();
    if (courseError || !sourceCourse?.class_id || !sourceCourse.subject_id) return json({ error: "Le cours source doit être lié à une salle et une matière." }, 400);

    const { data: sourceClass, error: classError } = await db.from("school_classes")
      .select("id,display_name,name,subsystem,sector,exam_level_id,series_id,specialty_id")
      .eq("id", sourceCourse.class_id).single();
    if (classError || !sourceClass) throw new Error("Impossible de lire la salle source.");

    const { data: file, error: downloadError } = await db.storage.from("course-resources").download(resource.storage_path);
    if (downloadError || !file) throw new Error(downloadError?.message ?? "Téléchargement du PDF impossible.");
    const bytes = new Uint8Array(await file.arrayBuffer());
    let extracted = await extractPdf(bytes);
    if (extracted.length < 250) {
      let binary = "";
      for (let i = 0; i < bytes.length; i += 0x8000) binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      const scanned = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${"gemini-3.8-flash"}:generateContent`, {
        method: "POST", headers: { "x-goog-api-key": geminiKey, "Content-Type": "application/json" },
        body: JSON.stringify({ contents: [{ role: "user", parts: [
          { text: "Transcris fidèlement tout le texte de ce PDF scolaire en français. Conserve les titres, les formules, les tableaux sous forme textuelle et les exemples. Ne résume pas et n'invente rien." },
          { inline_data: { mime_type: "application/pdf", data: btoa(binary) } },
        ] }], generationConfig: { temperature: 0 } }),
      });
      const scannedData = await scanned.json();
      if (!scanned.ok) throw new Error(scannedData?.error?.message ?? "Lecture du PDF scanné impossible.");
      extracted = scannedData?.candidates?.[0]?.content?.parts?.map((p: any) => p.text ?? "").join("\n") ?? "";
    }
    if (extracted.trim().length < 200) throw new Error("Le PDF ne contient pas assez de texte lisible pour l'import.");

    const subjectResult = await db.from("subjects").select("id,name_fr,name_en").eq("id", sourceCourse.subject_id).single();
    if (subjectResult.error || !subjectResult.data) throw new Error("Matière source introuvable.");
    const prompt = `Tu es un rédacteur pédagogique expérimenté pour les classes du système scolaire camerounais francophone. Transforme le texte extrait en véritables cours de salle de classe, complets, progressifs et directement lisibles par les élèves dans l'application mobile. Il ne s'agit ni d'un résumé ni d'une copie brute du PDF.

RÈGLES ABSOLUES :
- Découpe le document uniquement selon les chapitres réellement présents. Si aucun chapitre explicite n'existe, crée des sections cohérentes à partir des titres et changements de notions visibles, sans inventer de contenu.
- Conserve les notions, définitions, propriétés, théorèmes, démonstrations, formules, exemples, tableaux et exercices. Ne résume pas et ne supprime pas les explications.
- N'invente aucune connaissance externe, donnée, formule, expérience, réponse ou référence.
- Rédige en français scolaire naturel, avec des phrases complètes, des explications accessibles et une progression logique.
- N'écris jamais le cours entier dans un seul paragraphe. Structure avec des titres Markdown (#, ##, ###), les grandes parties I., II., III., puis A., B. si pertinent.
- Utilise les rubriques « Définition », « Propriété », « Théorème », « Démonstration », « Exemple », « Application » et « À retenir » uniquement lorsque le contenu source les justifie.
- Place les formules mathématiques en LaTeX entre $...$ ou $$...$$. Mets les tableaux en tableau Markdown et les étapes en listes numérotées ou à puces.
- Analyse aussi les pages visuelles du PDF fourni en pièce jointe : schémas, figures, graphiques, illustrations, tableaux et légendes. Ne te limite pas au texte extrait automatiquement.
- Pour chaque figure, conserve sa position logique dans le cours, sa légende et une description fidèle de ses éléments visibles. Si elle correspond à un schéma pris en charge, insère le jeton correspondant ; sinon écris « Schéma à redessiner : [description fidèle des éléments visibles et de leurs légendes] ». Ne prétends jamais qu’une image a été enregistrée si tu ne l’as pas réellement extraite.
- Conserve les schémas et leurs légendes. Lorsque le texte ou la légende identifie clairement un schéma pris en charge, insère sur une ligne séparée le jeton correspondant exactement à sa place dans le cours : [[diagram:gravity_pair]], [[diagram:gravity_altitude]], [[diagram:weight]], [[diagram:geom_triangle]], [[diagram:geom_right_triangle]], [[diagram:geom_circle]], [[diagram:geom_square]], [[diagram:geom_parallel]], [[diagram:geom_coordinate]], [[diagram:geom_cube]], [[diagram:geom_pyramid]], [[diagram:geom_cylinder]], [[diagram:geom_prism]], [[diagram:graph_line]], [[diagram:stats_bar]], [[diagram:svt_cell]], [[diagram:svt_neuron]] ou [[diagram:svt_synapse]]. N'utilise un jeton que si la source le justifie clairement ; ne devine jamais. Pour tout autre schéma, conserve sa légende et indique « Schéma à redessiner : [description fidèle] » sans prétendre afficher une image.
- Conserve tous les exercices et questions ; ne fabrique pas de corrigés.
- N'ajoute pas artificiellement des objectifs ou rubriques absentes de la source.
- Le rendu final doit être agréable sur téléphone : paragraphes aérés, titres clairs, pas de HTML ni de bloc de code.

Réponds uniquement en JSON valide sous la forme {"document_title":"...","chapters":[{"title_fr":"titre fidèle en français","title_en":"faithful English title","content_fr":"cours complet et structuré en français avec Markdown","content_en":"faithful English translation preserving the same structure"}]}. Maximum 30 chapitres. Matière connue : ${subjectResult.data.name_fr}. Salle source : ${sourceClass.display_name ?? sourceClass.name}.

TEXTE EXTRAIT DU PDF (texte intégral, sans troncature) :
${extracted}`;
    const parsed = JSON.parse(await gemini(prompt, geminiKey, bytes));
    const chapters = Array.isArray(parsed.chapters) ? parsed.chapters.filter((c: any) => String(c.title_fr ?? "").trim() && String(c.content_fr ?? "").trim()).slice(0, 30) : [];
    if (!chapters.length) throw new Error("Aucun chapitre exploitable n'a été identifié dans le PDF.");

    const { data: curricula, error: curriculaError } = await db.from("curricula")
      .select("id,title_fr,subsystem,sector,exam_level_id,series_id,specialty_id,is_catalog_container")
      .eq("subject_id", sourceCourse.subject_id).eq("is_active", true)
      .eq("subsystem", sourceClass.subsystem).eq("sector", sourceClass.sector);
    if (curriculaError) throw curriculaError;

    const contextCurricula = (curricula ?? []).filter((c: any) =>
      c.exam_level_id === sourceClass.exam_level_id &&
      c.series_id === sourceClass.series_id &&
      c.specialty_id === sourceClass.specialty_id);
    const containers = contextCurricula.filter((c: any) => c.is_catalog_container === true);
    const matchingCurricula = sourceCourse.curriculum_id
      ? contextCurricula.filter((c: any) => c.id === sourceCourse.curriculum_id)
      : (containers.length ? containers : contextCurricula);
    if (!matchingCurricula.length) throw new Error("Aucun programme actif ne correspond exactement à la salle source et à cette matière.");

    const report: any[] = [];
    for (const curriculum of matchingCurricula) {
      const { data: existing, error: existingError } = await db.from("course_chapters")
        .select("id,title_fr,position").eq("curriculum_id", curriculum.id).eq("is_active", true).order("position");
      if (existingError) throw existingError;
      let nextPosition = Math.max(-1, ...(existing ?? []).map((x: any) => Number(x.position ?? 0))) + 1;
      for (const chapter of chapters) {
        const title = String(chapter.title_fr).trim().slice(0, 250);
        let target = (existing ?? []).find((x: any) => normalize(x.title_fr) === normalize(title));
        if (!target) {
          const { data: created, error: createError } = await db.from("course_chapters").insert({
            curriculum_id: curriculum.id, title_fr: title, title_en: title,
            description_fr: "Chapitre importé depuis un PDF pédagogique.", description_en: "Chapter imported from an educational PDF.",
            position: nextPosition++, is_active: true,
          }).select("id,title_fr,position").single();
          if (createError) throw createError;
          target = created;
          (existing as any[]).push(created);
        }
        const { data: duplicate, error: duplicateError } = await db.from("chapter_content_items")
          .select("id").eq("chapter_id", target.id).eq("content_type", "course").eq("title_fr", title).limit(1);
        if (duplicateError) throw duplicateError;
        if ((duplicate ?? []).length) {
          report.push({ chapter: title, curriculum: curriculum.title_fr, status: "already_exists" });
          continue;
        }
        const bodyText = String(chapter.content_fr).trim();
        const { data: item, error: itemError } = await db.from("chapter_content_items").insert({
          chapter_id: target.id, content_type: "course", title_fr: title, title_en: String(chapter.title_en ?? title).trim().slice(0, 250) || title,
          body_text_fr: bodyText, body_text_en: String(chapter.content_en ?? "").trim() || bodyText, position: 0,
          is_published: false, created_by: authData.user.id, folder_key: "course",
        }).select("id").single();
        if (itemError) throw itemError;
        report.push({ chapter: title, curriculum: curriculum.title_fr, status: "imported", content_item_id: item.id });
      }
    }
    const imported = report.filter((r) => r.status === "imported").length;
    const existingCount = report.filter((r) => r.status === "already_exists").length;
    const wordCount = extracted.split(/\s+/).filter(Boolean).length;
    const { error: statusError } = await db.from("course_resources").update({
      index_status: "indexed",
      index_error: null,
      index_preview: extracted.slice(0, 4000),
      index_word_count: wordCount,
      index_approved: false,
      indexed_at: new Date().toISOString(),
    }).eq("id", resourceId);
    if (statusError) throw statusError;
    return json({
      success: true, source_resource_id: resourceId, source_class: sourceClass.display_name ?? sourceClass.name,
      subject: subjectResult.data.name_fr, detected_chapters: chapters.length,
      imported, already_exists: existingCount, report,
      message: `${imported} chapitre(s) préparé(s), ${existingCount} déjà présents. Les nouveaux cours sont enregistrés en brouillon dans les salles correspondantes : relisez et corrigez le contenu dans l’espace écrit, puis publiez-le pour les élèves.`,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Erreur lors de l'import du PDF.";
    if (db && resourceId) {
      try {
        await db.from("course_resources").update({
          index_status: "failed",
          index_error: message.slice(0, 2000),
          indexed_at: new Date().toISOString(),
        }).eq("id", resourceId);
      } catch (_) {
        // Le statut d'import ne doit jamais masquer l'erreur initiale.
      }
    }
    return json({ error: message }, 500);
  }
});
