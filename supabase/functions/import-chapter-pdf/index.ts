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
  if (doc.numPages > 120) throw new Error("Le PDF dépasse la limite de 120 pages. Divisez-le en plusieurs fichiers.");
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

async function gemini(prompt: string, apiKey: string): Promise<string> {
  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${"gemini-3.8-flash"}:generateContent`, {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
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
  try {
    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const service = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!url || !anon || !service || !geminiKey) {
      return json({ error: "Configuration serveur incomplète (Supabase/Gemini)." }, 500);
    }

    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return json({ error: "Connexion requise." }, 401);
    const token = auth.slice(7).trim();
    const userClient = createClient(url, anon, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false },
    });
    const { data: authData, error: authError } = await userClient.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Session invalide." }, 401);
    const { data: profile } = await userClient.from("profiles").select("role")
      .eq("id", authData.user.id).maybeSingle();
    if (profile?.role !== "admin") return json({ error: "Import réservé à l'administrateur." }, 403);

    const body = await req.json();
    const contentItemId = String(body?.content_item_id ?? "").trim();
    const restoreExisting = body?.restore_existing === true;
    if (!contentItemId) return json({ error: "content_item_id manquant." }, 400);
    const db = createClient(url, service);

    const { data: source, error: sourceError } = await db.from("chapter_content_items")
      .select("id,chapter_id,content_type,title_fr,storage_path")
      .eq("id", contentItemId).single();
    if (sourceError || !source) return json({ error: "Document source introuvable." }, 404);
    if (source.content_type !== "pdf" || !source.storage_path) {
      return json({ error: "Le contenu source doit être un PDF stocké." }, 400);
    }

    const { data: sourceChapter, error: chapterError } = await db.from("course_chapters")
      .select("id,curriculum_id,title_fr,title_en,position")
      .eq("id", source.chapter_id).single();
    if (chapterError || !sourceChapter) return json({ error: "Chapitre de destination introuvable." }, 404);

    const { data: curriculum, error: curriculumError } = await db.from("curricula")
      .select("id,subject_id,subsystem,sector,exam_level_id,series_id,specialty_id,teaching_stream,title_fr,is_active")
      .eq("id", sourceChapter.curriculum_id).single();
    if (curriculumError || !curriculum || !curriculum.is_active) {
      return json({ error: "Le programme du chapitre est introuvable ou inactif." }, 400);
    }
    const { data: subject, error: subjectError } = await db.from("subjects")
      .select("id,name_fr,name_en").eq("id", curriculum.subject_id).single();
    if (subjectError || !subject) throw new Error("Matière du programme introuvable.");

    const { data: file, error: downloadError } = await db.storage.from("chapter-content")
      .download(source.storage_path);
    if (downloadError || !file) throw new Error(downloadError?.message ?? "Téléchargement du PDF impossible.");
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (bytes.length > 25 * 1024 * 1024) throw new Error("Le PDF dépasse la taille maximale de 25 Mo.");
    if (bytes.length < 5 || new TextDecoder().decode(bytes.subarray(0, 5)) !== "%PDF-") {
      throw new Error("Le fichier stocké ne possède pas une signature PDF valide.");
    }

    let extracted = await extractPdf(bytes);
    if (extracted.length < 250) {
      let binary = "";
      for (let i = 0; i < bytes.length; i += 0x8000) {
        binary += String.fromCharCode(...bytes.subarray(i, i + 0x8000));
      }
      const scanned = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${"gemini-3.8-flash"}:generateContent`, {
        method: "POST",
        headers: { "x-goog-api-key": geminiKey, "Content-Type": "application/json" },
        body: JSON.stringify({ contents: [{ role: "user", parts: [
          { text: "Transcris fidèlement le texte de ce PDF scolaire en français. Conserve les titres, formules, tableaux sous forme textuelle et exemples. Ne résume pas et n'invente rien." },
          { inline_data: { mime_type: "application/pdf", data: btoa(binary) } },
        ] }], generationConfig: { temperature: 0 } }),
      });
      const scannedData = await scanned.json();
      if (!scanned.ok) throw new Error(scannedData?.error?.message ?? "Lecture du PDF scanné impossible.");
      extracted = scannedData?.candidates?.[0]?.content?.parts?.map((p: any) => p.text ?? "").join("\n") ?? "";
    }
    if (extracted.trim().length < 200) throw new Error("Le PDF ne contient pas assez de texte lisible.");

    const prompt = `Tu es un rédacteur pédagogique expérimenté pour les classes du système scolaire camerounais francophone. Transforme le texte extrait en un véritable cours de salle de classe, clair, complet, progressif et directement lisible par un élève dans l'application mobile. Ce n'est PAS un résumé et ce ne doit PAS ressembler à un PDF brut.

RÈGLES ABSOLUES :
- Reste fidèle au document source : ne supprime aucune notion importante, définition, propriété, formule, démonstration, exemple, tableau ni exercice.
- N'invente aucune information, valeur, formule, référence, expérience ou réponse absente de la source. Si une rubrique n'est pas présente ou ne peut pas être déduite avec certitude, omets-la.
- Réorganise seulement lorsque cela améliore la compréhension, sans changer le sens ni l'ordre logique des notions.
- Rédige en français scolaire naturel, avec des phrases complètes et des explications accessibles. Corrige les erreurs manifestes de transcription sans altérer les notions.
- N'écris pas tout le cours dans un seul paragraphe. Aère le texte et utilise des titres et sous-titres Markdown.
- Utilise les conventions de rédaction scolaire : I., II., III. pour les grandes parties ; A., B. pour les sous-parties ; « Définition », « Propriété », « Théorème », « Exemple », « Application » et « À retenir » lorsque ces éléments existent dans la source.
- Place chaque définition et formule sur une ligne distincte. Écris les formules mathématiques en LaTeX entre $...$ ou $$...$$. Présente les tableaux en tableau Markdown. Présente les étapes et énumérations en listes numérotées ou à puces.
- Pour les schémas, conserve les légendes et les relations décrites dans la source ; si le schéma lui-même n'est pas récupérable, indique sobrement « Schéma à insérer : [description fidèle] » sans prétendre afficher une image.
- Préserve tous les exercices et questions du document. Ne fournis pas de corrigé si le document n'en donne pas.
- N'ajoute pas artificiellement une introduction, des objectifs ou une conclusion si le document ne contient pas les éléments nécessaires.
- Le contenu doit être propre sur un écran de téléphone : titres courts, paragraphes aérés, aucune balise HTML, aucun bloc de code.

Réponds uniquement en JSON valide sous la forme {"document_title":"...","chapters":[{"title_fr":"...","title_en":"...","content_fr":"cours structuré complet en français avec Markdown","content_en":"faithful English translation preserving the same structure"}]}. Si le PDF traite d'un seul chapitre, retourne un seul élément. Maximum 30 chapitres. Matière : ${subject.name_fr}. Programme : ${curriculum.title_fr}. Chapitre sélectionné par l'administrateur : ${sourceChapter.title_fr}.

TEXTE DU PDF :
${extracted.slice(0, 90000)}`;
    const parsed = JSON.parse(await gemini(prompt, geminiKey));
    const chapters = Array.isArray(parsed.chapters)
      ? parsed.chapters.filter((c: any) => String(c.title_fr ?? "").trim() && String(c.content_fr ?? "").trim()).slice(0, 30)
      : [];
    if (!chapters.length) throw new Error("Aucun chapitre exploitable n'a été identifié.");

    const { data: existingRows, error: existingError } = await db.from("course_chapters")
      .select("id,title_fr,title_en,position").eq("curriculum_id", curriculum.id)
      .eq("is_active", true).order("position");
    if (existingError) throw existingError;
    const existing = existingRows ?? [];
    let nextPosition = Math.max(-1, ...existing.map((x: any) => Number(x.position ?? 0))) + 1;
    const report: any[] = [];

    for (let index = 0; index < chapters.length; index++) {
      const generated = chapters[index];
      const parsedTitle = String(generated.title_fr).trim().slice(0, 250);
      let target: any = chapters.length === 1
        ? sourceChapter
        : existing.find((x: any) => normalize(x.title_fr) === normalize(parsedTitle));

      if (!target && chapters.length > 1) {
        const { data: created, error: createError } = await db.from("course_chapters").insert({
          curriculum_id: curriculum.id,
          title_fr: parsedTitle,
          title_en: String(generated.title_en ?? parsedTitle).trim().slice(0, 250) || parsedTitle,
          description_fr: "Chapitre issu d'un document PDF importé par l'administrateur.",
          description_en: "Chapter created from an administrator-imported PDF.",
          position: nextPosition++,
          is_active: true,
        }).select("id,title_fr,title_en,position").single();
        if (createError) throw createError;
        target = created;
        existing.push(created);
      }

      const contentTitle = chapters.length === 1
        ? (String(parsed.document_title ?? "").trim().slice(0, 250) || sourceChapter.title_fr)
        : parsedTitle;
      const { data: duplicate, error: duplicateError } = await db.from("chapter_content_items")
        .select("id,title_fr,title_en,is_published,position")
        .eq("chapter_id", target.id).eq("content_type", "course")
        .eq("title_fr", contentTitle).limit(1);
      if (duplicateError) throw duplicateError;

      // Update existing lesson only after successful PDF extraction and AI generation.
      // Keep its ID, publication state, links and position unchanged.
      let item: any;
      if (restoreExisting && (duplicate ?? []).length) {
        const previous = duplicate![0];
        const { data: updated, error: updateError } = await db.from("chapter_content_items")
          .update({
            title_en: String(generated.title_en ?? previous.title_en ?? contentTitle).trim().slice(0, 250) || contentTitle,
            body_text_fr: String(generated.content_fr).trim(),
            body_text_en: String(generated.content_en ?? "").trim() || String(generated.content_fr).trim(),
            folder_key: "course",
          })
          .eq("id", previous.id).select("id").single();
        if (updateError) throw updateError;
        item = updated;
        report.push({ chapter: target.title_fr, status: "restored_existing", content_item_id: item.id });
      } else if (restoreExisting) {
        const { data: existingCourses, error: coursesError } = await db.from("chapter_content_items")
          .select("id,title_fr,title_en,is_published,position")
          .eq("chapter_id", target.id).eq("content_type", "course")
          .order("position").limit(1);
        if (coursesError) throw coursesError;
        if ((existingCourses ?? []).length) {
          const previous = existingCourses![0];
          const { data: updated, error: updateError } = await db.from("chapter_content_items")
            .update({
              title_fr: contentTitle,
              title_en: String(generated.title_en ?? contentTitle).trim().slice(0, 250) || contentTitle,
              body_text_fr: String(generated.content_fr).trim(),
              body_text_en: String(generated.content_en ?? "").trim() || String(generated.content_fr).trim(),
              folder_key: "course",
            })
            .eq("id", previous.id).select("id").single();
          if (updateError) throw updateError;
          item = updated;
          report.push({ chapter: target.title_fr, status: "restored_existing", content_item_id: item.id });
        }
      }

      if (!item) {
        const { data: inserted, error: insertError } = await db.from("chapter_content_items").insert({
          chapter_id: target.id,
          content_type: "course",
          title_fr: contentTitle,
          title_en: String(generated.title_en ?? contentTitle).trim().slice(0, 250) || contentTitle,
          body_text_fr: String(generated.content_fr).trim(),
          body_text_en: String(generated.content_en ?? "").trim() || String(generated.content_fr).trim(),
          position: 0,
          is_published: false,
          created_by: authData.user.id,
          folder_key: "course",
        }).select("id").single();
        if (insertError) throw insertError;
        item = inserted;
        report.push({ chapter: target.title_fr, status: restoreExisting ? "restored_new" : "imported_draft", content_item_id: item.id });
      }

      const { count: linkedCount, error: linkError } = await db.from("chapter_content_item_chapters")
        .select("chapter_id", { count: "exact", head: true }).eq("content_item_id", item.id);
      if (linkError) throw linkError;
      report.push({ chapter: target.title_fr, status: "imported_draft", linked_chapters: linkedCount ?? 1, content_item_id: item.id });
    }

    return json({
      success: true,
      source_content_item_id: contentItemId,
      subject: subject.name_fr,
      source_chapter: sourceChapter.title_fr,
      detected_chapters: chapters.length,
      imported: report.filter((x) => x.status === "imported_draft").length,
      restored: report.filter((x) => x.status === "restored_existing" || x.status === "restored_new").length,
      already_exists: report.filter((x) => x.status === "already_exists").length,
      report,
      requires_admin_publication: !restoreExisting,
      message: "Import terminé. Les leçons sont enregistrées en brouillon et associées aux chapitres équivalents. Vérifiez-les puis publiez-les depuis l'administration.",
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Erreur lors de l'import du PDF.";
    return json({ error: message }, 500);
  }
});
