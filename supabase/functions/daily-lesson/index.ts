import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function nextOccurrence(dayOfWeek: number, timeText: string, from = new Date()) {
  const current = new Date(from.toLocaleString("en-US", { timeZone: "Africa/Douala" }));
  const [hh, mm] = String(timeText).slice(0, 5).split(":").map(Number);
  const dayDelta = (dayOfWeek - current.getDay() + 7) % 7 || 7;
  const target = new Date(current);
  target.setDate(current.getDate() + dayDelta);
  target.setHours(hh, mm, 0, 0);
  return target;
}

async function geminiJson(apiKey: string, prompt: string) {
  const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [{ text: prompt }] }],
      generationConfig: { temperature: 0.2, responseMimeType: "application/json" },
    }),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data?.error?.message ?? "Gemini request failed.");
  const raw = data?.candidates?.[0]?.content?.parts?.map((part: { text?: string }) => part.text ?? "").join("").trim();
  if (!raw) throw new Error("Gemini returned an empty response.");
  return JSON.parse(raw);
}

async function getNextChunk(admin: ReturnType<typeof createClient>, studentId: string, subjectId: string, classId: string) {
  const { data: progress } = await admin.from("student_lesson_progress")
    .select("last_chunk_id,status")
    .eq("student_id", studentId)
    .eq("subject_id", subjectId)
    .maybeSingle();

  let query = admin.from("course_chunks")
    .select("id,course_id,class_id,subject_id,position,title,content,language,course_resources(index_status,index_approved),courses(status,smart_lesson_enabled,minimum_exercise_score)")
    .eq("class_id", classId)
    .eq("subject_id", subjectId)
    .order("position");

  const { data: chunks, error } = await query;
  if (error) throw error;
  const usable = (chunks ?? []).filter((x: any) =>
    x.courses?.status === "published" && x.courses?.smart_lesson_enabled === true &&
    x.course_resources?.index_status === "indexed" && x.course_resources?.index_approved === true,
  );
  if (!usable.length) return null;

  const lastPosition = progress?.last_chunk_id
    ? Number((usable.find((x: any) => x.id === progress.last_chunk_id)?.position ?? -1))
    : -1;
  return usable.find((x: any) => Number(x.position) > lastPosition) ?? null;
}

