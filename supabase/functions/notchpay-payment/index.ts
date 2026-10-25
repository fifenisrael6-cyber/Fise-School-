import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const PREMIUM_PRICE_XAF = 2000;
const PREMIUM_CURRENCY = "XAF";
function adminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Supabase server secrets are not configured.");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });

const SCIENCE_SHARE = 200;
const LITERARY_SHARE = 200;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return json({ error: "Authentication required." }, 401);
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const publicKey = Deno.env.get("NOTCHPAY_PUBLIC_KEY");
    if (!supabaseUrl) throw new Error("Supabase URL is not configured.");
    if (!publicKey) {
      console.error("[notchpay-payment] NOTCHPAY_PUBLIC_KEY is missing.");
      return json({ error: "Le service de paiement n'est pas encore configuré. Réessaie plus tard." }, 503);
    }

    const admin = adminClient();
    const { data: authData, error: authError } = await admin.auth.getUser(authHeader.substring(7));
    if (authError || !authData.user) return json({ error: "Invalid session." }, 401);

    const { data: settings, error: settingsError } = await admin
      .from("payment_settings").select("enabled").eq("id", true).maybeSingle();
    if (settingsError) throw settingsError;
    if (settings?.enabled !== true) {
      return json({ error: "Les paiements sont temporairement désactivés. Réessaie plus tard." }, 503);
    }

    const body = await req.json().catch(() => ({}));
    const amount = Number(body?.amount ?? PREMIUM_PRICE_XAF);
    const currency = String(body?.currency ?? PREMIUM_CURRENCY).toUpperCase();
    if (amount !== PREMIUM_PRICE_XAF || currency !== PREMIUM_CURRENCY) {
      return json({ error: `Fise School Premium coûte ${PREMIUM_PRICE_XAF} ${PREMIUM_CURRENCY}.` }, 400);
    }
    const channel = String(body?.channel ?? "");
    if (!["cm.mtn", "cm.orange"].includes(channel)) {
      return json({ error: "Choisis MTN Mobile Money ou Orange Money." }, 400);
    }
    const rawPhone = String(body?.phone ?? "").trim().replace(/[\s().-]/g, "");
    const digits = rawPhone.replace(/^\+?237/, "");
    if (!/^6[0-9]{8}$/.test(digits)) {
      return json({ error: "Entre un numéro camerounais valide à 9 chiffres, commençant par 6." }, 400);
    }
    const phone = `237${digits}`;

    const { data: profile, error: profileError } = await admin
      .from("profiles").select("first_name,last_name,email,role").eq("id", authData.user.id).single();
    if (profileError) throw profileError;
    if (profile.role !== "student") return json({ error: "Premium est réservé aux élèves." }, 403);

    const { data: teachers } = await admin.rpc("resolve_premium_teachers", { p_student_id: authData.user.id });
    const scienceTeacher: string | null = teachers?.science_teacher_id ?? null;
    const literaryTeacher: string | null = teachers?.literary_teacher_id ?? null;
    const scienceCommission = scienceTeacher ? SCIENCE_SHARE : 0;
    const literaryCommission = literaryTeacher && literaryTeacher !== scienceTeacher ? LITERARY_SHARE : 0;
    // Resolve the same active standard-group memberships used by final payment settlement. The student's FISE code is used when joining the group, never entered at checkout.

    const reference = `FISE-${Date.now()}-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const callback = `${supabaseUrl}/functions/v1/notchpay-callback`;
    const email = String(profile.email ?? authData.user.email ?? "").trim();
    const name = `${profile.first_name ?? ""} ${profile.last_name ?? ""}`.trim();
    const description = "Abonnement Fise School Premium — 30 jours";
    const { error: insertError } = await admin.from("payment_orders").insert({
      user_id: authData.user.id, reference, amount, currency, status: "NOTPAY", description, provider: "notchpay",
      teacher_id: null, science_teacher_id: scienceTeacher, literary_teacher_id: literaryTeacher,
      science_commission_xaf: scienceCommission, literary_commission_xaf: literaryCommission,
      teacher_commission_xaf: scienceCommission + literaryCommission,
      platform_revenue_xaf: amount - scienceCommission - literaryCommission,
    });
    if (insertError) throw insertError;

    const initResponse = await fetch("https://api.notchpay.co/payments", {
      method: "POST",
      headers: { Authorization: publicKey, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({
        amount, currency, customer: { name: name || "Fise School Student", ...(email ? { email } : {}), phone },
        description, reference, callback,
      }),
    });
    const initData = await initResponse.json().catch(() => ({}));
    if (!initResponse.ok) {
      await admin.rpc("mark_notchpay_payment_failed", { p_reference: reference, p_status: "FAILED", p_reason: "init_failed" });
      return json({ error: initData?.message ?? "Impossible de créer la transaction chez Notch Pay." }, 502);
    }

    const providerReference = String(initData?.transaction?.reference ?? initData?.transaction?.merchant_reference ?? reference);
    const chargeResponse = await fetch(`https://api.notchpay.co/payments/${encodeURIComponent(providerReference)}`, {
      method: "POST",
      headers: { Authorization: publicKey, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({ channel, phone }),
    });
    const chargeData = await chargeResponse.json().catch(() => ({}));
    if (!chargeResponse.ok) {
      await admin.rpc("mark_notchpay_payment_failed", { p_reference: reference, p_status: "FAILED", p_reason: "charge_init_failed" });
      return json({ error: chargeData?.message ?? "L'opérateur n'a pas accepté la demande de paiement." }, 502);
    }
    const { error: updateError } = await admin.from("payment_orders").update({
      status: "PENDING", provider_transaction_id: providerReference, updated_at: new Date().toISOString(),
    }).eq("reference", reference);
    if (updateError) throw updateError;
    return json({
      reference, status: String(chargeData?.status ?? "Accepted").toUpperCase(),
      message: chargeData?.message ?? "Demande envoyée. Confirme le paiement sur ton téléphone.",
      channel, phone,
    });
  } catch (error) {
    console.error("[notchpay-payment]", error instanceof Error ? error.message : error);
    return json({ error: "Impossible de démarrer le paiement. Réessaie dans un instant." }, 500);
  }
});
