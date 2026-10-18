import { adminClient, PREMIUM_CURRENCY, PREMIUM_PRICE_XAF } from "../_shared/notchpay.ts";

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
  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return json({ error: "Authentication required." }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const publicKey = Deno.env.get("NOTCHPAY_PUBLIC_KEY");
    if (!supabaseUrl || !publicKey) throw new Error("Notch Pay secrets are not configured.");

    const admin = adminClient();
    const { data: authData, error: authError } = await admin.auth.getUser(authHeader.substring(7));
    if (authError || !authData.user) return json({ error: "Invalid session." }, 401);

    const body = await req.json().catch(() => ({}));
    // Le prix est fixé par le serveur : toute autre valeur envoyée par le client est refusée.
    const amount = Number(body?.amount ?? PREMIUM_PRICE_XAF);
    const currency = String(body?.currency ?? PREMIUM_CURRENCY).toUpperCase();
    if (amount !== PREMIUM_PRICE_XAF || currency !== PREMIUM_CURRENCY) {
      return json({ error: `Fise School Premium costs ${PREMIUM_PRICE_XAF} ${PREMIUM_CURRENCY}.` }, 400);
    }

    const { data: profile, error: profileError } = await admin
      .from("profiles").select("first_name,last_name,email,role").eq("id", authData.user.id).single();
    if (profileError) throw profileError;
    if (profile.role !== "student") return json({ error: "Premium is reserved for students." }, 403);

    // Enseignants concernés selon l'affectation de classe de l'élève
    const { data: teachers } = await admin.rpc("resolve_premium_teachers", { p_student_id: authData.user.id });
    const scienceTeacher: string | null = teachers?.science_teacher_id ?? null;
    const literaryTeacher: string | null = teachers?.literary_teacher_id ?? null;
    const scienceCommission = scienceTeacher ? SCIENCE_SHARE : 0;
    const literaryCommission = literaryTeacher ? LITERARY_SHARE : 0;

    // Code enseignant historique (traçabilité uniquement ; il ne crée plus de commission à lui seul)
    const teacherCode = String(body?.teacher_code ?? "").trim();
    let legacyTeacherId: string | null = null;
    if (teacherCode) {
      const { data: resolved, error: resolveError } = await admin.rpc("resolve_teacher_payment_code", { p_code: teacherCode });
      if (resolveError || !resolved) return json({ error: "Invalid teacher code." }, 400);
      legacyTeacherId = String(resolved);
    }

    const reference = `FISE-${Date.now()}-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const callback = `${supabaseUrl}/functions/v1/notchpay-callback`;
    const email = String(profile.email ?? authData.user.email ?? "").trim();
    const name = `${profile.first_name ?? ""} ${profile.last_name ?? ""}`.trim();
    const description = "Abonnement Fise School Premium — 30 jours";

    // 1) On enregistre la commande AVANT d'appeler Notch Pay (pas de paiement orphelin).
    const { error: insertError } = await admin.from("payment_orders").insert({
      user_id: authData.user.id, reference, amount, currency, status: "NOTPAY", description, provider: "notchpay",
      teacher_id: legacyTeacherId,
      science_teacher_id: scienceTeacher, literary_teacher_id: literaryTeacher,
      science_commission_xaf: scienceCommission, literary_commission_xaf: literaryCommission,
      teacher_commission_xaf: scienceCommission + literaryCommission,
      platform_revenue_xaf: amount - scienceCommission - literaryCommission,
    });
    if (insertError) throw insertError;

    const paymentResponse = await fetch("https://api.notchpay.co/payments", {
      method: "POST",
      headers: { Authorization: publicKey, "Content-Type": "application/json", Accept: "application/json" },
      body: JSON.stringify({
        amount, currency,
        customer: { name: name || "Fise School Student", ...(email ? { email } : {}) },
        description, reference, callback,
      }),
    });
    const paymentData = await paymentResponse.json().catch(() => ({}));
    if (!paymentResponse.ok) {
      await admin.rpc("mark_notchpay_payment_failed", { p_reference: reference, p_status: "FAILED", p_reason: "init_failed" });
      throw new Error(paymentData?.message ?? "Notch Pay payment initialization failed.");
    }

    const authorizationUrl = paymentData?.authorization_url ?? paymentData?.transaction?.authorization_url;
    const returnedReference = String(paymentData?.transaction?.merchant_reference ?? reference);
    if (!authorizationUrl) throw new Error("Notch Pay returned no authorization URL.");

    await admin.from("payment_orders").update({
      status: "PENDING",
      provider_transaction_id: paymentData?.transaction?.id ?? null,
      updated_at: new Date().toISOString(),
    }).eq("reference", reference);

    return json({ authorization_url: authorizationUrl, reference: returnedReference });
  } catch (error) {
    console.error("[notchpay-payment]", error instanceof Error ? error.message : error);
    return json({ error: "Impossible de démarrer le paiement. Réessaie dans un instant." }, 500);
  }
});
