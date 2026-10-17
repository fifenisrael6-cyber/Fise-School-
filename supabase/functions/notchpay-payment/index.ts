import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) return json({ error: "Authentication required." }, 401);

    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
    const publicKey = Deno.env.get("NOTCHPAY_PUBLIC_KEY");
    if (!supabaseUrl || !serviceKey || !publicKey) {
      throw new Error("Supabase/Notch Pay secrets are not configured.");
    }

    const token = authHeader.substring("Bearer ".length);
    const admin = createClient(supabaseUrl, serviceKey);
    const { data: authData, error: authError } = await admin.auth.getUser(token);
    if (authError || !authData.user) return json({ error: "Invalid session." }, 401);

    const body = await req.json();
    const amount = Number(body?.amount ?? 2000);
    const currency = String(body?.currency ?? "XAF").toUpperCase();
    if (amount !== 2000 || currency !== "XAF") {
      return json({ error: "Fise School Premium must be 2000 XAF." }, 400);
    }

    const { data: profile, error: profileError } = await admin
      .from("profiles")
      .select("first_name,last_name,email,role")
      .eq("id", authData.user.id)
      .single();
    if (profileError) throw profileError;
    if (profile.role !== "student") {
      return json({ error: "Only student accounts can purchase Premium." }, 403);
    }

    let relatedClassId: string | null = null;
    let scientificTeacherId: string | null = null;
    let literaryTeacherId: string | null = null;
    const { data: membership, error: membershipError } = await admin
      .from("class_students")
      .select("class_id")
      .eq("student_id", authData.user.id)
      .eq("is_active", true)
      .order("joined_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (membershipError) throw membershipError;
    relatedClassId = membership?.class_id?.toString() ?? null;

    if (relatedClassId) {
      const { data: assignments, error: assignmentError } = await admin
        .from("class_teachers")
        .select("teacher_id")
        .eq("class_id", relatedClassId)
        .eq("is_active", true);
      if (assignmentError) throw assignmentError;
      const teacherIds = [...new Set((assignments ?? [])
        .map((row: { teacher_id?: string }) => row.teacher_id)
        .filter((id): id is string => typeof id === "string" && id.length > 0))];
      if (teacherIds.length > 0) {
        const { data: teachers, error: teachersError } = await admin
          .from("profiles")
          .select("id,teacher_vocation")
          .eq("role", "teacher")
          .in("id", teacherIds);
        if (teachersError) throw teachersError;
        scientificTeacherId = (teachers ?? [])
          .find((teacher: { teacher_vocation?: string }) => teacher.teacher_vocation === "scientific")?.id ?? null;
        literaryTeacherId = (teachers ?? [])
          .find((teacher: { teacher_vocation?: string }) => teacher.teacher_vocation === "literary")?.id ?? null;
      }
    }

    // Never block Premium checkout because a classroom has not yet assigned
    // both teaching vocations. Credit only teachers actually assigned to the room;
    // the unallocated commission remains with the platform.
    const scientificCommission = scientificTeacherId ? 200 : 0;
    const literaryCommission = literaryTeacherId ? 200 : 0;
    const platformRevenue = amount - scientificCommission - literaryCommission;

    const reference = `FISE-${Date.now()}-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
    const callback = `${supabaseUrl}/functions/v1/notchpay-callback`;
    const email = String(body?.email ?? profile.email ?? authData.user.email ?? "").trim();
    const name = String(body?.name ?? `${profile.first_name ?? ""} ${profile.last_name ?? ""}`).trim();

    const paymentResponse = await fetch("https://api.notchpay.co/payments", {
      method: "POST",
      headers: {
        "Authorization": publicKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount,
        currency,
        customer: {
          name: name || "Fise School Student",
          ...(email ? { email } : {}),
        },
        description: String(body?.description ?? "Abonnement Fise School Premium - 30 jours"),
        reference,
        callback,
        locked_currency: "XAF",
        locked_country: "CM",
      }),
    });

    const paymentData = await paymentResponse.json();
    if (!paymentResponse.ok) {
      throw new Error(paymentData?.message ?? paymentData?.error?.message ?? "Notch Pay payment initialization failed.");
    }

    const authorizationUrl = paymentData?.authorization_url ?? paymentData?.transaction?.authorization_url;
    const returnedReference = String(paymentData?.reference ?? paymentData?.transaction?.reference ?? reference);
    const providerTransactionId = paymentData?.transaction?.id ?? null;
    if (!authorizationUrl) throw new Error("Notch Pay returned no authorization URL.");

    const { error: insertError } = await admin.from("payment_orders").insert({
      user_id: authData.user.id,
      reference: returnedReference,
      amount,
      currency,
      status: "PENDING",
      description: String(body?.description ?? "Abonnement Fise School"),
      provider: "notchpay",
      provider_transaction_id: providerTransactionId,
      teacher_id: null,
      teacher_commission_xaf: scientificCommission + literaryCommission,
      platform_revenue_xaf: platformRevenue,
      scientific_teacher_id: scientificTeacherId,
      literary_teacher_id: literaryTeacherId,
      scientific_commission_xaf: scientificCommission,
      literary_commission_xaf: literaryCommission,
      related_class_id: relatedClassId,
    });
    if (insertError) throw insertError;

    return json({
      authorization_url: authorizationUrl,
      reference: returnedReference,
      teacher_id: null,
    });
  } catch (error) {
    return json({ error: error instanceof Error ? error.message : "Unknown error" }, 500);
  }
});
