import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const MAX_BATCH = 12;

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

function extractJson(text: string): Record<string, string> {
  const cleaned = text.trim().replace(/^\`\`\`json/i, "").replace(/^\`\`\`/i, "").replace(/\`\`\`$/i, "").trim();
  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  if (start < 0 || end <= start) throw new Error("Réponse IA non structurée.");
  const parsed = JSON.parse(cleaned.slice(start, end + 1));
  if (!parsed || typeof parsed !== "object") throw new Error("Réponse IA invalide.");
  return Object.fromEntries(Object.entries(parsed).map(([k, v]) => [k, String(v ?? "").trim()]));
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) return json({ error: "Authentication required." }, 401);

    const token = authHeader.slice("Bearer ".length).trim();
    const url = Deno.env.get("SUPABASE_URL");
    const anon = Deno.env.get("SUPABASE_ANON_KEY");
    const geminiKey = Deno.env.get("GEMINI_API_KEY");
    if (!url || !anon || !geminiKey) return json({ error: "Configuration serveur IA incomplète." }, 500);

    const client = createClient(url, anon, {
      global: { headers: { Authorization: `Bearer ${token}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userError } = await client.auth.getUser(token);
    if (userError || !userData.user) return json({ error: "Session invalide ou expirée." }, 401);

    const { data: profile, error: profileError } = await client.from("profiles").select("id,role").eq("id", userData.user.id).maybeSingle();
    if (profileError || profile?.role !== "admin") return json({ error: "Accès réservé à l'administrateur." }, 403);

    const body = await req.json();
    const action = String(body?.action ?? "generate");

    if (action === "approve") {
      const ids = Array.isArray(body?.course_ids) ? body.course_ids.map((v: unknown) => String(v)).filter(Boolean).slice(0, 100) : [];
      if (!ids.length) return json({ error: "Aucun cours sélectionné." }, 400);
      const { data, error } = await client.from("courses").update({ status: "published", published_at: new Date().toISOString() })
        .in("id", ids).eq("ai_generated", true).eq("status", "draft").select("id,chapter_id");
      if (error) throw error;
      const chapterIds = Array.from(new Set((data ?? [])
        .map((row: any) => String(row.chapter_id ?? ""))
        .filter((id: string) => id.length > 0)));
      return json({ approved: data?.length ?? 0, chapter_ids: chapterIds });
    }

    if (action === "missing_quizzes") {
      const [{ data: chapterItems, error: itemError }, { data: courses, error: courseError }, { data: quizzes, error: quizError }] = await Promise.all([
        client.from("chapter_content_items").select("chapter_id")
          .in("content_type", ["course", "lesson", "text"]).eq("is_published", true).limit(1000),
        client.from("courses").select("chapter_id").eq("status", "published").limit(1000),
        client.from("chapter_quizzes").select("chapter_id")
          .eq("is_published", true).is("created_by", null).limit(1000),
      ]);
      if (itemError) throw itemError;
      if (courseError) throw courseError;
      if (quizError) throw quizError;
      const sourceChapterIds = new Set<string>();
      for (const row of chapterItems ?? []) {
        const id = String(row.chapter_id ?? "");
        if (id) sourceChapterIds.add(id);
      }
      for (const row of courses ?? []) {
        const id = String(row.chapter_id ?? "");
        if (id) sourceChapterIds.add(id);
      }
      const existingQuizChapterIds = new Set<string>((quizzes ?? [])
        .map((row: any) => String(row.chapter_id ?? "")).filter((id: string) => id.length > 0));
      const missingChapterIds = [...sourceChapterIds].filter((id) => !existingQuizChapterIds.has(id));
      return json({ chapter_ids: missingChapterIds, remaining: missingChapterIds.length });
    }

    const classIds = Array.isArray(body?.class_ids) ? body.class_ids.map((v: unknown) => String(v)).filter(Boolean).slice(0, 30) : [];
    if (!classIds.length) return json({ error: "Sélectionne au moins une salle." }, 400);

    const { data: classes, error: classesError } = await client.from("school_classes")
      .select("id,display_name,name,subsystem,sector").in("id", classIds).eq("is_active", true);
    if (classesError) throw classesError;

    const candidates: Array<Record<string, string | null>> = [];

    for (const schoolClass of classes ?? []) {
      const { data: links, error: linksError } = await client.from("class_subjects")
        .select("subject_id,subjects(id,name_fr,name_en,code)").eq("class_id", schoolClass.id).eq("is_active", true).order("position");
      if (linksError) throw linksError;

      for (const link of links ?? []) {
        const subject = link.subjects as Record<string, unknown> | null;
        if (!subject) continue;
        const { data: curricula, error: curriculumError } = await client.from("curricula")
          .select("id,title_fr,title_en,description_fr,description_en").eq("subject_id", subject.id).eq("is_active", true).order("title_fr");
        if (curriculumError) throw curriculumError;

        for (const curriculum of curricula ?? []) {
          const { data: chapters, error: chapterError } = await client.from("course_chapters")
            .select("id,title_fr,title_en,description_fr,description_en,position").eq("curriculum_id", curriculum.id).eq("is_active", true).order("position");
          if (chapterError) throw chapterError;

          for (const chapter of chapters ?? []) {
            const { data: existing, error: existingError } = await client.from("courses").select("id")
              .eq("class_id", schoolClass.id).eq("subject_id", subject.id).eq("chapter_id", chapter.id).neq("status", "archived").limit(1);
            if (existingError) throw existingError;
            if ((existing ?? []).length) continue;

            candidates.push({
              class_id: schoolClass.id.toString(),
              class_name: String(schoolClass.display_name ?? schoolClass.name ?? ""),
              subject_id: String(subject.id),
              subject_name_fr: String(subject.name_fr ?? ""),
              subject_name_en: String(subject.name_en ?? ""),
              curriculum_id: String(curriculum.id),
              curriculum_title_fr: String(curriculum.title_fr ?? ""),
              curriculum_title_en: String(curriculum.title_en ?? ""),
              chapter_id: String(chapter.id),
              chapter_title_fr: String(chapter.title_fr ?? ""),
              chapter_title_en: String(chapter.title_en ?? ""),
              chapter_description_fr: String(chapter.description_fr ?? ""),
              chapter_description_en: String(chapter.description_en ?? ""),
            });
            if (candidates.length >= MAX_BATCH) break;
          }
          if (candidates.length >= MAX_BATCH) break;
        }
        if (candidates.length >= MAX_BATCH) break;
      }
      if (candidates.length >= MAX_BATCH) break;
    }

    if (!candidates.length) return json({ generated: 0, remaining: 0, message: "Tous les cours disponibles ont déjà été préparés ou aucun programme actif n'est associé aux salles." });

    const batchId = crypto.randomUUID();
    let generated = 0;
    const createdIds: string[] = [];
    const errors: string[] = [];

    for (const item of candidates) {
      try {
        const prompt = `Crée un cours scolaire complet et exact pour Fise School au Cameroun.
Classe/salle: ${item.class_name}
Matière FR: ${item.subject_name_fr}
Matière EN: ${item.subject_name_en}
Programme FR: ${item.curriculum_title_fr}
Programme EN: ${item.curriculum_title_en}
Chapitre FR: ${item.chapter_title_fr}
Chapitre EN: ${item.chapter_title_en}
Description du chapitre FR: ${item.chapter_description_fr}
Description du chapitre EN: ${item.chapter_description_en}

Respecte strictement le programme et le chapitre. Explique notions, définitions, méthodes, exemples et résumé. Produis exactement un objet JSON avec title_fr, title_en, description_fr, description_en, content_fr, content_en. Pas de LaTeX ni de commandes TeX; mathématiques en texte/Unicode.`;

        const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash"}:generateContent`, {
          method: "POST",
          headers: { "x-goog-api-key": geminiKey, "Content-Type": "application/json" },
          body: JSON.stringify({
            systemInstruction: { parts: [{ text: "Tu es l'auteur pédagogique de Fise School au Cameroun. Respecte strictement les données de programme fournies. N'invente pas une référence officielle. Réponds uniquement avec le JSON demandé." }] },
            contents: [{ role: "user", parts: [{ text: prompt }] }],
            generationConfig: { temperature: 0.25 },
          }),
        });

        const data = await response.json();
        if (!response.ok) throw new Error(data?.error?.message ?? "Gemini a refusé la génération.");
        const raw = data?.candidates?.[0]?.content?.parts?.map((p: { text?: string }) => p.text ?? "").join("").trim();
        if (!raw) throw new Error("Gemini n'a retourné aucun contenu.");
        const course = extractJson(raw);
        if (!course.title_fr || !course.title_en || !course.content_fr || !course.content_en) throw new Error("Le cours généré est incomplet.");

        const { data: inserted, error: insertError } = await client.from("courses").insert({
          curriculum_id: item.curriculum_id,
          chapter_id: item.chapter_id,
          subject_id: item.subject_id,
          teacher_id: userData.user.id,
          class_id: item.class_id,
          title_fr: course.title_fr,
          title_en: course.title_en,
          description_fr: course.description_fr || null,
          description_en: course.description_en || null,
          content_fr: course.content_fr,
          content_en: course.content_en,
          status: "draft",
          ai_generated: true,
          ai_batch_id: batchId,
          ai_generated_at: new Date().toISOString(),
        }).select("id").single();
        if (insertError) throw insertError;
        createdIds.push(inserted.id);
        generated++;
      } catch (error) {
        errors.push(`${item.class_name} / ${item.subject_name_fr}: ${error instanceof Error ? error.message : String(error)}`);
      }
    }

    return json({
      generated,
      created_ids: createdIds,
      remaining: Math.max(0, candidates.length - generated),
      errors,
      message: generated ? `${generated} cours IA préparés en brouillon. Ils restent invisibles pour les élèves jusqu'à ton autorisation.` : "Aucun cours IA n'a pu être préparé dans ce lot.",
    });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Erreur IA inconnue." }, 500);
  }
});
