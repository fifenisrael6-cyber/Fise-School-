import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Method not allowed." }, 405);

  try {
    const authorization = req.headers.get("Authorization");
    if (!authorization?.startsWith("Bearer ")) {
      return json({ error: "Authentication required." }, 401);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const anonKey = Deno.env.get("SUPABASE_ANON_KEY");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    if (!supabaseUrl || !anonKey || !serviceKey) {
      return json({ error: "Supabase function configuration is incomplete." }, 500);
    }

    const admin = createClient(supabaseUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const token = authorization.substring("Bearer ".length);
    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Invalid session." }, 401);

    const body = await req.json().catch(() => ({}));
    const messageId = typeof body?.message_id === "string" ? body.message_id.trim() : "";
    const scope = body?.scope === "private" || body?.scope === "group" ? body.scope : null;
    if (!/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(messageId) || !scope) {
      return json({ error: "Invalid view-once request." }, 400);
    }

    // The user's JWT is deliberately used for the claim RPC. The database
    // validates membership/recipient identity and consumes the view exactly once.
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authorization } },
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const rpc = scope === "private"
      ? "claim_private_message_view_once"
      : "claim_group_message_view_once";
    const { data: storagePath, error: claimError } = await userClient.rpc(rpc, {
      p_message_id: messageId,
    });
    if (claimError || typeof storagePath !== "string" || storagePath.length === 0) {
      return json({ error: "This attachment is unavailable or has already been opened." }, 409);
    }

    const bucket = scope === "private"
      ? "private-message-attachments"
      : "group-message-attachments";
    const { data: signed, error: signError } = await admin.storage
      .from(bucket)
      .createSignedUrl(storagePath, 300);

    if (signError || !signed?.signedUrl) {
      return json({ error: "Unable to open this attachment." }, 410);
    }

    return json({ url: signed.signedUrl, expires_in: 300 });
  } catch (_) {
    return json({ error: "Unable to open this attachment." }, 500);
  }
});
