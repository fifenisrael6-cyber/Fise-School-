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

/** Convertit le Markdown en blocs ordonnes sans inventer d'images. */
function buildContentBlocks(markdown: string): Array<Record<string, string>> {
  const blocks: Array<Record<string, string>> = [];
  const formulaPattern = /(?:\$\$[\s\S]+?\$\$|\$[^$\n]+\$)/g;
  let cursor = 0;
  for (const match of markdown.matchAll(formulaPattern)) {
    const index = match.index ?? 0;
    const before = markdown.slice(cursor, index).trim();
    if (before) blocks.push({ type: 'TEXT', text: before });
    const raw = match[0];
    const latex = raw.startsWith('$$') ? raw.slice(2, -2).trim() : raw.slice(1, -1).trim();
    if (latex) blocks.push({ type: 'FORMULA', latex });
    cursor = index + raw.length;
  }
  const remaining = markdown.slice(cursor).trim();
  if (remaining) blocks.push({ type: 'TEXT', text: remaining });
  return blocks.length ? blocks : [{ type: 'TEXT', text: markdown }];
}

function buildReaderPages(french: string, english: string): Array<Record<string, unknown>> {
  const fr = buildContentBlocks(french);
  const en = buildContentBlocks(english || french);
  const blocks = fr.map((block, index) => {
    const kind = String(block.type ?? "TEXT").toLowerCase();
    if (kind === "formula") return { type: "formula", latex: block.latex ?? "" };
    const translated = en[index];
    const frText = String(block.text ?? "");
    const enText = translated?.type === block.type
      ? String(translated.text ?? frText)
      : frText;
    return {
      type: "text",
      text_fr: frText,
      text_en: enText,
    };
  });
  return [{ id: "imported-course-page-1", position: 1, blocks }];
}

async function extractPdf(bytes: Uint8Array, maxPages = 120): Promise<string[]> {
  const doc = await pdfjsLib.getDocument({ data: bytes, disableWorker: true, useSystemFonts: true }).promise;
  if (doc.numPages > maxPages) throw new Error(`Le PDF dépasse la limite autorisée de ${maxPages} pages.`);
  const pages: string[] = [];
  for (let n = 1; n <= doc.numPages; n++) {
    const page = await doc.getPage(n);
    const content = await page.getTextContent();
    // Keep each page separate so each generated lesson can refer to the
    // original pages containing its figures, tables and exact page layout.
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
    pages.push(line);
  }
  return pages;
}

