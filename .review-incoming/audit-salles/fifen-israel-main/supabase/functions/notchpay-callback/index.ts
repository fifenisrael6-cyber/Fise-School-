// Page de retour après paiement (redirection navigateur, sans JWT).
// Ne confie jamais l'activation au paramètre d'URL : le statut vient de Notch Pay.
import { adminClient, applyVerifiedPayment, fetchPayment } from "../_shared/notchpay.ts";

const page = (message: string, status = 200) =>
  new Response(
    `<!doctype html><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Fise School</title><body style="font-family:sans-serif;text-align:center;padding:48px 24px"><h2>${message}</h2><p>Vous pouvez revenir dans l'application Fise School.</p></body>`,
    { status, headers: { "Content-Type": "text/html; charset=utf-8" } },
  );

Deno.serve(async (req) => {
  try {
    const url = new URL(req.url);
    const reference = (url.searchParams.get("reference") ?? url.searchParams.get("trxref") ?? "").trim();
    if (!reference || reference.length > 80) return page("Référence de paiement manquante.", 400);

    const payment = await fetchPayment(reference);
    const { outcome } = await applyVerifiedPayment(adminClient(), payment, "callback", null);

    if (outcome === "processed" || outcome === "duplicate") return page("Paiement confirmé ✅");
    if (outcome === "failed") return page("Paiement non abouti (refusé, annulé ou expiré).");
    if (outcome === "rejected") return page("Paiement reçu mais en cours de contrôle. Réessayez dans un instant.", 202);
    return page("Paiement en attente de confirmation…", 202);
  } catch (_) {
    return page("Impossible de vérifier le paiement pour le moment.", 502);
  }
});
