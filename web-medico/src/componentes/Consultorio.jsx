import { useState } from 'react'
import { bluetoothDisponible, conectarOrtesis } from '../ble/consultorio.js'
import { fuente } from '../datos/fuente.js'
import { fmt } from '../datos/indices.js'

// Acciones en la consulta con la ortesis al lado de la computadora.
// Es el camino que funciona aunque el paciente nunca haya instalado la app.
export default function Consultorio({ episodio, onCerrado, onDatos }) {
  const [ortesis, setOrtesis] = useState(null)
  const [info, setInfo] = useState(null)
  const [hoy, setHoy] = useState(null)
  const [mensaje, setMensaje] = useState(null)
  const [error, setError] = useState(null)
  const [bajando, setBajando] = useState(null)

  async function accion(fn) {
    setError(null); setMensaje(null)
    try { await fn() } catch (e) { setError(e.message) }
  }

  const conectar = () => accion(async () => {
    const o = await conectarOrtesis()
    setOrtesis(o)
    setInfo(await o.leerInfo())
    setHoy(await o.leerResumenHoy())
  })

  const descargar = () => accion(async () => {
    setBajando('Leyendo los días guardados…')
    try {
      const cerrados = await ortesis.descargarResumenes(new Date(0), (n) => setBajando(`${n} días leídos…`))
      const delDia = await ortesis.leerResumenHoy()
      setHoy(delDia)
      // Un upsert no puede tocar dos veces la misma fila: una fecha, un resumen.
      // El día en curso va último, así pisa cualquier versión parcial del mismo día.
      const porFecha = new Map([...cerrados, delDia].map((r) => [r.fecha, r]))

      setBajando('Leyendo el detalle minuto a minuto…')
      const registros = await ortesis.descargarHistorial(new Date(0), (n) => setBajando(`${n} minutos leídos…`))

      setBajando('Enviando al servidor…')
      const r = await fuente.subirDesdeOrtesis(episodio.token_sync, {
        resumenes: [...porFecha.values()],
        registros,
      })
      setMensaje(`Descarga lista: ${r.resumenes} ${r.resumenes === 1 ? 'día' : 'días'} y ${r.registros} minutos de registro.`)
      await onDatos?.()
    } finally {
      setBajando(null)
    }
  })

  const idCorto = episodio.id.replace(/-/g, '').slice(0, 16)
  const coincide = info && info.episodio === idCorto
  const ocupado = bajando != null

  return (
    <section className="bloque consultorio">
      <h2>En la consulta</h2>
      {!bluetoothDisponible() ? (
        <p className="nota">Para conectar la ortesis desde acá hace falta Chrome o Edge en una computadora con Bluetooth.</p>
      ) : !ortesis ? (
        <button onClick={conectar}>Conectar la ortesis</button>
      ) : (
        <div className="consultorio-conectado">
          <p>
            Conectada a <strong>{ortesis.nombre}</strong>, firmware {info?.firmware}.{' '}
            {info?.episodio ? (coincide ? 'Asignada a este tratamiento.' : 'Asignada a otro tratamiento.') : 'Sin asignar.'}
          </p>
          {hoy && (
            <p className="suave">
              Hoy: {fmt.num(hoy.dosis_sobrecarga)} %PC·min de sobrecarga, {hoy.excedencias} excedencias,
              pico {fmt.num(hoy.pico)} %PC.
            </p>
          )}
          <div className="acciones">
            <button className="primario" disabled={ocupado || !coincide} onClick={descargar}
              title={coincide ? 'Trae todo lo que la ortesis tenga guardado' : 'Primero asignala a este tratamiento'}>
              {ocupado ? 'Descargando…' : 'Descargar lo guardado'}
            </button>
            {!coincide && (
              <button disabled={ocupado} onClick={() => accion(async () => {
                await ortesis.escribirEpisodio(episodio.id)
                setInfo(await ortesis.leerInfo())
                setMensaje('Ortesis asignada a este tratamiento.')
              })}>Asignar a este tratamiento</button>
            )}
            <button disabled={ocupado} onClick={() => accion(async () => {
              await ortesis.proponerLimites(episodio)
              setMensaje('Indicación enviada. Pedile al paciente que mantenga apretado el botón de la ortesis 2 segundos para aplicarla.')
            })}>Enviar la indicación actual</button>
            <button className="peligro" disabled={ocupado} onClick={() => accion(async () => {
              if (!confirm('Se cierra el tratamiento y se borra la memoria de la ortesis. ¿Descargaste los datos primero?')) return
              await ortesis.escribirEpisodio('')
              await fuente.cerrarEpisodio(episodio.id)
              ortesis.desconectar()
              setOrtesis(null)
              onCerrado?.()
            })}>Registrar devolución</button>
          </div>
          {bajando && <p className="nota" role="status">{bajando}</p>}
        </div>
      )}
      {mensaje && <p className="ok" role="status">{mensaje}</p>}
      {error && <p className="error" role="alert">{error}</p>}
    </section>
  )
}
