// Appelée par l'application (JWT requis) au retour du paiement ou à l'ouverture de la page Premium.
// Gère le « retour tardif » : revérifie auprès de Notch Pay une commande de CET élève.
import { adminClient, applyVerifiedPayment, fetchPayment } from "../_shared/notchpay.ts";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const auth = req.headers.get("Authorization");
    if (!auth?.startsWith("Bearer ")) return json({ error: "Authentication required." }, 401);
    const admin = adminClient();
    const { data: u, error } = await admin.auth.getUser(auth.substring(7));
    if (error || !u.user) return json({ error: "Invalid session." }, 401);

    const body = await req.json().catch(() => ({}));
    let reference = String(body?.reference ?? "").trim();

    // Sans référence : dernière commande ouverte de l'utilisateur
    let q = admin.from("payment_orders").select("reference,status,processed_at").eq("user_id", u.user.id);
    q = reference ? q.eq("reference", reference) : q.in("status", ["NOTPAY", "PENDING"]).order("created_at", { ascending: false });
    const { data: order } = await q.limit(1).maybeSingle();
    if (!order) return json({ status: "NONE" });
    reference = order.reference;
    if (order.processed_at) return json({ status: "SUCCESS", reference });

    const payment = await fetchPayment(reference);
    const { outcome } = await applyVerifiedPayment(admin, payment, "client_sync", null);
    const { data: fresh } = await admin.from("payment_orders").select("status").eq("reference", reference).single();
    return json({ status: fresh?.status ?? "PENDING", outcome, reference });
  } catch (_) {
    return json({ error: "Verification unavailable." }, 502);
  }
});