async function ensureLesson(admin: ReturnType<typeof createClient>, apiKey: string, chunk: any, language: string, quotaUserId?: string) {
  const { data: cached } = await admin.from("generated_lessons").select("id,chunk_id,language,text,generated_at").eq("chunk_id", chunk.id).eq("language", language).maybeSingle();
  if (cached) {
    const { data: cachedExercise } = await admin.from("generated_exercises").select("id,lesson_id,language").eq("lesson_id", cached.id).maybeSingle();
    return { lesson: cached, exerciseReady: !!cachedExercise, cached: true };
  }

  if (quotaUserId) {
    const { data: count } = await admin.rpc("consume_ai_generation", { p_user_id: quotaUserId, p_limit: 10 });
    if (Number(count ?? 0) === 0) throw new Error("AI_DAILY_LIMIT");
  }

  const source = String(chunk.content ?? "").slice(0, 50000);
  const level = "school level appropriate for a Cameroon collège/lycée learner";
  const prompt = language === "en"
    ? `Create a short 5-minute lesson using ONLY the source text below. Do not add outside facts. ${level}. Return JSON with: title, lesson_text, and 4 multiple-choice questions. Each question must have id, question, choices (exactly 4 strings), correct_index (0-3), explanation.\n\nSOURCE:\n${source}`
    : `Crée une courte leçon de 5 minutes en utilisant UNIQUEMENT le texte source ci-dessous. N'ajoute aucun fait extérieur. Niveau scolaire adapté à un collégien/lycéen au Cameroun. Retourne un JSON avec : title, lesson_text et 4 QCM. Chaque QCM contient id, question, choices (exactement 4 chaînes), correct_index (0-3), explanation.\n\nSOURCE :\n${source}`;

  const generated = await geminiJson(apiKey, prompt);
  const title = String(generated.title ?? chunk.title ?? "Leçon du jour").slice(0, 180);
  const lessonText = String(generated.lesson_text ?? "").trim();
  const questionsRaw = Array.isArray(generated.questions) ? generated.questions.slice(0, 4) : [];
  if (!lessonText || questionsRaw.length !== 4) throw new Error("AI_INVALID_LESSON");

  const { data: lesson, error: lessonError } = await admin.from("generated_lessons").upsert({
    chunk_id: chunk.id,
    language,
    text: `${title}\n\n${lessonText}`.slice(0, 20000),
  }, { onConflict: "chunk_id,language" }).select("id,chunk_id,language,text,generated_at").single();
  if (lessonError) throw lessonError;

  const slotPlan = shuffleInPlace([0, 1, 2, 3]); // une bonne réponse par lettre A-D, ordre aléatoire
  const questions: any[] = [];
  const answerKey: Record<string, string> = {};
  const explanations: Record<string, string> = {};
  for (let i = 0; i < questionsRaw.length; i++) {
    const item = questionsRaw[i] ?? {};
    const id = String(item.id ?? `q${i + 1}`);
    const choices = Array.isArray(item.choices) ? item.choices.slice(0, 4).map((x: unknown) => String(x).slice(0, 800)) : [];
    const correct = Number(item.correct_index);
    if (choices.length !== 4 || !Number.isInteger(correct) || correct < 0 || correct > 3) throw new Error("AI_INVALID_EXERCISE");
    const arranged = arrangeChoices(choices, correct, slotPlan[i]);
    questions.push({ id, question: String(item.question ?? "").slice(0, 1200), choices: arranged.choices });
    answerKey[id] = String(arranged.correct);
    explanations[id] = String(item.explanation ?? "").slice(0, 1500);
  }

  const { error: exerciseError } = await admin.from("generated_exercises").upsert({
    lesson_id: lesson.id,
    chunk_id: chunk.id,
    language,
    questions,
    answer_key: answerKey,
    explanations,
  }, { onConflict: "lesson_id" });
  if (exerciseError) throw exerciseError;
  return { lesson, exerciseReady: true, cached: false };
}


// Mélange les choix et répartit la bonne réponse (le modèle IA la place presque toujours en A/B).
function randomInt(max: number): number {
  const buf = new Uint32Array(1);
  crypto.getRandomValues(buf);
  return buf[0] % max;
}
function shuffleInPlace<T>(items: T[]): T[] {
  for (let i = items.length - 1; i > 0; i--) {
    const j = randomInt(i + 1);
    [items[i], items[j]] = [items[j], items[i]];
  }
  return items;
}
const PINNED_LAST = /^(toutes?\s+les\s+(r[ée]ponses|options|propositions)|aucune?\s+(des|de\s+ces)|all\s+of\s+the\s+above|none\s+of\s+the\s+above)/i;
function arrangeChoices(choices: string[], correct: number, target: number): { choices: string[]; correct: number } {
  if (choices.some((c) => PINNED_LAST.test(c))) return { choices, correct };
  const order = [0, 1, 2, 3].filter((i) => i !== correct);
  shuffleInPlace(order);
  order.splice(target, 0, correct);
  return { choices: order.map((i) => choices[i]), correct: target };
}

