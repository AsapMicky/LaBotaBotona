// Datos simulados con la misma forma que las tablas de Supabase (backend/supabase).
// Semilla fija: todos ven los mismos pacientes.
function azar(semilla) {
  let s = semilla
  return () => {
    s |= 0; s = (s + 0x6d2b79f5) | 0
    let t = Math.imul(s ^ (s >>> 15), 1 | s)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}
const r = azar(62140)
const hoy = new Date()
const iso = (diasAtras) => {
  const d = new Date(hoy)
  d.setDate(d.getDate() - diasAtras)
  return d.toISOString().slice(0, 10)
}
const uuid = () => crypto.randomUUID()

const dispositivos = ['0001', '0002', '0003', '0004', '0005'].map((serie) => ({ id: uuid(), serie }))

function serie(dias, fn) {
  return Array.from({ length: dias }, (_, i) => {
    const k = i / Math.max(1, dias - 1) // 0 → 1 a lo largo del tratamiento
    return { fecha: iso(dias - i), ...fn(k, i) }
  })
}

const pacientes = [
  { nombre: 'Laura', apellido: 'Benítez', documento: '30111222' },
  { nombre: 'Marcos', apellido: 'Ferreyra', documento: '27333444' },
  { nombre: 'Sofía', apellido: 'Ruiz', documento: '41555666' },
  { nombre: 'Julián', apellido: 'Ocampo', documento: '35777888' },
].map((p, i) => ({ id: uuid(), codigo: `P-${String(118 + i).padStart(6, '0')}`, ...p }))

const [laura, marcos, sofia, julian] = pacientes

const episodios = [
  {
    paciente: laura, miembro: 'izquierdo', lesion: 'Reparación de tendón de Aquiles', dias: 21, L: 30, Lmin: 15, peso: 64,
    disp: 0,
    fn: (k) => {
      const t = 9000 + r() * 3000
      const exc = t * (0.24 - 0.2 * k + r() * 0.03)
      const sub = t * (0.07 + r() * 0.04)
      return { t_carga_s: t, t_exceso_s: exc, t_sub_s: sub, dosis_sobrecarga: exc / 9 + r() * 20,
        dosis_subcarga: sub / 40, pico: 38 + r() * 10, excedencias: Math.round(40 - 34 * k + r() * 4) }
    },
  },
  {
    paciente: marcos, miembro: 'derecho', lesion: 'Fractura bimaleolar', dias: 14, L: 20, Lmin: 0, peso: 82, disp: 1,
    fn: (k) => {
      const t = 10000 + r() * 2500
      const exc = t * (0.05 + 0.2 * k + r() * 0.03)
      return { t_carga_s: t, t_exceso_s: exc, t_sub_s: 0, dosis_sobrecarga: exc / 8 + r() * 15,
        dosis_subcarga: 0, pico: 26 + 14 * k + r() * 4, excedencias: Math.round(8 + 26 * k + r() * 3) }
    },
  },
  {
    paciente: sofia, miembro: 'izquierdo', lesion: 'Fractura de diáfisis tibial', dias: 7, L: 20, Lmin: 10, peso: 58, disp: 2,
    fn: () => {
      const t = 7000 + r() * 1500
      const exc = t * r() * 0.02
      const sub = t * (0.55 + r() * 0.1)
      return { t_carga_s: t, t_exceso_s: exc, t_sub_s: sub, dosis_sobrecarga: exc / 10,
        dosis_subcarga: sub / 18, pico: 19 + r() * 4, excedencias: Math.round(r() * 3) }
    },
  },
  {
    paciente: julian, miembro: 'derecho', lesion: 'Fractura de platillo tibial', dias: 3, L: 10, Lmin: 0, peso: 91, disp: 3,
    fn: () => {
      const t = 5000 + r() * 1000
      const exc = t * (0.08 + r() * 0.04)
      return { t_carga_s: t, t_exceso_s: exc, t_sub_s: 0, dosis_sobrecarga: exc / 12,
        dosis_subcarga: 0, pico: 17 + r() * 3, excedencias: Math.round(12 + r() * 5) }
    },
  },
].map((e) => ({
  id: uuid(),
  paciente_id: e.paciente.id,
  dispositivo_serie: dispositivos[e.disp].serie,
  miembro: e.miembro,
  lesion: e.lesion,
  fecha_cirugia: iso(e.dias + 2),
  inicio: iso(e.dias),
  fin: null,
  limite_sup: e.L,
  limite_inf: e.Lmin,
  peso_kg: e.peso,
  token_sync: uuid(),
  indicaciones: [{ desde: iso(e.dias), limite_sup: e.L, limite_inf: e.Lmin, peso_kg: e.peso, nota: null }],
  resumenes: serie(e.dias, e.fn).map((x) => ({
    ...x, t_carga_s: Math.round(x.t_carga_s), t_exceso_s: Math.round(x.t_exceso_s), t_sub_s: Math.round(x.t_sub_s),
  })),
}))

// Re-lesión de Marcos, mismo miembro, hace más de un año (decisión 004)
episodios.push({
  id: uuid(), paciente_id: marcos.id, dispositivo_serie: null, miembro: 'derecho',
  lesion: 'Fractura de maléolo lateral', fecha_cirugia: iso(422), inicio: iso(420), fin: iso(360),
  limite_sup: 20, limite_inf: 0, peso_kg: 84, token_sync: uuid(),
  indicaciones: [{ desde: iso(420), limite_sup: 20, limite_inf: 0, peso_kg: 84, nota: null }],
  resumenes: serie(60, (k) => {
    const t = 9500
    const exc = t * (0.2 - 0.15 * k)
    return { t_carga_s: t, t_exceso_s: Math.round(exc), t_sub_s: 0, dosis_sobrecarga: exc / 8,
      dosis_subcarga: 0, pico: 34 - 8 * k, excedencias: Math.round(30 - 22 * k) }
  }).map((x, i) => ({ ...x, fecha: iso(420 - i) })),
})

const espera = (ms = 150) => new Promise((res) => setTimeout(res, ms))
let usuario = null

export const fuenteMock = {
  simulada: true,
  async sesion() { return usuario },
  async ingresar(email) {
    await espera()
    usuario = { email, nombre: 'Dra. Prueba' }
    return usuario
  },
  async salir() { usuario = null },

  async listarPacientes() {
    await espera()
    return pacientes.map((p) => {
      const eps = episodios.filter((e) => e.paciente_id === p.id)
      return { ...p, episodioActual: eps.find((e) => !e.fin) ?? null, cantidadEpisodios: eps.length }
    })
  },
  async episodiosDe(pacienteId) {
    await espera()
    return episodios
      .filter((e) => e.paciente_id === pacienteId)
      .sort((a, b) => b.inicio.localeCompare(a.inicio))
      .map(({ resumenes, ...e }) => e)
  },
  async resumenesDe(episodioId) {
    await espera()
    return episodios.find((e) => e.id === episodioId)?.resumenes ?? []
  },
  async indicacionesDe(episodioId) {
    await espera()
    return (episodios.find((e) => e.id === episodioId)?.indicaciones ?? []).map((x) => ({ ...x }))
  },
  async cambiarIndicacion(episodioId, { limite_sup, limite_inf, peso_kg, nota }) {
    await espera()
    const e = episodios.find((x) => x.id === episodioId)
    if (!e) throw new Error('Tratamiento inexistente')
    if (e.fin) throw new Error('El tratamiento está cerrado')
    if (Number(limite_inf || 0) >= Number(limite_sup)) throw new Error('El mínimo tiene que ser menor que el máximo')
    e.limite_sup = Number(limite_sup)
    e.limite_inf = Number(limite_inf || 0)
    e.peso_kg = peso_kg === '' || peso_kg == null ? null : Number(peso_kg)
    e.indicaciones.push({
      desde: iso(0), limite_sup: e.limite_sup, limite_inf: e.limite_inf, peso_kg: e.peso_kg, nota: nota || null,
    })
  },
  async dispositivosLibres() {
    const ocupados = new Set(episodios.filter((e) => !e.fin).map((e) => e.dispositivo_serie))
    return dispositivos.filter((d) => !ocupados.has(d.serie))
  },
  async crearPacienteYEpisodio(d) {
    await espera()
    const p = { id: uuid(), codigo: `P-${String(118 + pacientes.length).padStart(6, '0')}`,
      nombre: d.nombre, apellido: d.apellido, documento: d.documento || null }
    pacientes.push(p)
    const e = { id: uuid(), paciente_id: p.id, dispositivo_serie: d.dispositivo_serie || null,
      miembro: d.miembro, lesion: d.lesion, fecha_cirugia: d.fecha_cirugia || null, inicio: iso(0), fin: null,
      limite_sup: Number(d.limite_sup), limite_inf: Number(d.limite_inf || 0), peso_kg: Number(d.peso_kg) || null,
      token_sync: uuid(), resumenes: [],
      indicaciones: [{ desde: iso(0), limite_sup: Number(d.limite_sup), limite_inf: Number(d.limite_inf || 0), peso_kg: Number(d.peso_kg) || null, nota: null }] }
    episodios.push(e)
    return { paciente: p, episodio: e }
  },
  async cerrarEpisodio(id) {
    const e = episodios.find((x) => x.id === id)
    if (e) e.fin = iso(0)
  },

  // Imita a la función `subir-datos`: valida el token y hace upsert por fecha.
  async subirDesdeOrtesis(token, { resumenes = [], registros = [], equipo }) {
    await espera()
    const ep = episodios.find((e) => e.token_sync === token && !e.fin)
    if (!ep) throw new Error('Episodio inexistente o cerrado')
    for (const r of resumenes) {
      const i = ep.resumenes.findIndex((x) => x.fecha === r.fecha)
      if (i >= 0) ep.resumenes[i] = r
      else ep.resumenes.push(r)
    }
    if (equipo) {
      ep.equipo_visto = equipo
      ep.equipo_visto_en = new Date().toISOString()
    }
    return { ok: true, resumenes: resumenes.length, registros: registros.length, equipo: !!equipo }
  },
}
