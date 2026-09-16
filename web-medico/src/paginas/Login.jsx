import { useState } from 'react'
import { fuente } from '../datos/fuente.js'

export default function Login({ onIngreso }) {
  const [email, setEmail] = useState(fuente.simulada ? 'medica@hospital.org' : '')
  const [clave, setClave] = useState(fuente.simulada ? 'demo' : '')
  const [error, setError] = useState(null)
  const [enviando, setEnviando] = useState(false)

  async function ingresar(ev) {
    ev.preventDefault()
    setError(null)
    setEnviando(true)
    try {
      onIngreso(await fuente.ingresar(email, clave))
    } catch (e) {
      setError(e.message)
    } finally {
      setEnviando(false)
    }
  }

  return (
    <main className="login">
      <div className="login-marca">
        <svg viewBox="0 0 64 64" aria-hidden="true" className="huella">
          <path d="M24 60c-7 0-10-6-10-14 0-9 4-14 4-22 0-8 4-14 11-14s10 7 10 14c0 9-6 12-6 20 0 6 3 8 3 11 0 3-5 5-12 5z" />
          <circle cx="44" cy="10" r="4" /><circle cx="51" cy="16" r="3.2" /><circle cx="55" cy="24" r="2.6" />
          <circle cx="56" cy="31" r="2.2" /><circle cx="55" cy="37" r="1.9" />
        </svg>
        <h1>Seguimiento de carga</h1>
        <p>Cuánto apoyaron tus pacientes entre una consulta y la siguiente.</p>
      </div>
      <form className="login-form" onSubmit={ingresar}>
        <h2>Ingresar</h2>
        <label>
          Email
          <input type="email" required value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="username" />
        </label>
        <label>
          Contraseña
          <input type="password" required value={clave} onChange={(e) => setClave(e.target.value)} autoComplete="current-password" />
        </label>
        {error && <p className="error" role="alert">{error}</p>}
        <button className="primario" disabled={enviando}>{enviando ? 'Ingresando…' : 'Ingresar'}</button>
        {fuente.simulada && <p className="nota">Modo demostración: los pacientes son simulados.</p>}
      </form>
    </main>
  )
}
