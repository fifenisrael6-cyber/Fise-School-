import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const MAX_ATTACHMENT_BYTES = 8 * 1024 * 1024;
const ALLOWED_MIME = new Set([
  "application/pdf",
  "text/plain",
  "text/markdown",
  "text/csv",
  "image/jpeg",
  "image/png",
  "image/webp",
]);

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function normalizeSearchText(value: string) {
  return value
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

const SEARCH_STOP_WORDS = new Set([
  "a", "ai", "au", "aux", "avec", "ce", "ces", "cette", "dans", "de", "des",
  "du", "elle", "en", "et", "est", "je", "la", "le", "les", "ma", "mais",
  "me", "mon", "ne", "nos", "notre", "nous", "on", "ou", "par", "pas",
  "pour", "que", "quel", "quelle", "quels", "quelles", "qui", "sa", "se",
  "son", "sur", "ta", "te", "tes", "ton", "tu", "un", "une", "vos", "votre",
  "vous", "the", "this", "that", "and", "are", "can", "how", "what", "when",
  "where", "why", "with", "from", "for", "is", "of", "to", "in", "my", "your",
]);

function searchTerms(value: string) {
  return [...new Set(
    normalizeSearchText(value)
      .split(" ")
      .filter((word) => word.length >= 3 && !SEARCH_STOP_WORDS.has(word)),
  )].slice(0, 24);
}

async function findStudentCourseContext(
  admin: ReturnType<typeof createClient>,
  userId: string,
  question: string,
  language: string,
) {
  const terms = searchTerms(question);
  if (!terms.length) return { found: false, context: "" };

  const { data: memberships, error: membershipError } = await admin
    .from("class_students")
    .select("class_id")
    .eq("student_id", userId)
    .eq("is_active", true);

  if (membershipError) throw membershipError;
  const classIds = [...new Set((memberships ?? []).map((row: any) => String(row.class_id)).filter(Boolean))];
  if (!classIds.length) return { found: false, context: "" };

  // Scan every approved/indexed chunk belonging to the student's active classes.
  // Relevance is computed locally before anything is sent to Gemini.
  const { data: chunks, error: chunkError } = await admin
    .from("course_chunks")
    .select("id,class_id,subject_id,title,content,language,position,courses!inner(id,title_fr,title_en,status),course_resources!inner(index_status,index_approved)")
    .in("class_id", classIds)
    .eq("course_resources.index_status", "indexed")
    .eq("course_resources.index_approved", true)
    .eq("courses.status", "published")
    .limit(120);

  if (chunkError) throw chunkError;

  const scored = (chunks ?? [])
    .map((row: any) => {
      const title = language === "en" ? String(row.courses?.title_en ?? row.title ?? "") : String(row.courses?.title_fr ?? row.title ?? "");
      const content = String(row.content ?? "");
      const haystack = normalizeSearchText(title + " " + content);
      let score = 0;
      for (const term of terms) {
        if (haystack.includes(term)) score += 1;
        if (normalizeSearchText(title).includes(term)) score += 3;
      }
      const phrase = normalizeSearchText(question);
      if (phrase.length >= 12 && haystack.includes(phrase)) score += 12;
      return { row, score, title, content };
    })
    .filter((item) => item.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, 8);

  if (!scored.length) return { found: false, context: "" };

  const context = scored
    .map((item, index) => {
      const clipped = item.content.slice(0, 6000);
      return [
        `[Cours ${index + 1}]`,
        `Titre: ${item.title}`,
        `Contenu: ${clipped}`,
      ].join("\n");
    })
    .join("\n\n");

  return { found: true, context };
}

function cleanHistory(value: unknown) {
  if (!Array.isArray(value)) return [];
  return value
    .filter((item) => item && typeof item === "object")
    .slice(-20)
    .map((item: Record<string, unknown>) => ({
      role: item.role === "model" ? "model" : "user",
      text: String(item.text ?? "").trim().slice(0, 12000),
    }))
    .filter((item) => item.text.length > 0);
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) {
      return json({ error: "Authentication required." }, 401);
    }

    const accessToken = authHeader.slice("Bearer ".length).trim();
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const apiKey = Deno.env.get("GEMINI_API_KEY");

    if (!supabaseUrl || !supabaseAnonKey) {
      return json({ error: "Supabase authentication is not configured." }, 500);
    }
    if (!apiKey) return json({ error: "GEMINI_API_KEY is not configured." }, 500);

    // Verify the actual Supabase access token. Merely checking for a Bearer
    // header is not authentication.
    const userClient = createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: `Bearer ${accessToken}` } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: userError } = await userClient.auth.getUser(accessToken);
    if (userError || !userData.user) return json({ error: "Invalid or expired session." }, 401);

    const { data: profile, error: profileError } = await userClient
      .from("profiles")
      .select("first_name,last_name,preferred_language,subsystem,sector,class_name,exam_level_label,exam_label,role")
      .eq("id", userData.user.id)
      .maybeSingle();
    if (profileError || !profile) return json({ error: "School profile unavailable." }, 403);

    const body = await req.json();
    const message = String(body?.message ?? "").trim().slice(0, 12000);
    const language = profile.preferred_language === "en" ? "en" : "fr";
    const attachment = body?.attachment;

    if (!message && !attachment?.base64) {
      return json({ error: language === "fr"
        ? "Écris une question ou joins un document avant d'envoyer."
        : "Write a question or attach a document before sending." }, 400);
    }

    const isIncompleteExercisePrompt = /^(?:help me solve this exercise step by step|aide[- ]moi à résoudre cet exercice étape par étape)\s*:?\s*$/i;
    if (!attachment?.base64 && isIncompleteExercisePrompt.test(message)) {
      return json({ error: language === "fr"
        ? "Écris l'énoncé de l'exercice ou joins une photo/PDF avant d'envoyer."
        : "Write the exercise statement or attach a photo/PDF before sending." }, 400);
    }

    let attachmentPart: Record<string, unknown> | null = null;
    if (attachment?.base64) {
      const mime = String(attachment.mimeType ?? "application/octet-stream").toLowerCase();
      const base64 = String(attachment.base64);
      if (!ALLOWED_MIME.has(mime)) {
        return json({ error: language === "fr"
          ? "Type de fichier non pris en charge. Utilise une image, un PDF ou un fichier texte."
          : "Unsupported file type. Use an image, PDF, or text file." }, 400);
      }
      // Base64 is roughly 4/3 of the binary size.
      if (Math.ceil(base64.length * 3 / 4) > MAX_ATTACHMENT_BYTES) {
        return json({ error: language === "fr"
          ? "Fichier trop volumineux. La limite est de 8 Mo."
          : "File is too large. The limit is 8 MB." }, 413);
      }
      attachmentPart = {
        inline_data: { mime_type: mime, data: base64 },
      };
    }

    let courseSearch = { found: false, context: "" };
    try {
      courseSearch = await findStudentCourseContext(
      createClient(supabaseUrl, supabaseAnonKey, {
        global: { headers: { Authorization: `Bearer ${accessToken}` } },
        auth: { persistSession: false, autoRefreshToken: false },
      }),
      userData.user.id,
      message,
      language,
    );
    } catch {
      // Course search is optional and must never block the AI.
    }

    const courseContextInstruction = courseSearch.found
      ? (language === "en"
          ? `FIRST PRIORITY — the student's own Fise School courses were searched before Gemini. Use the course excerpts below as the authoritative source for the answer. Do not add facts that contradict them. If the excerpts do not actually answer the question, say so clearly instead of pretending they do.
\\n\\nSTUDENT COURSE EXCERPTS:\\n${courseSearch.context}`
          : `PRIORITÉ ABSOLUE — les cours Fise School de l'élève ont été parcourus avant Gemini. Utilise les extraits de ses cours ci-dessous comme source principale et fiable pour répondre. N'ajoute pas de faits qui les contredisent. Si les extraits ne répondent pas réellement à la question, dis-le clairement au lieu de faire semblant.
\\n\\nEXTRAITS DES COURS DE L'ÉLÈVE :\\n${courseSearch.context}`)
      : (language === "en"
          ? `The student's indexed Fise School courses were searched first, but no relevant course passage was found for this question. You may answer from your general educational knowledge, and clearly indicate when the answer is not from the student's courses.`
          : `Les cours Fise School indexés de l'élève ont été parcourus en premier, mais aucun passage pertinent n'a été trouvé pour cette question. Tu peux alors répondre avec tes connaissances éducatives générales, en indiquant clairement que la réponse ne vient pas de ses cours.`);

    const schoolContext = language === "en"
      ? `You are Fise School AI, an educational assistant for Cameroon.
Authenticated student/teacher profile: first name=${profile.first_name ?? "unknown"}, role=${profile.role ?? "unknown"}, subsystem=${profile.subsystem ?? "unknown"}, sector=${profile.sector ?? "unknown"}, class=${profile.class_name ?? "unknown"}, exam level=${profile.exam_level_label ?? "unknown"}, exam=${profile.exam_label ?? "unknown"}.
Teach clearly and accurately at the user's school level. When solving schoolwork, explain the reasoning instead of only giving a result. Never invent a Fise School course or curriculum detail. ${courseContextInstruction}`
      : `Tu es Fise School AI, un assistant éducatif pour le Cameroun.
Profil authentifié : prénom=${profile.first_name ?? "inconnu"}, rôle=${profile.role ?? "inconnu"}, sous-système=${profile.subsystem ?? "inconnu"}, secteur=${profile.sector ?? "inconnu"}, classe=${profile.class_name ?? "inconnue"}, niveau d'examen=${profile.exam_level_label ?? "inconnu"}, examen=${profile.exam_label ?? "inconnu"}.
Explique clairement et correctement au niveau scolaire de l'utilisateur. Pour un exercice, explique le raisonnement et pas seulement le résultat. N'invente jamais un détail de programme ou de cours Fise School. ${courseContextInstruction}`;

    const history = cleanHistory(body?.history);
    const contents: Record<string, unknown>[] = history.map((item) => ({
      role: item.role,
      parts: [{ text: item.text }],
    }));
    const currentParts: Record<string, unknown>[] = [];
    if (attachmentPart) currentParts.push(attachmentPart);
    if (message) currentParts.push({ text: message });
    contents.push({ role: "user", parts: currentParts });

    // Discover models enabled for this API key instead of relying on retired model names.
    const configuredModel = Deno.env.get("GEMINI_MODEL")?.trim().replace(/^models\//, "");
    let models: string[] = [];
    try {
      const listController = new AbortController();
      const listTimeout = setTimeout(() => listController.abort(), 10000);
      try {
        const listResponse = await fetch(
          "https://generativelanguage.googleapis.com/v1beta/models?pageSize=100",
          { headers: { "x-goog-api-key": apiKey }, signal: listController.signal },
        );
        const listData = await listResponse.json().catch(() => ({}));
        if (!listResponse.ok) {
          const safeBody = JSON.stringify(listData ?? {}).replaceAll(apiKey, "[REDACTED]").slice(0, 1500);
          console.error("[gemini-chat] Gemini model discovery failed", JSON.stringify({ status: listResponse.status, body: safeBody }));
        } else {
          const available = (Array.isArray(listData?.models) ? listData.models : [])
            .filter((item: any) => Array.isArray(item.supportedGenerationMethods)
              && item.supportedGenerationMethods.includes("generateContent"))
            .map((item: any) => String(item.name ?? "").replace(/^models\//, ""))
            .filter((name: string) => name.length > 0);
          const preferred = [
            ...(configuredModel ? [configuredModel] : []),
            ...available.filter((name: string) => /flash/i.test(name) && !/tts|image|embedding|robotics/i.test(name)),
            ...available.filter((name: string) => !/tts|image|embedding|robotics/i.test(name)),
          ];
          models = [...new Set(preferred)].slice(0, 3);
        }
      } finally {
        clearTimeout(listTimeout);
      }
    } catch (error) {
      console.error("[gemini-chat] Gemini model discovery exception", error instanceof Error ? error.message : String(error));
    }
    if (!models.length) {
      models = [...new Set([...(configuredModel ? [configuredModel] : []), "gemini-2.5-flash", "gemini-2.0-flash"])];
    }

    let data: any = null;
    let lastError = "Gemini request failed.";
    for (const model of models) {
      const controller = new AbortController();
      const timeout = setTimeout(() => controller.abort(), 18000);
      try {
        const response = await fetch(
          `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
          {
            method: "POST",
            headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
            body: JSON.stringify({
              systemInstruction: { parts: [{ text: schoolContext }] },
              contents,
              generationConfig: { maxOutputTokens: 1536 },
            }),
            signal: controller.signal,
          },
        );
        data = await response.json().catch(() => ({}));
        if (response.ok) break;
        const safeProviderBody = JSON.stringify(data ?? {}).replaceAll(apiKey, "[REDACTED]").slice(0, 4000);
        console.error("[gemini-chat] AI provider HTTP error", JSON.stringify({ model, status: response.status, body: safeProviderBody }));
        lastError = `Gemini HTTP ${response.status}: ${data?.error?.message ?? safeProviderBody}`;
        if (![404, 429, 500, 502, 503, 504].includes(response.status)) break;
      } catch (error) {
        lastError = error instanceof DOMException && error.name === "AbortError"
          ? `Gemini request timed out on ${model}.`
          : (error instanceof Error ? error.message : "Gemini request failed.");
        console.error("[gemini-chat] Gemini request exception", JSON.stringify({ model, message: lastError.slice(0, 1500) }));
      } finally {
        clearTimeout(timeout);
      }
    }

    if (!data?.candidates?.length) {
      throw new Error(lastError);
    }

    const text = data?.candidates?.[0]?.content?.parts
      ?.map((part: { text?: string }) => part.text ?? "")
      .join("")
      .trim();

    if (!text) throw new Error("Gemini returned an empty response.");
    return json({ text });
  } catch (error) {
    const detail = error instanceof Error ? error.message : String(error);
    // Never log request headers or the provider API key. Error details are capped.
    console.error("[gemini-chat] request failed:", detail.replaceAll(Deno.env.get("GEMINI_API_KEY") ?? "\u0000", "[REDACTED]").slice(0, 2000));
    if (/timeout|aborted|timed out/i.test(detail)) {
      return json({ error: "AI_REQUEST_TIMEOUT" }, 504);
    }
    if (/429|quota|resource exhausted|rate limit/i.test(detail)) {
      return json({ error: "AI_QUOTA_EXCEEDED" }, 429);
    }
    if (/401|403|api.?key|permission denied|not configured/i.test(detail)) {
      return json({ error: "AI_PROVIDER_CONFIGURATION_ERROR" }, 502);
    }
    if (/404|model.*not found|not found.*model|unsupported model/i.test(detail)) {
      return json({ error: "AI_MODEL_CONFIGURATION_ERROR" }, 502);
    }
    if (/failed to fetch|network|connection|dns|socket/i.test(detail)) {
      return json({ error: "AI_UPSTREAM_NETWORK_ERROR" }, 502);
    }
    return json({ error: "AI_UPSTREAM_ERROR" }, 502);
  }
});
