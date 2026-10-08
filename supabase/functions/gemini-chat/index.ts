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
    const mode = String(body?.mode ?? 'student').toLowerCase() === 'admin' ? 'admin' : 'student';
    const schoolContext = body?.schoolContext && typeof body.schoolContext === 'object' ? body.schoolContext : null;
    if (mode === 'admin' && profile.role !== 'admin') {
      return json({ error: language === 'fr' ? 'Accès réservé à l’administrateur.' : 'Administrator access required.' }, 403);
    }

    if (!message && !attachment?.base64) {
      return json({ error: "A message or attachment is required." }, 400);
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

    const contextText = schoolContext ? JSON.stringify(schoolContext).slice(0, 20000) : '';
    const systemPrompt = language === "en"
      ? `You are Fise School AI, an educational assistant for Cameroon.
Authenticated profile: first name=${profile.first_name ?? "unknown"}, role=${profile.role ?? "unknown"}, subsystem=${profile.subsystem ?? "unknown"}, sector=${profile.sector ?? "unknown"}, class=${profile.class_name ?? "unknown"}, exam level=${profile.exam_level_label ?? "unknown"}, exam=${profile.exam_label ?? "unknown"}.
${mode === 'admin'
  ? 'You are in ADMIN PEDAGOGICAL MODE. Help the administrator create, improve, structure and adapt lessons, exercises, QCM and corrections for a selected classroom. Produce ready-to-use school content, but never invent an official Cameroon curriculum reference when it is not supplied. Clearly label suggestions that require validation.'
  : 'You are in STUDENT MODE. Explain school subjects like a teacher: definition, explanation, formula/rule when relevant, method, worked example, correction, then a short summary. Adapt vocabulary and difficulty to the authenticated school level.'}
Use the Cameroon school context when supplied. Do not invent Fise School database facts. If curriculum information is missing, say so and provide a clearly marked general pedagogical explanation.
${contextText ? `Current Fise School context: ${contextText}` : ''}`
      : `Tu es Fise School AI, assistant pédagogique pour le Cameroun.
Profil authentifié : prénom=${profile.first_name ?? "inconnu"}, rôle=${profile.role ?? "inconnu"}, sous-système=${profile.subsystem ?? "inconnu"}, secteur=${profile.sector ?? "inconnu"}, classe=${profile.class_name ?? "inconnue"}, niveau d'examen=${profile.exam_level_label ?? "inconnu"}, examen=${profile.exam_label ?? "inconnu"}.
${mode === 'admin'
  ? 'MODE ADMINISTRATEUR PÉDAGOGIQUE : aide à créer, améliorer, structurer et adapter des leçons, exercices, QCM et corrigés pour une salle choisie. Génère un contenu directement exploitable à l’école, mais n’invente jamais une référence officielle du programme camerounais non fournie. Signale clairement ce qui doit être validé.'
  : 'MODE ÉLÈVE : explique les matières comme un enseignant : définition, explication, formule/règle si nécessaire, méthode, exemple résolu, correction, puis résumé court. Adapte le vocabulaire et la difficulté au niveau scolaire authentifié.'}
Utilise le contexte scolaire camerounais lorsqu’il est fourni. N’invente jamais les données de la base Fise School. Si une information du programme manque, dis-le et donne une explication pédagogique générale clairement signalée.
${contextText ? `Contexte Fise School actuel : ${contextText}` : ''}`;

    const history = cleanHistory(body?.history);
    const contents: Record<string, unknown>[] = history.map((item) => ({
      role: item.role,
      parts: [{ text: item.text }],
    }));
    const currentParts: Record<string, unknown>[] = [];
    if (attachmentPart) currentParts.push(attachmentPart);
    if (message) currentParts.push({ text: message });
    contents.push({ role: "user", parts: currentParts });

    const model = Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash";
    const response = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`,
      {
        method: "POST",
        headers: {
          "x-goog-api-key": apiKey,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          systemInstruction: { parts: [{ text: systemPrompt }] },
          contents,
          generationConfig: { temperature: 0.4 },
        }),
      },
    );

    const data = await response.json();
    if (!response.ok) {
      throw new Error(data?.error?.message ?? "Gemini request failed.");
    }

    const text = data?.candidates?.[0]?.content?.parts
      ?.map((part: { text?: string }) => part.text ?? "")
      .join("")
      .trim();

    if (!text) throw new Error("Gemini returned an empty response.");
    return json({ text });
  } catch (error) {
    return json({
      error: error instanceof Error ? error.message : "Unknown error",
    }, 500);
  }
});
