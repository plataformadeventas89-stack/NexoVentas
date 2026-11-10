import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://nexoventas-c1mk.onrender.com",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "Método no permitido" }, 405);

  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return json({ error: "Sesión requerida" }, 401);

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!serviceKey) return json({ error: "Falta configurar la clave administrativa del proyecto" }, 500);

  const admin = createClient(supabaseUrl, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const token = authHeader.slice("Bearer ".length);
  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData.user) return json({ error: "Sesión inválida o vencida" }, 401);

  const { data: caller, error: callerError } = await admin
    .from("usuarios")
    .select("comercio_id,rol")
    .eq("id", authData.user.id)
    .maybeSingle();

  if (callerError || !caller || caller.rol !== "admin") {
    return json({ error: "Solo un administrador puede invitar usuarios" }, 403);
  }

  let body: { email?: string; nombre?: string; rol?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "El cuerpo de la solicitud no es válido" }, 400);
  }

  const email = String(body.email || "").trim().toLowerCase();
  const nombre = String(body.nombre || "").trim();
  const rol = body.rol === "admin" ? "admin" : "vendedor";
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return json({ error: "Ingresá un correo electrónico válido" }, 400);
  if (nombre.length < 2 || nombre.length > 100) return json({ error: "El nombre debe tener entre 2 y 100 caracteres" }, 400);

  const { data: invited, error: inviteError } = await admin.auth.admin.inviteUserByEmail(email, {
    redirectTo: "https://nexoventas-c1mk.onrender.com/",
    data: { nombre_usuario: nombre },
  });
  if (inviteError || !invited.user) {
    return json({ error: inviteError?.message || "No se pudo enviar la invitación" }, 400);
  }

  const { error: profileError } = await admin.from("usuarios").insert({
    id: invited.user.id,
    comercio_id: caller.comercio_id,
    nombre,
    rol,
  });

  if (profileError) {
    await admin.auth.admin.deleteUser(invited.user.id);
    return json({ error: "No se pudo vincular el usuario al comercio: " + profileError.message }, 500);
  }

  return json({ ok: true, nombre, email, rol });
});