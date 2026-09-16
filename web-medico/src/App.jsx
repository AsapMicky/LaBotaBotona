import { useEffect, useState } from 'react'
import { fuente } from './datos/fuente.js'
import Login from './paginas/Login.jsx'
import Panel from './paginas/Panel.jsx'

export default function App() {
  const [usuario, setUsuario] = useState(undefined)

  useEffect(() => {
    fuente.sesion().then(setUsuario).catch(() => setUsuario(null))
  }, [])

  if (usuario === undefined) return <p className="cargando">Cargando…</p>
  if (!usuario) return <Login onIngreso={setUsuario} />
  return (
    <Panel
      usuario={usuario}
      onSalir={async () => {
        await fuente.salir()
        setUsuario(null)
      }}
    />
  )
}
