import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Content-Type": "application/json",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return json({ error: "Authentication required" }, 401);
    }
    const token = authorization.slice("Bearer ".length).trim();
    const url = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!url || !anonKey || !serviceRoleKey) {
      return json({ error: "Supabase function secrets are not configured" }, 500);
    }

    const caller = createClient(url, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: userData, error: authError } = await caller.auth.getUser(token);
    if (authError || !userData.user) return json({ error: "Invalid session" }, 401);

    const body = await request.json();
    const messageId = body.message_id;
    const kind = body.kind;
    if (typeof messageId !== "string" || !/^[0-9a-f-]{36}$/i.test(messageId)) {
      return json({ error: "Invalid message id" }, 400);
    }
    if (kind !== "private" && kind !== "group") return json({ error: "Invalid message kind" }, 400);

    const rpcName = kind === "private"
      ? "claim_private_message_view_once"
      : "claim_group_message_view_once";
    const { data: path, error: claimError } = await caller.rpc(rpcName, { p_message_id: messageId });
    if (claimError || typeof path !== "string" || path.length === 0) {
      return json({ error: claimError?.message ?? "Attachment unavailable" }, 403);
    }

    const bucket = kind === "private"
      ? "private-message-attachments"
      : "group-message-attachments";
    const admin = createClient(url, serviceRoleKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: signed, error: signError } = await admin.storage.from(bucket).createSignedUrl(path, 60);
    if (signError || !signed?.signedUrl) return json({ error: "Could not create a temporary attachment URL" }, 500);

    return json({ url: signed.signedUrl, expiresIn: 60 });
  } catch (error) {
    return json({
      error: error instanceof Error ? error.message : "Unexpected server error",
    }, 500);
  }
});
