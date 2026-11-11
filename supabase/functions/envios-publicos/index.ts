const SITE_ORIGIN = "https://nexoventas-c1mk.onrender.com";
const corsHeaders = {
  "Access-Control-Allow-Origin": SITE_ORIGIN,
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Vary": "Origin",
};
const reply = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
});
const normalize = (value: unknown) => String(value ?? "").normalize("NFD")
  .replace(/[\u0300-\u036f]/g, "").trim().replace(/\s+/g, " ").toLocaleLowerCase("es");
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.headers.get("origin") && req.headers.get("origin") !== SITE_ORIGIN)
    return reply({ error: "Origen no permitido" }, 403);
  if (req.method !== "POST") return reply({ error: "Método no permitido" }, 405);
  try {
    const body = await req.json();
    const slug = String(body?.slug ?? "").trim().toLowerCase();
    const localidad = String(body?.localidad ?? "").trim().slice(0, 100);
    const provincia = String(body?.provincia ?? "").trim().slice(0, 100);
    const codigoPostal = String(body?.codigo_postal ?? "").trim().slice(0, 20);
    const subtotal = Number(body?.subtotal);
    if (!/^[a-z0-9]+(?:-[a-z0-9]+)*$/.test(slug) || slug.length > 80)
      return reply({ error: "La tienda indicada no es válida." }, 400);
    if (localidad.length < 2 || provincia.length < 2)
      return reply({ error: "Ingresá una localidad y una provincia válidas." }, 400);
    if (!Number.isFinite(subtotal) || subtotal < 0 || subtotal > 1000000000)
      return reply({ error: "El importe del carrito no es válido." }, 400);
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SUPABASE_SECRET_KEY");
    if (!supabaseUrl || !serviceKey) {
      console.error("envios-publicos: faltan variables de servidor");
      return reply({ error: "La consulta de envíos no está disponible temporalmente." }, 503);
    }
    const headers = { apikey: serviceKey, Authorization: "Bearer " + serviceKey };
    const rest = async (path: string) => {
      const response = await fetch(supabaseUrl + "/rest/v1/" + path, { headers });
      if (!response.ok) {
        const detail = (await response.text()).slice(0, 300);
        console.error("envios-publicos REST", response.status, detail);
        throw new Error("No se pudo consultar la configuración de envíos.");
      }
      return await response.json();
    };
    const businesses = await rest("comercios?select=id&tienda_slug=eq." + encodeURIComponent(slug) + "&tienda_activa=eq.true&activo=eq.true&limit=1");
    const business = businesses?.[0];
    if (!business) return reply({ error: "Esta tienda no está disponible." }, 404);
    const commerceId = String(business.id);
    const [methods, zones] = await Promise.all([
      rest("envios_metodos?select=id,nombre,tipo,descripcion,requiere_seguimiento&comercio_id=eq." + commerceId + "&activo=eq.true&order=nombre.asc"),
      rest("envios_zonas?select=id,metodo_id,localidad,provincia,codigo_postal,precio,dias_min,dias_max,gratis_desde&comercio_id=eq." + commerceId + "&activo=eq.true"),
    ]);
    const targetLocality = normalize(localidad);
    const targetProvince = normalize(provincia);
    const targetPostal = codigoPostal.replace(/\s+/g, "").toUpperCase();
    const methodMap = new Map<string, Record<string, unknown>>();
    for (const method of methods || []) methodMap.set(String(method.id), method);
    const matches = (zones || []).filter((zone: Record<string, unknown>) =>
      normalize(zone.localidad) === targetLocality &&
      normalize(zone.provincia) === targetProvince &&
      (!String(zone.codigo_postal ?? "").trim() ||
        String(zone.codigo_postal).replace(/\s+/g, "").toUpperCase() === targetPostal)
    );
    const bestByMethod = new Map<string, Record<string, unknown>>();
    for (const zone of matches) {
      const methodId = String(zone.metodo_id);
      if (!methodMap.has(methodId)) continue;
      const current = bestByMethod.get(methodId);
      const specific = String(zone.codigo_postal ?? "").trim() !== "";
      const currentSpecific = current && String(current.codigo_postal ?? "").trim() !== "";
      if (!current || (specific && !currentSpecific)) bestByMethod.set(methodId, zone);
    }
    const options = Array.from(bestByMethod.entries()).map(([methodId, zone]) => {
      const method = methodMap.get(methodId)!;
      const threshold = zone.gratis_desde == null ? null : Number(zone.gratis_desde);
      const free = threshold !== null && subtotal >= threshold;
      return {
        metodo_id: methodId,
        zona_id: String(zone.id),
        nombre: method.nombre,
        tipo: method.tipo,
        descripcion: method.descripcion,
        requiere_seguimiento: Boolean(method.requiere_seguimiento),
        costo: free ? 0 : Number(zone.precio),
        dias_min: Number(zone.dias_min),
        dias_max: Number(zone.dias_max),
        envio_gratis_aplicado: free,
        gratis_desde: threshold,
      };
    }).sort((a, b) => a.costo - b.costo || a.dias_min - b.dias_min || String(a.nombre).localeCompare(String(b.nombre), "es"));
    return reply({ localidad, provincia, codigo_postal: codigoPostal, subtotal, opciones: options });
  } catch (error) {
    console.error("envios-publicos error", error);
    return reply({ error: error instanceof Error ? error.message : "No se pudo consultar los envíos." }, 500);
  }
});