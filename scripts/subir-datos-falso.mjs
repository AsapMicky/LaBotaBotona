// Servidor falso de la función `subir-datos`, para probar la app sin Supabase.
// Imprime lo que llega y contesta como la función real.
//
//   node scripts/subir-datos-falso.mjs            # escucha en http://0.0.0.0:8787
//   CERRADO=1 node scripts/subir-datos-falso.mjs  # contesta "episodio cerrado" (404)
//
// Desde el emulador de Android la PC es 10.0.2.2:
//   flutter run --dart-define=SUPABASE_URL=http://10.0.2.2:8787
// Desde un celular en la misma red, la IP de la PC (ipconfig).
import http from 'node:http'

const puerto = Number(process.env.PUERTO ?? 8787)
const cerrado = process.env.CERRADO === '1'
const cabeceras = { 'access-control-allow-origin': '*', 'access-control-allow-headers': 'content-type,apikey,authorization' }

http.createServer((req, res) => {
  const responder = (codigo, cuerpo) => {
    res.writeHead(codigo, { ...cabeceras, 'content-type': typeof cuerpo === 'string' ? 'text/plain' : 'application/json' })
    res.end(typeof cuerpo === 'string' ? cuerpo : JSON.stringify(cuerpo))
  }
  if (req.method === 'OPTIONS') return responder(204, '')
  if (req.method !== 'POST' || !req.url.endsWith('/functions/v1/subir-datos')) return responder(404, '{"code":"NOT_FOUND"}')

  let datos = ''
  req.on('data', (t) => (datos += t))
  req.on('end', () => {
    let cuerpo
    try { cuerpo = JSON.parse(datos) } catch { return responder(400, 'JSON inválido') }
    if (!cuerpo.token) return responder(400, 'Falta el token del episodio')
    const resumenes = cuerpo.resumenes ?? []
    const registros = cuerpo.registros ?? []
    const hora = new Date().toLocaleTimeString('es-AR')
    console.log(`[${hora}] token ${cuerpo.token.slice(0, 8)}… · ${resumenes.length} resúmenes · ${registros.length} registros`)
    for (const r of resumenes) console.log(`   ${r.fecha}: ${r.excedencias} exc., ${r.t_carga_s} s de apoyo, dosis ${Number(r.dosis_sobrecarga).toFixed(1)}`)
    if (cerrado) return responder(404, 'Episodio inexistente o cerrado')
    responder(200, { ok: true, resumenes: resumenes.length, registros: registros.length })
  })
}).listen(puerto, '0.0.0.0', () => {
  console.log(`subir-datos falso escuchando en http://0.0.0.0:${puerto}${cerrado ? ' (modo episodio cerrado)' : ''}`)
})