async function gemini(prompt: string, apiKey: string, pdfBytes?: Uint8Array): Promise<string> {
  const parts: any[] = [{ text: prompt }];
  if (pdfBytes?.length) {
    let binary = "";
    for (let i = 0; i < pdfBytes.length; i += 0x8000) {
      binary += String.fromCharCode(...pdfBytes.subarray(i, i + 0x8000));
    }
    parts.push({
      inline_data: {
        mime_type: "application/pdf",
        data: btoa(binary),
      },
    });
  }
  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${"gemini-3.8-flash"}:generateContent`, {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts }],
      generationConfig: { responseMimeType: "application/json" },
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
      .select("id,chapter_id,content_type,title_fr,storage_path,is_published")
      .eq("id", contentItemId).single();
    if (sourceError || !source) return json({ error: "Document source introuvable." }, 404);
    if (source.content_type !== "pdf" || !source.storage_path) {
      return json({ error: "Le contenu source doit être un PDF stocké." }, 400);
    }

    const isSvteehbTerminalD = curriculum.id === "0c34d759-a33d-42c1-9eaf-ad5654aea0e1";
    if (isSvteehbTerminalD) restoreExisting = true;

    // Lessons generated from the PDF follow the administrator publication choice.
    const publishGeneratedLessons = isSvteehbTerminalD || source.is_published === true;

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
      .select("id,name_fr,name_en,teaching_stream").eq("id", curriculum.subject_id).single();
    if (subjectError || !subject) throw new Error("Matière du programme introuvable.");

    // Load every active curriculum for this subject. The selected chapter is
    // only the source context; AI-detected chapter headings determine where
    // the lessons are actually placed.
    const { data: curricula, error: curriculaError } = await db.from("curricula")
      .select("id,subject_id,subsystem,sector,exam_level_id,series_id,specialty_id,teaching_stream,title_fr,is_active,is_catalog_container")
      .eq("subject_id", subject.id).eq("is_active", true);
    if (curriculaError) throw curriculaError;

    const { data: file, error: downloadError } = await db.storage.from("chapter-content")
      .download(source.storage_path);
    if (downloadError || !file) throw new Error(downloadError?.message ?? "Téléchargement du PDF impossible.");
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (bytes.length > 25 * 1024 * 1024) throw new Error("Le PDF dépasse la taille maximale de 25 Mo.");
    if (bytes.length < 5 || new TextDecoder().decode(bytes.subarray(0, 5)) !== "%PDF-") {
      throw new Error("Le fichier stocké ne possède pas une signature PDF valide.");
    }

    const extractedPages = await extractPdf(bytes, isSvteehbTerminalD ? 250 : 120);
    const sourcePageCount = extractedPages.length;
    if (isSvteehbTerminalD) {
      const coverText = normalize(extractedPages.slice(0, 3).join(" "));
      if (!coverText.includes("cours de svteehb tle d")) {
        throw new Error("Le PDF fourni ne correspond pas au cours SVTEEHB Terminale D attendu. Aucun ancien cours n’a été remplacé.");
      }
    }
    const pagesForGeneration = isSvteehbTerminalD ? extractedPages.slice(3) : extractedPages;
    let extracted = pagesForGeneration
      .map((page, index) => `[PAGE ${index + (isSvteehbTerminalD ? 4 : 1)}]\n${page}`)
      .join("\n\n")
      .trim();
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
        ] }]}),
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
- Pour les schémas, conserve les légendes et les relations décrites dans la source. Lorsque le texte ou la légende identifie clairement un schéma pris en charge, insère sur une ligne séparée le jeton correspondant exactement à sa place dans le cours : [[diagram:gravity_pair]], [[diagram:gravity_altitude]], [[diagram:weight]], [[diagram:geom_triangle]], [[diagram:geom_right_triangle]], [[diagram:geom_circle]], [[diagram:geom_square]], [[diagram:geom_parallel]], [[diagram:geom_coordinate]], [[diagram:geom_cube]], [[diagram:geom_pyramid]], [[diagram:geom_cylinder]], [[diagram:geom_prism]], [[diagram:graph_line]], [[diagram:stats_bar]], [[diagram:svt_cell]], [[diagram:svt_neuron]] ou [[diagram:svt_synapse]]. N'utilise un jeton que si la source le justifie clairement ; ne devine jamais. Pour tout autre schéma, conserve sa légende et indique « Schéma à redessiner : [description fidèle] » sans prétendre afficher une image.
- Préserve tous les exercices et questions du document. Ne fournis pas de corrigé si le document n'en donne pas.
- N'ajoute pas artificiellement une introduction, des objectifs ou une conclusion si le document ne contient pas les éléments nécessaires.
- Le contenu doit être propre sur un écran de téléphone : titres courts, paragraphes aérés, aucune balise HTML, aucun bloc de code.

CONSIGNES SPÉCIALES SVTEEHB TERMINALE D :
- Exclure la couverture, le nom de l’auteur et les pages « PROGRAMME ANNUEL » ; seules les pages pédagogiques à partir de la page 4 sont transmises.
- Regrouper les leçons sous les séquences réellement présentes. Conserver chaque titre de leçon comme sous-titre et garder toutes les explications, figures, tableaux, légendes et exercices.
- Ne pas inventer le contenu d’une séquence mentionnée uniquement dans la table des matières. Le PDF original sera affiché aux pages source pour conserver les illustrations.
- Utiliser exactement les titres suivants pour les chapitres de séquence, dans cet ordre : Séquence I — Échanges cellulaires ; Séquence II — Quelques aspects du métabolisme énergétique chez l’Homme ; Séquence III — Mécanismes fondamentaux de la reproduction sexuée chez les mammifères et les spermaphytes ; Séquence IV — Brassage génétique au cours de la reproduction sexuée et unicité génétique des individus ; Séquence V — Prévision en génétique humaine ; Séquence VI — Activité réflexe ; Séquence VII — Fonctionnement des neurones ; Séquence VIII — Activités cérébrales et motricité volontaire ou dirigée ; Séquence IX — Bases de l’immunocompétence ; Séquence X — Mécanismes de l’immunité ; Séquence XI — Dysfonctionnements du système immunitaire ; Séquence XII — Santé reproductive ; Séquence XIII — Santé nutritionnelle ; Séquence XIV — Secourisme ; Séquence XV — Mouvements de la lithosphère ; Séquence XVI — Énergies renouvelables ; Séquence XVII — Évolution de la Terre et de l’Homme ; Séquence XVIII — Transformation et conservation des produits de saison ; Séquence XIX — Entomophagie ; Séquence XX — Production des biocarburants ; Séquence XXI — Valorisation des déchets de l’environnement de l’Homme.
- Utiliser exactement les 21 titres de séquence du programme Terminale D, dans l’ordre indiqué par le document ; garder les leçons comme sous-titres à l’intérieur de chaque séquence.

Pour chaque chapitre, indique aussi source_page_start et source_page_end (numéros de pages du PDF, numérotation commençant à 1). Ces bornes doivent couvrir les pages originales qui contiennent réellement le chapitre, ses exemples, ses tableaux et ses schémas. Si plusieurs chapitres se trouvent sur une même page, cette page peut appartenir aux deux. N'invente jamais de numéro de page.

Réponds uniquement en JSON valide sous la forme {"document_title":"...","chapters":[{"title_fr":"...","title_en":"...","content_fr":"cours structuré complet en français avec Markdown","content_en":"faithful English translation preserving the same structure","source_page_start":1,"source_page_end":3}]}. Si le PDF traite d'un seul chapitre, retourne un seul élément. Maximum 30 chapitres. Matière : ${subject.name_fr}. Programme : ${curriculum.title_fr}. Chapitre sélectionné par l'administrateur : ${sourceChapter.title_fr}. Le PDF contient ${sourcePageCount} page(s). Les marqueurs [PAGE n] identifient les numéros de page originaux.

TEXTE DU PDF :
${extracted.slice(0, isSvteehbTerminalD ? 450000 : 90000)}`;
    const parsed = JSON.parse(await gemini(prompt, geminiKey, isSvteehbTerminalD ? undefined : bytes));
    const chapters = Array.isArray(parsed.chapters)
      ? parsed.chapters
          .filter((c: any) => String(c.title_fr ?? "").trim() && String(c.content_fr ?? "").trim())
          .slice(0, 30)
          .map((c: any) => {
            const start = Number(c.source_page_start);
            const end = Number(c.source_page_end);
            const minimumSourcePage = isSvteehbTerminalD ? 4 : 1;
            const validStart = Number.isInteger(start) && start >= minimumSourcePage && start <= sourcePageCount ? start : minimumSourcePage;
            const validEnd = Number.isInteger(end) && end >= validStart && end <= sourcePageCount
              ? end
              : sourcePageCount;
            return { ...c, source_page_start: validStart, source_page_end: validEnd };
          })
      : [];
    if (isSvteehbTerminalD) {
      const canonical = [
        ["Séquence I — Échanges cellulaires", "Sequence I — Cellular exchanges"],
        ["Séquence II — Quelques aspects du métabolisme énergétique chez l’Homme", "Sequence II — Aspects of human energy metabolism"],
        ["Séquence III — Mécanismes fondamentaux de la reproduction sexuée chez les mammifères et les spermaphytes", "Sequence III — Fundamental mechanisms of sexual reproduction in mammals and spermatophytes"],
        ["Séquence IV — Brassage génétique au cours de la reproduction sexuée et unicité génétique des individus", "Sequence IV — Genetic mixing during sexual reproduction and genetic uniqueness"],
        ["Séquence V — Prévision en génétique humaine", "Sequence V — Prediction in human genetics"],
        ["Séquence VI — Activité réflexe", "Sequence VI — Reflex activity"],
        ["Séquence VII — Fonctionnement des neurones", "Sequence VII — Neuron function"],
        ["Séquence VIII — Activités cérébrales et motricité volontaire ou dirigée", "Sequence VIII — Brain activity and voluntary or directed movement"],
        ["Séquence IX — Bases de l’immunocompétence", "Sequence IX — Foundations of immunocompetence"],
        ["Séquence X — Mécanismes de l’immunité", "Sequence X — Mechanisms of immunity"],
        ["Séquence XI — Dysfonctionnements du système immunitaire", "Sequence XI — Immune system dysfunctions"],
        ["Séquence XII — Santé reproductive", "Sequence XII — Reproductive health"],
        ["Séquence XIII — Santé nutritionnelle", "Sequence XIII — Nutritional health"],
        ["Séquence XIV — Secourisme", "Sequence XIV — First aid"],
        ["Séquence XV — Mouvements de la lithosphère", "Sequence XV — Lithosphere movements"],
        ["Séquence XVI — Énergies renouvelables", "Sequence XVI — Renewable energy"],
        ["Séquence XVII — Évolution de la Terre et de l’Homme", "Sequence XVII — Evolution of the Earth and humankind"],
        ["Séquence XVIII — Transformation et conservation des produits de saison", "Sequence XVIII — Processing and preservation of seasonal produce"],
        ["Séquence XIX — Entomophagie", "Sequence XIX — Entomophagy"],
        ["Séquence XX — Production des biocarburants", "Sequence XX — Biofuel production"],
        ["Séquence XXI — Valorisation des déchets de l’environnement de l’Homme", "Sequence XXI — Recovery and reuse of human-environment waste"],
      ];
      const roman = ["", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi", "xii", "xiii", "xiv", "xv", "xvi", "xvii", "xviii", "xix", "xx", "xxi"];
      for (const generated of chapters) {
        const match = normalize(generated.title_fr).match(/sequence\s+(xxi|xx|xix|xviii|xvii|xvi|xv|xiv|xiii|xii|xi|x|ix|viii|vii|vi|v|iv|iii|ii|i|\d+)\b/);
        if (!match) continue;
        const token = match[1].toLowerCase();
        const index = /^\d+$/.test(token) ? Number(token) : roman.indexOf(token);
        if (index >= 1 && index <= canonical.length) {
          generated.title_fr = canonical[index - 1][0];
          generated.title_en = canonical[index - 1][1];
        }
      }
    }
    if (!chapters.length) throw new Error("Aucun chapitre exploitable n'a été identifié.");
    // The source document has a known 21-sequence Terminale D structure.
    // Keep all sequence cards, including those whose lessons are absent from
    // this PDF copy; those cards intentionally remain empty until content exists.
    let svteehbOriginalChapterIds: string[] = [];
    if (isSvteehbTerminalD) {
      const sequenceRows = [
        ["Séquence I — Échanges cellulaires", "Sequence I — Cellular exchanges", "Module I — Le monde vivant", "Module I — The living world"],
        ["Séquence II — Quelques aspects du métabolisme énergétique chez l’Homme", "Sequence II — Aspects of human energy metabolism", "Module I — Le monde vivant", "Module I — The living world"],
        ["Séquence III — Mécanismes fondamentaux de la reproduction sexuée chez les mammifères et les spermaphytes", "Sequence III — Fundamental mechanisms of sexual reproduction in mammals and spermatophytes", "Module I — Le monde vivant", "Module I — The living world"],
        ["Séquence IV — Brassage génétique au cours de la reproduction sexuée et unicité génétique des individus", "Sequence IV — Genetic mixing during sexual reproduction and genetic uniqueness", "Module I — Le monde vivant", "Module I — The living world"],
        ["Séquence V — Prévision en génétique humaine", "Sequence V — Prediction in human genetics", "Module I — Le monde vivant", "Module I — The living world"],
        ["Séquence VI — Activité réflexe", "Sequence VI — Reflex activity", "Module I — Le monde vivant", "Module I — The living world"],
        ["Séquence VII — Fonctionnement des neurones", "Sequence VII — Neuron function", "Module I — Le monde vivant", "Module I — The living world"],
        ["Séquence VIII — Activités cérébrales et motricité volontaire ou dirigée", "Sequence VIII — Brain activity and voluntary or directed movement", "Module I — Le monde vivant", "Module I — The living world"],
        ["Séquence IX — Bases de l’immunocompétence", "Sequence IX — Foundations of immunocompetence", "Module II — Éducation à la santé", "Module II — Health education"],
        ["Séquence X — Mécanismes de l’immunité", "Sequence X — Mechanisms of immunity", "Module II — Éducation à la santé", "Module II — Health education"],
        ["Séquence XI — Dysfonctionnements du système immunitaire", "Sequence XI — Immune system dysfunctions", "Module II — Éducation à la santé", "Module II — Health education"],
        ["Séquence XII — Santé reproductive", "Sequence XII — Reproductive health", "Module II — Éducation à la santé", "Module II — Health education"],
        ["Séquence XIII — Santé nutritionnelle", "Sequence XIII — Nutritional health", "Module II — Éducation à la santé", "Module II — Health education"],
        ["Séquence XIV — Secourisme", "Sequence XIV — First aid", "Module II — Éducation à la santé", "Module II — Health education"],
        ["Séquence XV — Mouvements de la lithosphère", "Sequence XV — Lithosphere movements", "Module III — Éducation à l’environnement et au développement durable", "Module III — Environmental and sustainable development education"],
        ["Séquence XVI — Énergies renouvelables", "Sequence XVI — Renewable energy", "Module III — Éducation à l’environnement et au développement durable", "Module III — Environmental and sustainable development education"],
        ["Séquence XVII — Évolution de la Terre et de l’Homme", "Sequence XVII — Evolution of the Earth and humankind", "Module III — Éducation à l’environnement et au développement durable", "Module III — Environmental and sustainable development education"],
        ["Séquence XVIII — Transformation et conservation des produits de saison", "Sequence XVIII — Processing and preservation of seasonal produce", "Module IV — Biotechnologie", "Module IV — Biotechnology"],
        ["Séquence XIX — Entomophagie", "Sequence XIX — Entomophagy", "Module IV — Biotechnologie", "Module IV — Biotechnology"],
        ["Séquence XX — Production des biocarburants", "Sequence XX — Biofuel production", "Module IV — Biotechnologie", "Module IV — Biotechnology"],
        ["Séquence XXI — Valorisation des déchets de l’environnement de l’Homme", "Sequence XXI — Recovery and reuse of human-environment waste", "Module IV — Biotechnologie", "Module IV — Biotechnology"],
      ];
      const { data: oldChapters, error: oldChaptersError } = await db.from("course_chapters")
        .select("id,position").eq("curriculum_id", curriculum.id);
      if (oldChaptersError) throw oldChaptersError;
      svteehbOriginalChapterIds = (oldChapters ?? []).map((row: any) => String(row.id));
      for (const oldChapter of [...(oldChapters ?? [])].sort((a: any, b: any) => Number(b.position ?? 0) - Number(a.position ?? 0))) {
        const { error: deactivateError } = await db.from("course_chapters")
          .update({
            is_active: false,
            position: Number(oldChapter.position ?? 0) + 1000,
          }).eq("id", oldChapter.id);
        if (deactivateError) throw deactivateError;
      }
      for (let index = 0; index < sequenceRows.length; index++) {
        const [titleFr, titleEn, moduleFr, moduleEn] = sequenceRows[index];
        const { error: insertError } = await db.from("course_chapters").insert({
          curriculum_id: curriculum.id,
          title_fr: titleFr,
          title_en: titleEn,
          description_fr: moduleFr,
          description_en: moduleEn,
          position: index + 1,
          is_active: true,
          source_title: "Document de cours SVTEEHB Terminale D fourni pour l’intégration",
        });
        if (insertError) throw insertError;
      }
    }


    // Determine every active classroom that actually studies this subject.
    // Then choose the same canonical curriculum that the student catalogue uses:
    // exact catalog containers first, otherwise compatible non-container curricula.
    const { data: assignedRows, error: assignedError } = await db.from("class_subjects")
      .select("class_id").eq("subject_id", subject.id).eq("is_active", true);
    if (assignedError) throw assignedError;
    const assignedClassIds = [...new Set((assignedRows ?? []).map((row: any) => String(row.class_id)))];
    const { data: activeClasses, error: classesError } = assignedClassIds.length
      ? await db.from("school_classes")
          .select("id,display_name,name,subsystem,sector,exam_level_id,series_id,specialty_id")
          .in("id", assignedClassIds).eq("is_active", true)
      : { data: [], error: null };
    if (classesError) throw classesError;

    const curriculumMatchesClass = (candidate: any, schoolClass: any) =>
      candidate.subsystem === schoolClass.subsystem &&
      candidate.sector === schoolClass.sector &&
      (candidate.exam_level_id == null || candidate.exam_level_id === schoolClass.exam_level_id) &&
      (candidate.series_id == null || candidate.series_id === schoolClass.series_id) &&
      (candidate.specialty_id == null || candidate.specialty_id === schoolClass.specialty_id);

    // Never cross subsystem, sector, exam level, specialty or teaching stream.
    // Series is intentionally allowed to differ: the existing shared-chapter
    // catalogue links equivalent chapters across compatible series.
    const sameSourceContext = (candidate: any) =>
      candidate.subsystem === curriculum.subsystem &&
      candidate.sector === curriculum.sector &&
      candidate.exam_level_id === curriculum.exam_level_id &&
      candidate.specialty_id === curriculum.specialty_id &&
      candidate.teaching_stream === curriculum.teaching_stream;

    const selectedCurriculumIds = new Set<string>([curriculum.id]);
    for (const schoolClass of activeClasses ?? []) {
      const compatible = (curricula ?? []).filter((candidate: any) =>
        sameSourceContext(candidate) && curriculumMatchesClass(candidate, schoolClass));
      const exactContainers = compatible.filter((candidate: any) =>
        candidate.is_catalog_container === true &&
        candidate.exam_level_id === schoolClass.exam_level_id &&
        candidate.series_id === schoolClass.series_id &&
        candidate.specialty_id === schoolClass.specialty_id);
      const selected = exactContainers.length
        ? exactContainers
        : compatible.filter((candidate: any) => candidate.is_catalog_container !== true);
      for (const candidate of selected) selectedCurriculumIds.add(String(candidate.id));
    }

    const targetCurricula = isSvteehbTerminalD
      ? [curriculum]
      : (curricula ?? []).filter((candidate: any) =>
          selectedCurriculumIds.has(String(candidate.id)));
    if (!targetCurricula.some((candidate: any) => candidate.id === curriculum.id)) {
      targetCurricula.push(curriculum);
    }

    const targetRooms = (activeClasses ?? []).filter((schoolClass: any) =>
      targetCurricula.some((candidate: any) => curriculumMatchesClass(candidate, schoolClass)));
    const chapterCache = new Map<string, { rows: any[]; nextPosition: number }>();
    for (const targetCurriculum of targetCurricula) {
      const { data: rows, error: rowsError } = await db.from("course_chapters")
        .select("id,title_fr,title_en,position").eq("curriculum_id", targetCurriculum.id)
        .eq("is_active", true).order("position");
      if (rowsError) throw rowsError;
      const existingRows = rows ?? [];
      chapterCache.set(String(targetCurriculum.id), {
        rows: existingRows,
        nextPosition: Math.max(-1, ...existingRows.map((row: any) => Number(row.position ?? 0))) + 1,
      });
    }

    const report: any[] = [];
    const keptContentItemIds = new Set<string>();
    for (const generated of chapters) {
      const parsedTitle = String(generated.title_fr).trim().slice(0, 250);
      // The selected chapter is only a source context. Always use the chapter
      // heading detected in the PDF to find or create the actual destination.
      const chapterTitle = parsedTitle;
      const targetChapterIds = new Set<string>();
      let sourceTarget: any = null;

      for (const targetCurriculum of targetCurricula) {
        const cache = chapterCache.get(String(targetCurriculum.id))!;
        let target = cache.rows.find((row: any) => normalize(row.title_fr) === normalize(chapterTitle));

        if (!target) {
          const { data: created, error: createError } = await db.from("course_chapters").insert({
            curriculum_id: targetCurriculum.id,
            title_fr: chapterTitle,
            title_en: String(generated.title_en ?? chapterTitle).trim().slice(0, 250) || chapterTitle,
            description_fr: "Chapitre issu d'un document PDF importé par l'administrateur.",
            description_en: "Chapter created from an administrator-imported PDF.",
            position: cache.nextPosition++,
            is_active: true,
          }).select("id,title_fr,title_en,position").single();
          if (createError) throw createError;
          target = created;
          cache.rows.push(created);
        }

        const targetId = String(target.id);
        targetChapterIds.add(targetId);
        if (targetCurriculum.id === curriculum.id) sourceTarget = target;
      }

      if (!sourceTarget) {
        throw new Error("Impossible de déterminer le chapitre source pour enregistrer le cours.");
      }

      const contentTitle = parsedTitle;
      const { data: duplicate, error: duplicateError } = await db.from("chapter_content_items")
        .select("id,title_fr,title_en,is_published,position")
        .eq("chapter_id", sourceTarget.id).eq("content_type", "course")
        .eq("title_fr", contentTitle).limit(1);
      if (duplicateError) throw duplicateError;

      let item: any = null;
      let status = "imported_draft";
      if (!restoreExisting && (duplicate ?? []).length) {
        item = duplicate![0];
        if (publishGeneratedLessons && item.is_published !== true) {
          const { data: published, error: publishError } = await db.from("chapter_content_items")
            .update({ is_published: true }).eq("id", item.id)
            .select("id,is_published").single();
          if (publishError) throw publishError;
          item = published;
          status = "published_existing";
        } else {
          status = item.is_published === true ? "already_published" : "already_exists";
        }
      } else if (restoreExisting && (duplicate ?? []).length) {
        const previous = duplicate![0];
        const { data: updated, error: updateError } = await db.from("chapter_content_items")
          .update({
            title_en: String(generated.title_en ?? previous.title_en ?? contentTitle).trim().slice(0, 250) || contentTitle,
            body_text_fr: String(generated.content_fr).trim(),
            body_text_en: String(generated.content_en ?? "").trim() || String(generated.content_fr).trim(),
            content_blocks_fr: buildContentBlocks(String(generated.content_fr).trim()),
            content_blocks_en: buildContentBlocks(String(generated.content_en ?? "").trim() || String(generated.content_fr).trim()),
            pages_json: buildReaderPages(String(generated.content_fr).trim(), String(generated.content_en ?? "").trim() || String(generated.content_fr).trim()),
            source_pdf_path: source.storage_path,
            source_page_start: generated.source_page_start,
            source_page_end: generated.source_page_end,
            folder_key: "course",
            is_published: previous.is_published === true || publishGeneratedLessons,
          })
          .eq("id", previous.id).select("id,is_published").single();
        if (updateError) throw updateError;
        item = updated;
        status = updated.is_published === true ? "restored_existing_published" : "restored_existing";
      } else if (restoreExisting) {
        const { data: existingCourses, error: coursesError } = await db.from("chapter_content_items")
          .select("id,title_fr,title_en,is_published,position")
          .eq("chapter_id", sourceTarget.id).eq("content_type", "course")
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
              content_blocks_fr: buildContentBlocks(String(generated.content_fr).trim()),
              content_blocks_en: buildContentBlocks(String(generated.content_en ?? "").trim() || String(generated.content_fr).trim()),
              pages_json: buildReaderPages(String(generated.content_fr).trim(), String(generated.content_en ?? "").trim() || String(generated.content_fr).trim()),
              source_pdf_path: source.storage_path,
              source_page_start: generated.source_page_start,
              source_page_end: generated.source_page_end,
              folder_key: "course",
              is_published: previous.is_published === true || publishGeneratedLessons,
            })
            .eq("id", previous.id).select("id,is_published").single();
          if (updateError) throw updateError;
          item = updated;
          status = updated.is_published === true ? "restored_existing_published" : "restored_existing";
        }
      }

      if (!item) {
        const { data: inserted, error: insertError } = await db.from("chapter_content_items").insert({
          chapter_id: sourceTarget.id,
          content_type: "course",
          title_fr: contentTitle,
          title_en: String(generated.title_en ?? contentTitle).trim().slice(0, 250) || contentTitle,
          body_text_fr: String(generated.content_fr).trim(),
          body_text_en: String(generated.content_en ?? "").trim() || String(generated.content_fr).trim(),
          content_blocks_fr: buildContentBlocks(String(generated.content_fr).trim()),
          content_blocks_en: buildContentBlocks(String(generated.content_en ?? "").trim() || String(generated.content_fr).trim()),
          pages_json: buildReaderPages(String(generated.content_fr).trim(), String(generated.content_en ?? "").trim() || String(generated.content_fr).trim()),
          source_pdf_path: source.storage_path,
          source_page_start: generated.source_page_start,
          source_page_end: generated.source_page_end,
          position: 0,
          is_published: publishGeneratedLessons,
          created_by: isSvteehbTerminalD ? null : authData.user.id,
          folder_key: "course",
        }).select("id").single();
        if (insertError) throw insertError;
        item = inserted;
        status = restoreExisting ? "restored_new" : (publishGeneratedLessons ? "imported_published" : "imported_draft");
      }

      keptContentItemIds.add(String(item.id));

      // Explicit links guarantee that every selected classroom's matching
      // chapter receives the same lesson, even if its title punctuation differs.
      const links = [...targetChapterIds].map((chapterId) => ({
        content_item_id: item.id,
        chapter_id: chapterId,
      }));
      if (links.length) {
        const { error: linkInsertError } = await db.from("chapter_content_item_chapters")
          .upsert(links, { onConflict: "content_item_id,chapter_id", ignoreDuplicates: true });
        if (linkInsertError) throw linkInsertError;
      }

      report.push({
        chapter: chapterTitle,
        status,
        content_item_id: item.id,
        linked_chapters: targetChapterIds.size,
      });
    }


    if (isSvteehbTerminalD) {
      const { data: oldItems, error: oldItemsError } = await db.from("chapter_content_items")
        .select("id,chapter_id").in("chapter_id", svteehbOriginalChapterIds).eq("content_type", "course");
      if (oldItemsError) throw oldItemsError;
      const oldChapterSet = new Set(svteehbOriginalChapterIds);
      for (const oldItem of oldItems ?? []) {
        const oldId = String(oldItem.id);
        if (keptContentItemIds.has(oldId)) continue;
        const { data: links, error: linksError } = await db.from("chapter_content_item_chapters")
          .select("chapter_id").eq("content_item_id", oldId);
        if (linksError) throw linksError;
        const outsideLinks = [...new Set((links ?? [])
          .map((row: any) => String(row.chapter_id))
          .filter((chapterId: string) => !oldChapterSet.has(chapterId)))];
        const { error: unlinkError } = await db.from("chapter_content_item_chapters")
          .delete().eq("content_item_id", oldId).in("chapter_id", svteehbOriginalChapterIds);
        if (unlinkError) throw unlinkError;
        if (outsideLinks.length) {
          const { error: moveError } = await db.from("chapter_content_items")
            .update({ chapter_id: outsideLinks[0] }).eq("id", oldId);
          if (moveError) throw moveError;
        } else {
          const { error: deleteError } = await db.from("chapter_content_items")
            .delete().eq("id", oldId);
          if (deleteError) throw deleteError;
        }
      }
      const { data: oldCourses, error: oldCoursesError } = await db.from("courses")
        .select("id").in("chapter_id", svteehbOriginalChapterIds);
      if (oldCoursesError) throw oldCoursesError;
      const oldCourseIds = (oldCourses ?? []).map((row: any) => String(row.id));
      if (oldCourseIds.length) {
        const { error: deleteLessonsError } = await db.from("lessons").delete().in("course_id", oldCourseIds);
        if (deleteLessonsError) throw deleteLessonsError;
        const { error: deleteCoursesError } = await db.from("courses").delete().in("id", oldCourseIds);
        if (deleteCoursesError) throw deleteCoursesError;
      }
      const { error: hideSourceError } = await db.from("chapter_content_items")
        .update({ is_published: false }).eq("id", contentItemId);
      if (hideSourceError) throw hideSourceError;
    }

    return json({
      success: true,
      source_content_item_id: contentItemId,
      subject: subject.name_fr,
      source_chapter: sourceChapter.title_fr,
      target_rooms: targetRooms.map((schoolClass: any) => ({
        id: schoolClass.id,
        name: schoolClass.display_name ?? schoolClass.name ?? "Salle",
      })),
      target_room_count: targetRooms.length,
      target_curriculum_count: targetCurricula.length,
      detected_chapters: chapters.length,
      imported: report.filter((x) => x.status === "imported_draft" || x.status === "imported_published").length,
      published: report.filter((x) => x.status === "imported_published" || x.status === "published_existing" || x.status === "already_published").length,
      restored: report.filter((x) => x.status === "restored_existing" || x.status === "restored_new").length,
      already_exists: report.filter((x) => x.status === "already_exists").length,
      report,
      requires_admin_publication: report.some((x) => x.status === "imported_draft" || x.status === "restored_new" || x.status === "restored_existing"),
      message: publishGeneratedLessons
        ? `Import terminé : les leçons natives sont publiées et reliées aux chapitres correspondants de ${targetRooms.length} salle(s).`
        : `Import terminé : les leçons sont reliées aux chapitres correspondants de ${targetRooms.length} salle(s). Elles restent en brouillon jusqu'à validation de l'administrateur.`,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Erreur lors de l'import du PDF.";
    return json({ error: message }, 500);
  }
});