async function normalRequest(admin: ReturnType<typeof createClient>, userId: string, body: any, apiKey: string) {
  const { data: profile, error: profileError } = await admin.from("profiles")
    .select("preferred_language,role,class_name,subsystem,sector")
    .eq("id", userId).single();
  if (profileError || !profile) throw new Error("PROFILE_UNAVAILABLE");
  if (profile.role !== "student") throw new Error("STUDENT_ONLY");

  let classId = "";
  const { data: personal } = await admin.from("student_timetable_entries")
    .select("id,subject_id,day_of_week,start_time,end_time,subject,subject_en")
    .eq("student_id", userId).order("day_of_week").order("start_time");
  const personalRows = personal ?? [];

  const { data: memberships } = await admin.from("class_students").select("class_id").eq("student_id", userId).eq("is_active", true);
  const classIds = (memberships ?? []).map((x: any) => String(x.class_id));
  if (!classIds.length) throw new Error("NO_CLASS");

  let chosenSubject = String(body?.subject_id ?? "");
  const nowCameroon = new Date(new Date().toLocaleString("en-US", { timeZone: "Africa/Douala" }));
  const currentDay = nowCameroon.getDay() === 0 ? 7 : nowCameroon.getDay();
  const currentMinutes = nowCameroon.getHours() * 60 + nowCameroon.getMinutes();

  const todayPersonal = personalRows.filter((x: any) => Number(x.day_of_week) === currentDay && String(x.start_time).slice(0, 5) >= `${String(nowCameroon.getHours()).padStart(2, "0")}:${String(nowCameroon.getMinutes()).padStart(2, "0")}`);
  if (!chosenSubject && todayPersonal.length) chosenSubject = String(todayPersonal[0].subject_id ?? "");

  if (!chosenSubject) {
    const { data: todayClass } = await admin.from("class_timetable_entries")
      .select("subject_id,subject_fr,subject_en,start_time")
      .in("class_id", classIds).eq("day_of_week", currentDay).eq("is_active", true)
      .order("start_time");
    const found = (todayClass ?? []).find((x: any) => {
      const [h, m] = String(x.start_time).slice(0, 5).split(":").map(Number);
      return h * 60 + m >= currentMinutes;
    });
    if (found) chosenSubject = String(found.subject_id ?? "");
  }

  if (!chosenSubject) {
    const { data: late } = await admin.from("student_lesson_progress")
      .select("subject_id,updated_at").eq("student_id", userId).order("updated_at").limit(1);
    chosenSubject = String(late?.[0]?.subject_id ?? "");
  }
  if (!chosenSubject) throw new Error("NO_SUBJECT");

  classId = classIds[0];
  const chunk = await getNextChunk(admin, userId, chosenSubject, classId);
  if (!chunk) return { status: "completed", subject_id: chosenSubject, message: "Aucune leçon intelligente disponible pour cette matière." };

  const language = profile.preferred_language === "en" ? "en" : "fr";
  const ensured = await ensureLesson(admin, apiKey, chunk, language, userId);
  const { data: exerciseRow } = await admin.from("generated_exercises")
    .select("questions")
    .eq("lesson_id", ensured.lesson.id)
    .maybeSingle();
  return { status: "ready", lesson: ensured.lesson, questions: exerciseRow?.questions ?? [], subject_id: chosenSubject, course_id: chunk.course_id, chunk_id: chunk.id, cached: ensured.cached };
}

async function timetableEntriesForStudent(
  admin: ReturnType<typeof createClient>,
  studentId: string,
  classId: string,
  day: number,
) {
  const { data: personal } = await admin.from("student_timetable_entries")
    .select("id,day_of_week,start_time,end_time,subject,subject_en,subject_id")
    .eq("student_id", studentId)
    .eq("day_of_week", day)
    .order("start_time");
  const personalRows = personal ?? [];
  if (personalRows.some((x: any) => x.subject_id)) return personalRows;

  const { data: classRows } = await admin.from("class_timetable_entries")
    .select("id,class_id,subject_id,subject_fr,subject_en,start_time,end_time")
    .eq("class_id", classId)
    .eq("day_of_week", day)
    .eq("is_active", true)
    .order("start_time");
  return classRows ?? [];
}

async function scheduledPrepare(admin: ReturnType<typeof createClient>, apiKey: string) {
  const now = new Date();
  const target = new Date(now.getTime() + 24 * 60 * 60 * 1000);
  const targetLocal = new Date(target.toLocaleString("en-US", { timeZone: "Africa/Douala" }));
  const day = targetLocal.getDay() === 0 ? 7 : targetLocal.getDay();
  const { data: memberships, error } = await admin.from("class_students")
    .select("student_id,class_id").eq("is_active", true);
  if (error) throw error;

  let prepared = 0;
  const seen = new Set<string>();
  for (const membership of memberships ?? []) {
    const studentId = String(membership.student_id);
    const classId = String(membership.class_id);
    if (seen.has(studentId)) continue;
    seen.add(studentId);

    const entries = await timetableEntriesForStudent(admin, studentId, classId, day);
    const { data: profile } = await admin.from("profiles")
      .select("preferred_language").eq("id", studentId).maybeSingle();
    const language = profile?.preferred_language === "en" ? "en" : "fr";

    for (const entry of entries as any[]) {
      const subjectId = entry.subject_id ? String(entry.subject_id) : "";
      if (!subjectId) continue;
      try {
        const chunk = await getNextChunk(admin, studentId, subjectId, classId);
        if (!chunk) continue;
        const result = await ensureLesson(admin, apiKey, chunk, language, studentId);
        if (!result.cached) prepared++;
      } catch {
        // One student/slot must not block preparation for the rest.
      }
    }
  }
  return { status: "prepared", count: prepared, day };
}

