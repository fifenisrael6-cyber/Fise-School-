// Envoie une notification push (FCM HTTP v1) quand une ligne est insérée dans public.notifications.
// Déclenchée par un Database Webhook Supabase (INSERT sur notifications).
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

function b64url(input: string | ArrayBuffer): string {
  const bytes = typeof input === "string" ? new TextEncoder().encode(input) : new Uint8Array(input);
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function getAccessToken(sa: { client_email: string; private_key: string }): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const unsigned = `${b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${b64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }))}`;
  const pem = sa.private_key.replace(/-----[^-]+-----/g, "").replace(/\s+/g, "");
  const der = Uint8Array.from(atob(pem), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, new TextEncoder().encode(unsigned));
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${unsigned}.${b64url(signature)}`,
    }),
  });
  const data = await response.json();
  if (!response.ok || !data.access_token) {
    throw new Error(`OAuth Google refusé: ${JSON.stringify(data)}`);
  }
  return data.access_token as string;
}

serve(async (req) => {
  try {
    const secret = Deno.env.get("PUSH_WEBHOOK_SECRET");
    if (!secret || req.headers.get("x-webhook-secret") !== secret) {
      return new Response("Unauthorized", { status: 401 });
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const saRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
    if (!supabaseUrl || !serviceKey || !saRaw) {
      return new Response("Configuration push manquante.", { status: 500 });
    }

    const payload = await req.json();
    const record = payload?.record;
    if (payload?.type !== "INSERT" || !record?.user_id) {
      return new Response("Ignoré", { status: 200 });
    }

    const admin = createClient(supabaseUrl, serviceKey);
    const { data: tokens, error } = await admin
      .from("device_tokens")
      .select("token")
      .eq("user_id", record.user_id);
    if (error) return new Response(`Lecture des jetons impossible: ${error.message}`, { status: 500 });
    if (!tokens || tokens.length === 0) return new Response("Aucun appareil", { status: 200 });

    const sa = JSON.parse(saRaw);
    const accessToken = await getAccessToken(sa);
    const endpoint = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;

    let sent = 0;
    for (const { token } of tokens) {
      const res = await fetch(endpoint, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token,
            notification: {
              title: String(record.title ?? "Fise School").slice(0, 180),
              body: String(record.body ?? "").slice(0, 500),
            },
            data: { type: String(record.type ?? "info"), notification_id: String(record.id ?? "") },
            android: { priority: "HIGH" },
          },
        }),
      });
      if (res.ok) {
        sent++;
      } else if (res.status === 404 || res.status === 400) {
        // Jeton périmé : on le supprime pour ne plus y envoyer.
        const detail = await res.text();
        if (detail.includes("UNREGISTERED") || detail.includes("NOT_FOUND")) {
          await admin.from("device_tokens").delete().eq("token", token);
        }
      }
    }
    return new Response(JSON.stringify({ sent }), { status: 200, headers: { "Content-Type": "application/json" } });
  } catch (e) {
    return new Response(`Erreur: ${e instanceof Error ? e.message : String(e)}`, { status: 500 });
  }
});
