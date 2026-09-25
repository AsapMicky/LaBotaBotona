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
    async indicacionesDe(episodioId) {
      return ok(await db.from('indicaciones').select('*')
        .eq('episodio_id', episodioId).order('desde').order('creado'))
    },
    // Una sola operación del lado del servidor: cambia el episodio y deja la historia.
    async cambiarIndicacion(episodioId, { limite_sup, limite_inf, peso_kg, nota }) {
      const { error } = await db.rpc('cambiar_indicacion', {
        ep: episodioId,
        sup: Number(limite_sup),
        inf: Number(limite_inf || 0),
        peso: peso_kg === '' || peso_kg == null ? null : Number(peso_kg),
        nota_txt: nota || null,
      })
      if (error) throw new Error(error.message)
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

    // Lo que se bajó de la ortesis en la consulta va por la misma puerta que usa la app:
    // la función `subir-datos`, que valida el token del episodio del lado del servidor.
    // Las policies no dejan escribir estas tablas desde el navegador, y está bien así.
    async subirDesdeOrtesis(token, { resumenes = [], registros = [], equipo }) {
      const r = await fetch(`${url.replace(/\/+$/, '')}/functions/v1/subir-datos`, {
        method: 'POST',
        headers: { 'content-type': 'application/json' },
        // `origen` importa: esto lo hace el médico en la consulta, no el paciente
        // sincronizando, así que no cuenta como sincronización de la app.
        body: JSON.stringify({ token, resumenes, registros, origen: 'consultorio', ...(equipo ? { equipo } : {}) }),
      })
      if (!r.ok) throw new Error(await r.text() || `El servidor respondió ${r.status}`)
      return r.json()
    },

    /**
     * Avisa cuando algo cambia en el episodio que el médico está mirando: datos nuevos
     * que subió la app, o el propio episodio (la marca de sincronización).
     *
     * Se filtra por episodio a propósito. Escuchar la tabla entera obligaría a evaluar
     * las policies sobre cada fila que cambie en el sistema; así solo llega lo de este
     * paciente. Devuelve la función para darse de baja.
     */
    escucharEpisodio(episodioId, { alCambiar, alEstado } = {}) {
      const canal = db.channel(`episodio-${episodioId}`)
        .on('postgres_changes',
          { event: '*', schema: 'public', table: 'resumenes_diarios', filter: `episodio_id=eq.${episodioId}` },
          () => alCambiar?.())
        .on('postgres_changes',
          { event: 'UPDATE', schema: 'public', table: 'episodios', filter: `id=eq.${episodioId}` },
          () => alCambiar?.())
        .subscribe((estado) => alEstado?.(estado))
      return () => { db.removeChannel(canal) }
    },
  }
}