async function scheduledNotify(admin: ReturnType<typeof createClient>) {
  const nowCameroon = new Date(new Date().toLocaleString("en-US", { timeZone: "Africa/Douala" }));
  const day = nowCameroon.getDay() === 0 ? 7 : nowCameroon.getDay();
  const currentMinutes = nowCameroon.getHours() * 60 + nowCameroon.getMinutes();
  const { data: memberships } = await admin.from("class_students")
    .select("student_id,class_id").eq("is_active", true);
  let sent = 0;

  const seen = new Set<string>();
  for (const membership of memberships ?? []) {
    const studentId = String(membership.student_id);
    const classId = String(membership.class_id);
    if (seen.has(studentId)) continue;
    seen.add(studentId);

    const entries = await timetableEntriesForStudent(admin, studentId, classId, day);
    for (const entry of entries as any[]) {
      const [h, m] = String(entry.start_time).slice(0, 5).split(":").map(Number);
      const diff = h * 60 + m - currentMinutes;
      if (diff < 28 || diff > 32) continue;
      if (!entry.subject_id) continue;

      const occurrence = nowCameroon.toISOString().slice(0, 10);
      const { error: insertError } = await admin.from("smart_lesson_notifications").insert({
        student_id: studentId, timetable_entry_id: entry.id, occurrence_date: occurrence,
      });
      if (insertError?.code === "23505") continue;
      if (insertError) continue;

      const { data: profile } = await admin.from("profiles")
        .select("preferred_language").eq("id", studentId).maybeSingle();
      const english = profile?.preferred_language === "en";
      const subject = String(english ? (entry.subject_en || entry.subject_fr || entry.subject || "Subject") : (entry.subject_fr || entry.subject || entry.subject_en || "Matière"));
      const { error: notificationError } = await admin.from("notifications").insert({
        user_id: studentId,
        title: english ? "Next class" : "Prochain cours",
        body: english ? `${subject} — lesson ready` : `${subject} — leçon prête`,
        type: "smart_lesson",
      });
      if (!notificationError) sent++;
    }
  }
  return { status: "notified", count: sent };
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey || !geminiKey) return json({ error: "Configuration missing." }, 500);

  try {
    const body = await req.json().catch(() => ({}));
    const mode = String(body?.mode ?? "student");
    const admin = createClient(supabaseUrl, serviceKey);

    if (mode === "prepare" || mode === "notify") {
      const secret = Deno.env.get("SMART_LESSON_CRON_SECRET");
      if (!secret || req.headers.get("x-cron-secret") !== secret) return json({ error: "Unauthorized." }, 401);
      return json(mode === "prepare" ? await scheduledPrepare(admin, geminiKey) : await scheduledNotify(admin));
    }

    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return json({ error: "Authentication required." }, 401);
    const token = auth.slice("Bearer ".length).trim();
    const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
    const { data: authData, error: authError } = await userClient.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Invalid session." }, 401);
    try {
      return json(await normalRequest(admin, authData.user.id, body, geminiKey));
    } catch (error) {
      const message = error instanceof Error ? error.message : "Daily lesson failed.";
      const lang = body?.language === "en" ? "en" : "fr";
      if (message === "AI_DAILY_LIMIT") return json({ error: lang === "en" ? "Daily AI generation limit reached (10)." : "Limite quotidienne de 10 générations IA atteinte." }, 429);
      if (message === "AI_INVALID_LESSON" || message === "AI_INVALID_EXERCISE") return json({ error: lang === "en" ? "The smart lesson could not be generated. Try again later." : "La leçon intelligente n'a pas pu être générée. Réessayez plus tard." }, 502);
      return json({ error: lang === "en" ? "The daily lesson is temporarily unavailable." : "La leçon du jour est temporairement indisponible." }, 500);
    }
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unknown error." }, 500);
  }
});
