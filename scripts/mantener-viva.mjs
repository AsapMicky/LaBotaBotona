// Mantiene despierto el proyecto de Supabase del plan gratuito.
//
// Supabase pausa los proyectos gratuitos que pasan una semana con poca actividad.
// La documentación es explícita: no alcanza con entrar una vez, hacen falta "unas pocas
// consultas por día" a lo largo de toda la semana previa. Este script hace esas consultas.
//
//   node scripts/mantener-viva.mjs
//
// Saca la URL y la anon key de web-medico/.env.local, que no se versiona. También las
// toma de las variables de entorno SUPABASE_URL y SUPABASE_ANON_KEY si están puestas.
//
// La anon key es pública por diseño (ya viaja en el bundle de la web) y lo que protege
// los datos son las policies RLS. Como todas las policies son por médico, estas consultas
// devuelven vacío: no se lee ni un dato de nadie. Lo único que importa es que la consulta
// llegue hasta Postgres, que es lo que Supabase cuenta como actividad.
//
// Sale con código 0 si la base está viva y 1 si no, para poder encadenarlo.
import { readFileSync, writeFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const aca = dirname(fileURLToPath(import.meta.url))
const archivoEnv = join(aca, '..', 'web-medico', '.env.local')
const archivoUltimo = join(aca, '.ultimo-ping.json')

function leerEnv(ruta) {
  try {
    return Object.fromEntries(
      readFileSync(ruta, 'utf8')
        .split('\n')
        .map((l) => l.trim())
        .filter((l) => l && !l.startsWith('#') && l.includes('='))
        .map((l) => {
          const i = l.indexOf('=')
          return [l.slice(0, i).trim(), l.slice(i + 1).trim()]
        }),
    )
  } catch {
    return {}
  }
}

const env = leerEnv(archivoEnv)
const url = (process.env.SUPABASE_URL ?? env.VITE_SUPABASE_URL ?? '').replace(/\/+$/, '')
const clave = process.env.SUPABASE_ANON_KEY ?? env.VITE_SUPABASE_ANON_KEY ?? ''

if (!url || !clave) {
  console.error('Faltan las credenciales.')
  console.error(`Esperaba VITE_SUPABASE_URL y VITE_SUPABASE_ANON_KEY en ${archivoEnv},`)
  console.error('o SUPABASE_URL y SUPABASE_ANON_KEY en el entorno.')
  process.exit(1)
}

// Varias tablas distintas, que es lo que la documentación llama "unas pocas consultas".
//
// A propósito no están `resumenes_diarios`, `indicaciones` ni `registros_minuto`: sus
// policies llaman a `es_mi_episodio()`, que la migración 0003 le revocó a `anon`, así que
// sin sesión contestan 401 en vez de una lista vacía. Es el modelo de seguridad andando
// bien, pero ensucia la lectura de este script. Estas tres contestan 200 con `[]`.
const tablas = ['dispositivos', 'episodios', 'pacientes']

async function consultar(tabla) {
  const arranque = Date.now()
  // Sin `select`: no todas las tablas tienen una columna `id` (`resumenes_diarios` se
  // identifica por episodio_id + fecha) y así esto no se rompe si cambia el esquema.
  const r = await fetch(`${url}/rest/v1/${tabla}?limit=1`, {
    headers: { apikey: clave, Authorization: `Bearer ${clave}` },
    signal: AbortSignal.timeout(20000),
  })
  return { tabla, codigo: r.status, ms: Date.now() - arranque, cuerpo: await r.text() }
}

function diasDesde(iso) {
  const d = (Date.now() - new Date(iso).getTime()) / 86400000
  return Number.isFinite(d) ? d : null
}

const anterior = (() => {
  try { return JSON.parse(readFileSync(archivoUltimo, 'utf8')) } catch { return null }
})()

console.log(`Proyecto: ${url}`)
if (anterior?.cuando) {
  const d = diasDesde(anterior.cuando)
  const cuanto = d < 1 ? 'hoy' : d < 2 ? 'ayer' : `hace ${Math.floor(d)} días`
  console.log(`Último ping: ${cuanto} (${new Date(anterior.cuando).toLocaleString('es-AR')})`)
  if (d >= 6) console.log('Ojo: estuviste cerca del límite de 7 días.')
} else {
  console.log('Último ping: no hay registro, debe ser la primera vez.')
}
console.log('')

let viva = true
for (const tabla of tablas) {
  try {
    const { codigo, ms, cuerpo } = await consultar(tabla)
    // Con RLS por médico y sin sesión, la respuesta correcta es 200 con una lista vacía.
    if (codigo === 200) {
      console.log(`  ${tabla.padEnd(18)} ${codigo}  ${String(ms).padStart(5)} ms`)
    } else {
      viva = false
      const pista = /pause/i.test(cuerpo) ? '  ← el proyecto está pausado' : ''
      console.log(`  ${tabla.padEnd(18)} ${codigo}  ${String(ms).padStart(5)} ms${pista}`)
    }
  } catch (e) {
    viva = false
    console.log(`  ${tabla.padEnd(18)} sin respuesta  (${e.name === 'TimeoutError' ? 'tardó más de 20 s' : e.message})`)
  }
}

console.log('')
if (viva) {
  console.log('La base está viva. El contador de inactividad vuelve a cero.')
  try {
    writeFileSync(archivoUltimo, JSON.stringify({ cuando: new Date().toISOString() }, null, 2) + '\n')
  } catch { /* si no se puede escribir el registro, no es motivo para fallar */ }
} else {
  console.log('La base no contestó como debería.')
  console.log('Si está pausada, se despierta a mano desde https://supabase.com/dashboard')
  console.log('con el botón "Resume project". Tenés 90 días desde que se pausó y no se pierde nada.')
}

process.exit(viva ? 0 : 1)
