// Recibe los datos que la app del paciente descargó del equipo.
// El paciente no tiene cuenta: se autentica con el token_sync del QR.
// La web del médico usa esta misma función cuando descarga la ortesis en la consulta.
import { createClient } from "npm:@supabase/supabase-js@2";

type Resumen = {
  fecha: string; dosis_sobrecarga: number; dosis_subcarga: number;
  t_carga_s: number; t_exceso_s: number; t_sub_s: number; pico: number; excedencias: number;
};
type Registro = {
  ts: string; carga_media: number; carga_pico: number; dosis: number;
  excedencias: number; seg_apoyo: number;
};
// Lo que la ortesis dice de sí misma. Nada de esto identifica a una persona.
type Equipo = {
  serie?: string; firmware?: string; episodio?: string;
  limite_sup?: number; limite_inf?: number; peso_kg?: number;
  hay_pendiente?: boolean; pendiente_sup?: number; pendiente_inf?: number; pendiente_peso_kg?: number;
};

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return new Response("Método no permitido", { status: 405, headers: cors });

  let body: {
    token?: string; resumenes?: Resumen[]; registros?: Registro[];
    equipo?: Equipo; origen?: "app" | "consultorio";
  };
  try { body = await req.json(); } catch { return new Response("JSON inválido", { status: 400, headers: cors }); }
  if (!body.token) return new Response("Falta el token del episodio", { status: 400, headers: cors });

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const { data: ep, error } = await db.from("episodios")
    .select("id, vinculada_en").eq("token_sync", body.token).is("fin", null).maybeSingle();
  if (error) return new Response(error.message, { status: 500, headers: cors });
  if (!ep) return new Response("Episodio inexistente o cerrado", { status: 404, headers: cors });

  const resumenes = (body.resumenes ?? []).map((r) => ({ ...r, episodio_id: ep.id }));
  const registros = (body.registros ?? []).map((r) => ({ ...r, episodio_id: ep.id }));

  if (resumenes.length) {
    const { error: e } = await db.from("resumenes_diarios").upsert(resumenes);
    if (e) return new Response(e.message, { status: 400, headers: cors });
  }
  for (let i = 0; i < registros.length; i += 1000) {
    const { error: e } = await db.from("registros_minuto").upsert(registros.slice(i, i + 1000));
    if (e) return new Response(e.message, { status: 400, headers: cors });
  }

  const ahora = new Date().toISOString();
  const cambios: Record<string, unknown> = {};

  // Qué límites tiene cargados la ortesis. Le deja ver al médico si la indicación que
  // mandó llegó y fue confirmada con el pulsador del equipo.
  if (body.equipo) {
    cambios.equipo_visto = body.equipo;
    cambios.equipo_visto_en = ahora;
  }

  // La app se hace ver cada vez que habla, incluso cuando no trae datos: apenas se
  // escanea el QR manda un acuse para validar el token, y ese acuse es la vinculación.
  // La descarga en la consulta la hace el médico, así que no cuenta como sincronización.
  if (body.origen !== "consultorio") {
    cambios.ultima_sincronizacion = ahora;
    if (!ep.vinculada_en) cambios.vinculada_en = ahora;
  }

  if (Object.keys(cambios).length) {
    const { error: e } = await db.from("episodios").update(cambios).eq("id", ep.id);
    if (e) return new Response(e.message, { status: 400, headers: cors });
  }

  return Response.json(
    { ok: true, resumenes: resumenes.length, registros: registros.length, equipo: !!body.equipo },
    { headers: cors },
  );
});
