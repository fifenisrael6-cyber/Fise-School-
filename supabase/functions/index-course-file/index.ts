import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import * as pdfjsLib from "npm:pdfjs-dist@4.10.38/legacy/build/pdf.mjs";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function splitWords(text: string, target = 700) {
  const words = text.replace(/\s+/g, " ").trim().split(" ").filter(Boolean);
  const chunks: { title: string; content: string }[] = [];
  let buffer: string[] = [];
  for (const word of words) {
    buffer.push(word);
    if (buffer.length >= target) {
      chunks.push({ title: `Leçon ${chunks.length + 1}`, content: buffer.join(" ") });
      buffer = [];
    }
  }
  if (buffer.length > 0) chunks.push({ title: `Leçon ${chunks.length + 1}`, content: buffer.join(" ") });
  return chunks;
}

async function extractPdfText(bytes: Uint8Array): Promise<string> {
  try {
    // pdfjs is used only for native text extraction. Scanned PDFs fall back to Gemini below.
    const document = await pdfjsLib.getDocument({ data: bytes, disableWorker: true, useSystemFonts: true }).promise;
    const pages: string[] = [];
    for (let pageNumber = 1; pageNumber <= document.numPages; pageNumber++) {
      const page = await document.getPage(pageNumber);
      const content = await page.getTextContent();
      const text = content.items
        .map((item: unknown) => (item && typeof item === "object" && "str" in item ? String((item as { str?: unknown }).str ?? "") : ""))
        .join(" ")
        .replace(/\s+/g, " ")
        .trim();
      if (text) pages.push(text);
    }
    return pages.join("\n\n");
  } catch {
    return "";
  }
}

