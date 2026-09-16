import { useState } from 'react'
import { bluetoothDisponible, conectarOrtesis } from '../ble/consultorio.js'
import { fuente } from '../datos/fuente.js'
import { fmt } from '../datos/indices.js'

// Acciones en la consulta con la ortesis al lado de la computadora.
export default function Consultorio({ episodio, onCerrado }) {
  const [ortesis, setOrtesis] = useState(null)
  const [info, setInfo] = useState(null)
  const [hoy, setHoy] = useState(null)
  const [mensaje, setMensaje] = useState(null)
  const [error, setError] = useState(null)

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

  const idCorto = episodio.id.replace(/-/g, '').slice(0, 16)
  const coincide = info && info.episodio === idCorto

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
            {!coincide && (
              <button onClick={() => accion(async () => {
                await ortesis.escribirEpisodio(episodio.id)
                setInfo(await ortesis.leerInfo())
                setMensaje('Ortesis asignada a este tratamiento.')
              })}>Asignar a este tratamiento</button>
            )}
            <button onClick={() => accion(async () => {
              await ortesis.proponerLimites(episodio)
              setMensaje('Indicación enviada. Pedile al paciente que mantenga apretado el botón de la ortesis 2 segundos para aplicarla.')
            })}>Enviar la indicación actual</button>
            <button className="peligro" onClick={() => accion(async () => {
              if (!confirm('Se cierra el tratamiento y se borra la memoria de la ortesis. ¿Seguir?')) return
              await ortesis.escribirEpisodio('')
              await fuente.cerrarEpisodio(episodio.id)
              ortesis.desconectar()
              setOrtesis(null)
              onCerrado?.()
            })}>Registrar devolución</button>
          </div>
        </div>
      )}
      {mensaje && <p className="ok" role="status">{mensaje}</p>}
      {error && <p className="error" role="alert">{error}</p>}
    </section>
  )
}
