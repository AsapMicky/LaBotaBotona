import { useEffect, useState } from 'react'
import { fuente } from '../datos/fuente.js'
import QrVinculacion from '../componentes/QrVinculacion.jsx'

const inicial = {
  nombre: '', apellido: '', documento: '', miembro: 'izquierdo', lesion: '',
  fecha_cirugia: '', limite_sup: 20, limite_inf: 0, peso_kg: '', dispositivo_serie: '',
}

export default function AltaPaciente({ onCancelar, onCreado }) {
  const [d, setD] = useState(inicial)
  const [libres, setLibres] = useState([])
  const [error, setError] = useState(null)
  const [creado, setCreado] = useState(null)

  useEffect(() => { fuente.dispositivosLibres().then(setLibres) }, [])
  const campo = (k) => ({ value: d[k], onChange: (e) => setD({ ...d, [k]: e.target.value }) })

  async function guardar(ev) {
    ev.preventDefault()
    setError(null)
    if (Number(d.limite_inf) >= Number(d.limite_sup)) {
      setError('El mínimo tiene que ser menor que el máximo.')
      return
    }
    try {
      setCreado(await fuente.crearPacienteYEpisodio(d))
    } catch (e) {
      setError(e.message)
    }
  }

  if (creado) {
    return (
      <article className="alta">
        <h1>Alta registrada: {creado.paciente.nombre} {creado.paciente.apellido}</h1>
        <p>Código interno <strong>{creado.paciente.codigo}</strong>.</p>
        <div className="alta-qr">
          <QrVinculacion episodio={creado.episodio} />
          <div>
            <h2>Vincular la app del paciente</h2>
            <p>El paciente escanea este código desde la app. Queda vinculada a este tratamiento sin crear una cuenta.</p>
            <p>Después, conectá la ortesis desde el reporte para asignarla y enviarle la indicación.</p>
          </div>
        </div>
        <button className="primario" onClick={() => onCreado(creado.paciente.id)}>Ir al reporte</button>
      </article>
    )
  }

  return (
    <form className="alta" onSubmit={guardar}>
      <h1>Dar de alta un paciente</h1>
      <fieldset>
        <legend>Paciente</legend>
        <label>Nombre<input required {...campo('nombre')} /></label>
        <label>Apellido<input required {...campo('apellido')} /></label>
        <label>DNI <span className="suave">(solo como referencia)</span><input inputMode="numeric" {...campo('documento')} /></label>
      </fieldset>
      <fieldset>
        <legend>Tratamiento</legend>
        <label className="doble">Lesión<input required placeholder="Ej.: fractura bimaleolar" {...campo('lesion')} /></label>
        <label>Miembro
          <select {...campo('miembro')}>
            <option value="izquierdo">Izquierdo</option>
            <option value="derecho">Derecho</option>
          </select>
        </label>
        <label>Fecha de cirugía<input type="date" {...campo('fecha_cirugia')} /></label>
        <label>Carga máxima (%PC)<input type="number" min="1" max="100" step="0.5" required {...campo('limite_sup')} /></label>
        <label>Carga mínima (%PC) <span className="suave">0 si no se indica</span>
          <input type="number" min="0" max="100" step="0.5" {...campo('limite_inf')} /></label>
        <label>Peso corporal (kg)<input type="number" min="20" max="250" step="0.1" required {...campo('peso_kg')} /></label>
        <label>Ortesis
          <select {...campo('dispositivo_serie')}>
            <option value="">Asignar después</option>
            {libres.map((x) => <option key={x.serie} value={x.serie}>N.º {x.serie}</option>)}
          </select>
        </label>
      </fieldset>
      {error && <p className="error" role="alert">{error}</p>}
      <div className="acciones">
        <button type="button" onClick={onCancelar}>Cancelar</button>
        <button className="primario">Dar de alta</button>
      </div>
    </form>
  )
}