async function transcribeWithGemini(bytes: Uint8Array, mime: string, language: string, apiKey: string) {
  let binary = "";
  const chunkSize = 0x8000;
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  const base64 = btoa(binary);
  const prompt = language === "en"
    ? "Read the educational document image or PDF accurately. Return only the complete readable text, preserving headings, formulas, lists and examples. Do not summarize or invent content."
    : "Lis fidèlement l'image ou le PDF pédagogique. Retourne uniquement le texte complet et lisible, en conservant titres, formules, listes et exemples. Ne résume pas et n'invente rien.";

  const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${Deno.env.get("GEMINI_MODEL") ?? "gemini-2.5-flash"}:generateContent`, {
    method: "POST",
    headers: { "x-goog-api-key": apiKey, "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{ role: "user", parts: [
        { text: prompt },
        { inline_data: { mime_type: mime || "application/pdf", data: base64 } },
      ] }],
      generationConfig: { temperature: 0.0 },
    }),
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data?.error?.message ?? "Gemini transcription failed.");
  const text = data?.candidates?.[0]?.content?.parts?.map((part: { text?: string }) => part.text ?? "").join("\n").trim();
  if (!text) throw new Error("Gemini returned an empty transcription.");
  return text;
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  let requestedResourceId = "";
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const geminiKey = Deno.env.get("GEMINI_API_KEY");
  if (!supabaseUrl || !anonKey || !serviceKey) return json({ error: "Supabase configuration missing." }, 500);
  if (!geminiKey) return json({ error: "GEMINI_API_KEY is not configured." }, 500);

  try {
    const auth = req.headers.get("Authorization") ?? "";
    if (!auth.startsWith("Bearer ")) return json({ error: "Authentication required." }, 401);
    const token = auth.slice("Bearer ".length).trim();
    const userClient = createClient(supabaseUrl, anonKey, { global: { headers: { Authorization: `Bearer ${token}` } } });
    const { data: authData, error: authError } = await userClient.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Invalid session." }, 401);

    const body = await req.json();
    const resourceId = String(body?.resource_id ?? "").trim();
    requestedResourceId = resourceId;
    if (!resourceId) return json({ error: "resource_id is required." }, 400);

    const admin = createClient(supabaseUrl, serviceKey);
    const { data: resource, error: resourceError } = await admin
      .from("course_resources")
      .select("id,course_id,resource_type,storage_path,file_name,mime_type,file_size,index_status")
      .eq("id", resourceId)
      .single();
    if (resourceError || !resource) return json({ error: "Resource not found." }, 404);
    const mime = String(resource.mime_type ?? "").toLowerCase();
    const isPdf = resource.resource_type === "pdf" || mime === "application/pdf";
    const isImage = resource.resource_type === "image" && ["image/jpeg", "image/png", "image/webp"].includes(mime);
    if (!isPdf && !isImage) {
      return json({ error: "Only PDF, JPEG, PNG, and WebP course resources can be indexed." }, 400);
    }

    const { data: course, error: courseError } = await admin
      .from("courses")
      .select("id,class_id,subject_id,teacher_id,status,smart_lesson_enabled")
      .eq("id", resource.course_id)
      .single();
    if (courseError || !course) return json({ error: "Course not found." }, 404);
    if (!course.class_id) return json({ error: "This course is not attached to a class." }, 400);

    const { data: adminProfile } = await userClient.from("profiles").select("role").eq("id", authData.user.id).maybeSingle();
    const isAdmin = adminProfile?.role === "admin";
    const { data: assignment } = await admin.from("class_teachers")
      .select("class_id")
      .eq("class_id", course.class_id)
      .eq("teacher_id", authData.user.id)
      .eq("is_active", true)
      .maybeSingle();
    const allowedTeacher = !!assignment || course.teacher_id === authData.user.id;
    if (!isAdmin && !allowedTeacher) {
      return json({ error: "Not allowed." }, 403);
    }

    await admin.from("course_resources").update({
      index_status: "pending",
      index_error: null,
      index_preview: null,
      index_word_count: 0,
      index_approved: false,
      indexed_at: null,
    }).eq("id", resourceId);

    const { data: file, error: fileError } = await admin.storage.from("course-resources").download(resource.storage_path);
    if (fileError || !file) throw new Error(fileError?.message ?? "Unable to download the PDF.");
    const bytes = new Uint8Array(await file.arrayBuffer());
    if (bytes.length > 8 * 1024 * 1024) {
      throw new Error("The file is too large to index. The limit is 8 MB.");
    }
    const { data: actorProfile } = await userClient.from("profiles").select("preferred_language").eq("id", authData.user.id).maybeSingle();
    const bodyLanguage = body?.language == null ? actorProfile?.preferred_language : body.language;
    const preferredLanguage = String(bodyLanguage ?? "fr") === "en" ? "en" : "fr";

    let text = isPdf ? await extractPdfText(bytes) : "";
    if (text.replace(/\s+/g, " ").trim().length < 300) {
      text = await transcribeWithGemini(bytes, mime || (isPdf ? "application/pdf" : "image/jpeg"), preferredLanguage, geminiKey);
    }

    const chunks = splitWords(text, 700).filter((x) => x.content.trim().length >= 120);
    if (!chunks.length) throw new Error("No readable educational text was found in the PDF.");

    await admin.from("course_chunks").delete().eq("resource_id", resourceId);
    const rows = chunks.flatMap((chunk, index) => [{
      course_id: course.id,
      resource_id: resourceId,
      class_id: course.class_id,
      subject_id: course.subject_id,
      position: index,
      title: chunk.title,
      content: chunk.content,
      language: preferredLanguage,
    }]);
    const { error: insertError } = await admin.from("course_chunks").insert(rows);
    if (insertError) throw insertError;

    const preview = chunks.slice(0, 2).map((x) => `${x.title}\n${x.content}`).join("\n\n").slice(0, 6000);
    const { error: updateError } = await admin.from("course_resources").update({
      index_status: "indexed",
      index_error: null,
      index_preview: preview,
      index_word_count: text.split(/\s+/).filter(Boolean).length,
      index_approved: false,
      indexed_at: new Date().toISOString(),
    }).eq("id", resourceId);
    if (updateError) throw updateError;

    return json({ status: "indexed", resource_id: resourceId, chunks: chunks.length, approved: false });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Indexing failed.";
    try {
      const supabaseUrl2 = Deno.env.get("SUPABASE_URL");
      const serviceKey2 = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      if (requestedResourceId && supabaseUrl2 && serviceKey2) {
        const admin = createClient(supabaseUrl2, serviceKey2);
        await admin.from("course_resources").update({ index_status: "failed", index_error: message.slice(0, 1000) }).eq("id", requestedResourceId);
      }
    } catch {
      // Keep the original error response.
    }
    return json({ error: message }, 500);
  }
});
