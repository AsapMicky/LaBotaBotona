import { useState } from 'react'
import { fuente } from '../datos/fuente.js'
import { fmt } from '../datos/indices.js'

const texto = (ind) =>
  ind.limite_inf > 0
    ? `entre ${fmt.num(ind.limite_inf)} y ${fmt.num(ind.limite_sup)} %`
    : `hasta ${fmt.num(ind.limite_sup)} %`

/**
 * Cambiar la indicación durante el tratamiento. En rehabilitación la carga permitida se
 * progresa, y el peso de la persona cambia en meses: sin esto había que cerrar el
 * episodio y abrir otro, lo que partía la serie de datos en dos.
 *
 * El cambio no entra en vigencia en la ortesis hasta que se le envía por Bluetooth en la
 * consulta y el paciente lo confirma con el pulsador. El bloque de arriba avisa cuando
 * lo que tiene cargado el equipo no coincide con lo que dice acá.
 */
export default function Indicacion({ episodio, historia, onCambio }) {
  const [abierto, setAbierto] = useState(false)
  const [d, setD] = useState(null)
  const [error, setError] = useState(null)
  const [guardando, setGuardando] = useState(false)

  const abrir = () => {
    setError(null)
    setD({
      limite_sup: episodio.limite_sup,
      limite_inf: episodio.limite_inf,
      peso_kg: episodio.peso_kg ?? '',
      nota: '',
    })
    setAbierto(true)
  }

  const campo = (k) => ({ value: d[k], onChange: (e) => setD({ ...d, [k]: e.target.value }) })

  async function guardar(ev) {
    ev.preventDefault()
    setError(null)
    if (Number(d.limite_inf || 0) >= Number(d.limite_sup)) {
      setError('El mínimo tiene que ser menor que el máximo.')
      return
    }
    setGuardando(true)
    try {
      await fuente.cambiarIndicacion(episodio.id, d)
      setAbierto(false)
      await onCambio?.()
    } catch (e) {
      setError(e.message)
    } finally {
      setGuardando(false)
    }
  }

  const cambios = (historia ?? []).slice(1)

  return (
    <section className="bloque">
      <div className="bloque-cabecera">
        <h2>Indicación</h2>
        {!episodio.fin && !abierto && <button onClick={abrir}>Cambiar la indicación</button>}
      </div>

      {!abierto ? (
        <p>
          Apoyar <strong>{texto(episodio)}</strong> del peso corporal
          {episodio.peso_kg && (
            <span className="suave">
              {' '}({fmt.num((episodio.peso_kg * episodio.limite_sup) / 100, 1)} kg como máximo, con {fmt.num(episodio.peso_kg)} kg de peso)
            </span>
          )}.
        </p>
      ) : (
        <form className="alta" onSubmit={guardar}>
          <fieldset>
            <legend>Nueva indicación</legend>
            <label>Carga máxima (%PC)
              <input type="number" min="1" max="100" step="0.5" required {...campo('limite_sup')} /></label>
            <label>Carga mínima (%PC) <span className="suave">0 si no se indica</span>
              <input type="number" min="0" max="100" step="0.5" {...campo('limite_inf')} /></label>
            <label>Peso corporal (kg)
              <input type="number" min="20" max="250" step="0.1" required {...campo('peso_kg')} /></label>
            <label className="doble">Por qué <span className="suave">(opcional, queda en el historial)</span>
              <input placeholder="Ej.: buena evolución, se progresa la carga" {...campo('nota')} /></label>
          </fieldset>
          <p className="nota">
            Queda registrado con la fecha de hoy. Para que entre en vigencia hay que enviarla a la ortesis
            desde la consulta y que el paciente la confirme con el botón del equipo.
          </p>
          {error && <p className="error" role="alert">{error}</p>}
          <div className="acciones">
            <button type="button" onClick={() => setAbierto(false)} disabled={guardando}>Cancelar</button>
            <button className="primario" disabled={guardando}>{guardando ? 'Guardando…' : 'Guardar'}</button>
          </div>
        </form>
      )}

      {cambios.length > 0 && (
        <>
          <h3 className="sub">Cambios durante el tratamiento</h3>
          <ul className="historia-indicaciones">
            {[...(historia ?? [])].reverse().map((i, pos) => (
              <li key={`${i.desde}-${pos}`}>
                <strong>{fmt.fechaLarga(i.desde)}</strong>: {texto(i)} del peso corporal
                {i.peso_kg && <span className="suave">, con {fmt.num(i.peso_kg)} kg</span>}
                {pos === cambios.length && <span className="suave"> (indicación inicial)</span>}
                {i.nota && <div className="suave">{i.nota}</div>}
              </li>
            ))}
          </ul>
          <p className="nota">
            La dosis de sobrecarga se mide contra el límite que regía cada día, así que las barras de antes y
            después de un cambio no son comparables entre sí. El cumplimiento y la permanencia en ventana sí:
            son porcentajes relativos a su propio límite.
          </p>
        </>
      )}
    </section>
  )
}
