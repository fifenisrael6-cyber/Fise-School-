// Utilitaires communs Notch Pay (serveur uniquement). Aucune clé n'est lue côté Flutter.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export const PREMIUM_PRICE_XAF = 2000;
export const PREMIUM_CURRENCY = "XAF";

export function adminClient() {
  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!url || !key) throw new Error("Supabase secrets are not configured.");
  return createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });
}

export type VerifiedPayment = {
  reference: string;
  status: string; // minuscule : complete | pending | processing | failed | canceled | expired ...
  amount: number | null;
  currency: string | null;
  providerId: string | null;
};

// Vérifie un paiement directement auprès de Notch Pay (source de vérité).
export async function fetchPayment(reference: string): Promise<VerifiedPayment> {
  const publicKey = Deno.env.get("NOTCHPAY_PUBLIC_KEY");
  if (!publicKey) throw new Error("NOTCHPAY_PUBLIC_KEY is not configured.");
  const res = await fetch(`https://api.notchpay.co/payments/${encodeURIComponent(reference)}`, {
    headers: { Authorization: publicKey, Accept: "application/json" },
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`Notch Pay verification failed (${res.status}).`);
  const tx = data?.transaction ?? data;
  const amount = tx?.amount != null ? Number(tx.amount) : null;
  return {
    reference: String(tx?.merchant_reference ?? tx?.reference ?? reference),
    status: String(tx?.status ?? data?.status ?? "").toLowerCase(),
    amount: Number.isFinite(amount) ? amount : null,
    currency: tx?.currency ? String(tx.currency).toUpperCase() : null,
    providerId: tx?.id ? String(tx.id) : null,
  };
}

async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

// HMAC-SHA256 du corps brut avec la « hash key » du webhook (en-tête x-notch-signature).
export async function verifyWebhookSignature(rawBody: string, signature: string | null): Promise<boolean> {
  const secret = Deno.env.get("NOTCHPAY_WEBHOOK_HASH");
  if (!secret || !signature) return false;
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"],
  );
  const mac = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(rawBody)));
  const expected = Array.from(mac).map((b) => b.toString(16).padStart(2, "0")).join("");
  const given = signature.trim().toLowerCase();
  if (given.length !== expected.length) return false;
  let diff = 0; // comparaison à temps constant
  for (let i = 0; i < expected.length; i++) diff |= expected.charCodeAt(i) ^ given.charCodeAt(i);
  return diff === 0;
}

// Applique un état de paiement vérifié. Idempotent : peut être appelé N fois.
export async function applyVerifiedPayment(
  admin: ReturnType<typeof adminClient>,
  payment: VerifiedPayment,
  source: "webhook" | "callback" | "client_sync",
  signatureValid: boolean | null,
): Promise<{ outcome: string; status: string }> {
  const eventKey = await sha256Hex(
    `${source}|${payment.reference}|${payment.status}|${payment.providerId ?? ""}|${payment.amount ?? ""}`,
  );
  let outcome = "ignored";

  if (payment.status === "complete" || payment.status === "completed" || payment.status === "success") {
    const { data, error } = await admin.rpc("finalize_notchpay_payment", {
      p_reference: payment.reference,
      p_provider_transaction_id: payment.providerId,
      p_paid_amount: payment.amount,
      p_paid_currency: payment.currency,
    });
    if (error) {
      outcome = "rejected";
    } else {
      outcome = data?.already_processed ? "duplicate" : "processed";
    }
  } else if (["failed", "canceled", "cancelled", "expired", "rejected"].includes(payment.status)) {
    await admin.rpc("mark_notchpay_payment_failed", {
      p_reference: payment.reference, p_status: payment.status, p_reason: payment.status,
    });
    outcome = "failed";
  } else {
    outcome = "pending"; // pending / processing : on attend la confirmation finale
  }

  await admin.from("payment_events").upsert({
    event_key: eventKey, reference: payment.reference, event_type: payment.status, source,
    signature_valid: signatureValid, provider_status: payment.status,
    amount: payment.amount, currency: payment.currency, outcome,
  }, { onConflict: "event_key", ignoreDuplicates: true });

  return { outcome, status: payment.status };
}
