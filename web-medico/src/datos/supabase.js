import { createClient } from '@supabase/supabase-js'

export function crearFuenteSupabase(url, clave) {
  const db = createClient(url, clave)
  const ok = ({ data, error }) => {
    if (error) throw new Error(error.message)
    return data
  }

  return {
    simulada: false,
    async sesion() {
      const { data } = await db.auth.getUser()
      return data.user ? { email: data.user.email } : null
    },
    async ingresar(email, clave) {
      const { data, error } = await db.auth.signInWithPassword({ email, password: clave })
      if (error) throw new Error('El email o la contraseña no coinciden')
      return { email: data.user.email }
    },
    async salir() { await db.auth.signOut() },

    async listarPacientes() {
      const filas = ok(await db.from('pacientes')
        .select('*, episodios(*, dispositivos(serie))')
        .order('apellido'))
      return filas.map(({ episodios, ...p }) => {
        const actual = episodios.find((e) => !e.fin)
        return {
          ...p,
          cantidadEpisodios: episodios.length,
          episodioActual: actual ? { ...actual, dispositivo_serie: actual.dispositivos?.serie ?? null } : null,
        }
      })
    },
    async episodiosDe(pacienteId) {
      const filas = ok(await db.from('episodios').select('*, dispositivos(serie)')
        .eq('paciente_id', pacienteId).order('inicio', { ascending: false }))
      return filas.map((e) => ({ ...e, dispositivo_serie: e.dispositivos?.serie ?? null }))
    },
    async resumenesDe(episodioId) {
      return ok(await db.from('resumenes_diarios').select('*')
        .eq('episodio_id', episodioId).order('fecha'))
    },
    async dispositivosLibres() {
      const todos = ok(await db.from('dispositivos').select('id, serie').order('serie'))
      const abiertos = ok(await db.from('episodios').select('dispositivo_id').is('fin', null))
      const ocupados = new Set(abiertos.map((e) => e.dispositivo_id))
      return todos.filter((d) => !ocupados.has(d.id))
    },
    async crearPacienteYEpisodio(d) {
      const { data: u } = await db.auth.getUser()
      const paciente = ok(await db.from('pacientes').insert({
        nombre: d.nombre, apellido: d.apellido, documento: d.documento || null, medico_id: u.user.id,
      }).select().single())
      let dispositivo_id = null
      if (d.dispositivo_serie) {
        dispositivo_id = ok(await db.from('dispositivos').select('id').eq('serie', d.dispositivo_serie).single()).id
      }
      const episodio = ok(await db.from('episodios').insert({
        paciente_id: paciente.id, dispositivo_id, miembro: d.miembro, lesion: d.lesion,
        fecha_cirugia: d.fecha_cirugia || null, limite_sup: Number(d.limite_sup),
        limite_inf: Number(d.limite_inf || 0), peso_kg: Number(d.peso_kg) || null,
      }).select().single())
      return { paciente, episodio: { ...episodio, dispositivo_serie: d.dispositivo_serie || null } }
    },
    async cerrarEpisodio(id) {
      ok(await db.from('episodios').update({ fin: new Date().toISOString().slice(0, 10) }).eq('id', id))
    },
  }
}
