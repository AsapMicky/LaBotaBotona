import { useCallback, useEffect, useState } from 'react'
import { fuente } from '../datos/fuente.js'
import { fmt, tendencia } from '../datos/indices.js'
import Reporte from './Reporte.jsx'
import AltaPaciente from './AltaPaciente.jsx'

export default function Panel({ usuario, onSalir }) {
  const [pacientes, setPacientes] = useState(null)
  const [tendencias, setTendencias] = useState({})
  const [seleccion, setSeleccion] = useState(null)
  const [modo, setModo] = useState('reporte')
  const [filtro, setFiltro] = useState('')

  const cargar = useCallback(async (elegir) => {
    const lista = await fuente.listarPacientes()
    setPacientes(lista)
    // Elegir antes de las tendencias: si no, mientras cargan se ve "todavía no hay pacientes".
    setSeleccion((s) => elegir ?? s ?? lista[0]?.id ?? null)
    const t = {}
    await Promise.all(lista.filter((p) => p.episodioActual).map(async (p) => {
      t[p.id] = tendencia(await fuente.resumenesDe(p.episodioActual.id))
    }))
    setTendencias(t)
  }, [])

  useEffect(() => { cargar() }, [cargar])

  const visibles = (pacientes ?? []).filter((p) =>
    `${p.apellido} ${p.nombre} ${p.codigo} ${p.documento ?? ''}`.toLowerCase().includes(filtro.toLowerCase()))
  const actual = pacientes?.find((p) => p.id === seleccion)

  return (
    <div className="panel">
      <aside className="lateral">
        <header className="lateral-cabecera">
          <strong>Mis pacientes</strong>
          <span className="usuario">{usuario.email}</span>
        </header>
        <button className="primario ancho" onClick={() => setModo('alta')}>Dar de alta un paciente</button>
        <input className="buscar" type="search" placeholder="Buscar paciente"
          value={filtro} onChange={(e) => setFiltro(e.target.value)} aria-label="Buscar paciente" />
        <ul className="lista-pacientes">
          {pacientes === null && <li className="nota">Cargando…</li>}
          {visibles.map((p) => {
            const t = tendencias[p.id]
            return (
              <li key={p.id}>
                <button
                  className={`fila-paciente ${p.id === seleccion && modo === 'reporte' ? 'activa' : ''}`}
                  onClick={() => { setSeleccion(p.id); setModo('reporte') }}
                >
                  <span className="fp-nombre">{p.apellido}, {p.nombre}</span>
                  <span className="fp-detalle">
                    {p.episodioActual ? p.episodioActual.lesion : 'Sin tratamiento activo'}
                  </span>
                  <span className="fp-cumpl">
                    {t?.ultimos != null ? fmt.pct(t.ultimos) : '—'}
                    {t?.delta != null && Math.abs(t.delta) >= 2 && (
                      <span className={t.delta > 0 ? 'sube' : 'baja'}
                        title={`${t.delta > 0 ? 'Mejoró' : 'Empeoró'} ${Math.abs(t.delta).toFixed(1)} puntos respecto de la semana anterior`}>
                        {t.delta > 0 ? '▲' : '▼'}
                      </span>
                    )}
                  </span>
                </button>
              </li>
            )
          })}
          {pacientes && visibles.length === 0 && <li className="nota">Ningún paciente coincide con la búsqueda.</li>}
        </ul>
        <footer className="lateral-pie">
          {fuente.simulada && <span className="nota">Datos simulados</span>}
          <button className="enlace" onClick={onSalir}>Salir</button>
        </footer>
      </aside>

      <main className="contenido">
        {modo === 'alta' ? (
          <AltaPaciente
            onCancelar={() => setModo('reporte')}
            onCreado={async (id) => { await cargar(id); setModo('reporte') }}
          />
        ) : actual ? (
          <Reporte key={actual.id} paciente={actual} onCambio={() => cargar()} />
        ) : (
          <div className="vacio">
            <h2>Todavía no hay pacientes</h2>
            <p>Dá de alta el primero para asignarle una ortesis.</p>
            <button className="primario" onClick={() => setModo('alta')}>Dar de alta un paciente</button>
          </div>
        )}
      </main>
    </div>
  )
}
