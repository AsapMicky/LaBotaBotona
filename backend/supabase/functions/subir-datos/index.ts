// Recibe los datos que la app del paciente descargó del equipo.
// El paciente no tiene cuenta: se autentica con el token_sync del QR.
import { createClient } from "npm:@supabase/supabase-js@2";

type Resumen = {
  fecha: string; dosis_sobrecarga: number; dosis_subcarga: number;
  t_carga_s: number; t_exceso_s: number; t_sub_s: number; pico: number; excedencias: number;
};
type Registro = {
  ts: string; carga_media: number; carga_pico: number; dosis: number;
  excedencias: number; seg_apoyo: number;
};

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return new Response("Método no permitido", { status: 405, headers: cors });

  let body: { token?: string; resumenes?: Resumen[]; registros?: Registro[] };
  try { body = await req.json(); } catch { return new Response("JSON inválido", { status: 400, headers: cors }); }
  if (!body.token) return new Response("Falta el token del episodio", { status: 400, headers: cors });

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const { data: ep, error } = await db.from("episodios")
    .select("id").eq("token_sync", body.token).is("fin", null).maybeSingle();
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
  return Response.json({ ok: true, resumenes: resumenes.length, registros: registros.length }, { headers: cors });
});
