// Webhook Notch Pay. Déployé avec --no-verify-jwt : l'authenticité repose sur la
// signature HMAC (x-notch-signature) PUIS sur une revérification auprès de Notch Pay.
import { adminClient, applyVerifiedPayment, fetchPayment, verifyWebhookSignature } from "../_shared/notchpay.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  const raw = await req.text();
  const valid = await verifyWebhookSignature(raw, req.headers.get("x-notch-signature"));
  if (!valid) return new Response("Invalid signature", { status: 401 });

  try {
    const event = JSON.parse(raw);
    const data = event?.data ?? event?.transaction ?? {};
    const reference = String(data?.merchant_reference ?? data?.reference ?? "").trim();
    if (!reference) return new Response("ok", { status: 200 });

    // On ne fait jamais confiance au corps du webhook pour le montant/statut.
    const payment = await fetchPayment(reference);
    await applyVerifiedPayment(adminClient(), payment, "webhook", true);
    return new Response("ok", { status: 200 });
  } catch (_) {
    // 500 => Notch Pay réessaiera ; la finalisation est idempotente.
    return new Response("temporary error", { status: 500 });
  }
});
