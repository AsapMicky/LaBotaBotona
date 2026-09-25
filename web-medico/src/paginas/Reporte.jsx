import { useCallback, useEffect, useMemo, useState } from 'react'
import { fuente } from '../datos/fuente.js'
import { diasEntre, fmt, indices } from '../datos/indices.js'
import GraficoDosis from '../componentes/GraficoDosis.jsx'
import CarrilVentana from '../componentes/CarrilVentana.jsx'
import Consultorio from '../componentes/Consultorio.jsx'
import QrVinculacion from '../componentes/QrVinculacion.jsx'
import Indicacion from '../componentes/Indicacion.jsx'

const media = (xs) => {
  const v = xs.filter((x) => x != null)
  return v.length ? v.reduce((a, b) => a + b, 0) / v.length : null
}

function observaciones(dias, ep) {
  const obs = []
  if (!dias.length) return obs
  const ult = dias.slice(-7)
  const prev = dias.slice(-14, -7)
  const cU = media(ult.map((d) => d.cumplimiento))
  const cP = media(prev.map((d) => d.cumplimiento))
  if (cU != null && cP != null && cU - cP <= -5)
    obs.push(`El cumplimiento bajó ${fmt.num(cP - cU, 1)} puntos respecto de la semana anterior.`)
  if (cU != null && cP != null && cU - cP >= 5)
    obs.push(`El cumplimiento mejoró ${fmt.num(cU - cP, 1)} puntos respecto de la semana anterior.`)
  const sub = media(ult.map((d) => d.frac_sub))
  if (ep.limite_inf > 0 && sub > 0.3)
    obs.push(`Pasa el ${fmt.num(sub * 100)} % del tiempo de apoyo por debajo del mínimo indicado.`)
  const ultimo = dias[dias.length - 1].fecha
  const sinDatos = diasEntre(ultimo)
  if (!ep.fin && sinDatos > 2) obs.push(`No hay datos desde hace ${sinDatos} días. Puede que no esté usando la ortesis o que no haya sincronizado.`)
  return obs
}

export default function Reporte({ paciente, onCambio }) {
  const [episodios, setEpisodios] = useState(null)
  const [epId, setEpId] = useState(null)
  const [resumenes, setResumenes] = useState(null)
  const [indicaciones, setIndicaciones] = useState(null)
  const [ventana, setVentana] = useState(14)
  const [mostrarQr, setMostrarQr] = useState(false)

  useEffect(() => {
    fuente.episodiosDe(paciente.id).then((eps) => {
      setEpisodios(eps)
      setEpId((eps.find((e) => !e.fin) ?? eps[0])?.id ?? null)
    })
  }, [paciente.id])

  useEffect(() => {
    if (!epId) return
    setResumenes(null)
    setIndicaciones(null)
    fuente.resumenesDe(epId).then(setResumenes)
    fuente.indicacionesDe(epId).then(setIndicaciones)
  }, [epId])

  // Cambiar la indicación modifica el episodio, así que hay que releer los dos.
  const recargarIndicacion = useCallback(async () => {
    setEpisodios(await fuente.episodiosDe(paciente.id))
    if (epId) setIndicaciones(await fuente.indicacionesDe(epId))
  }, [paciente.id, epId])

  // Mientras el reporte está abierto, la web escucha lo que pasa con este episodio: si el
  // paciente sincroniza, el gráfico y la marca de sincronización se actualizan solos.
  // Si el canal no engancha (red que bloquea WebSockets), se cae a preguntar cada 20 s.
  useEffect(() => {
    if (!epId) return undefined
    let vivo = true
    let suscripto = false
    let respaldo = null

    const refrescar = async () => {
      if (!vivo) return
      const [res, eps] = await Promise.all([fuente.resumenesDe(epId), fuente.episodiosDe(paciente.id)])
      if (!vivo) return
      setResumenes(res)
      setEpisodios(eps)
    }
    const arrancarRespaldo = () => { if (!respaldo) respaldo = setInterval(refrescar, 20000) }
    const frenarRespaldo = () => { clearInterval(respaldo); respaldo = null }

    // Si en unos segundos no llegó ninguna confirmación, no esperamos más.
    const revisar = setTimeout(() => { if (!suscripto) arrancarRespaldo() }, 6000)

    const cancelar = fuente.escucharEpisodio(epId, {
      alCambiar: refrescar,
      alEstado: (estado) => {
        suscripto = estado === 'SUBSCRIBED'
        if (suscripto) frenarRespaldo()
        else arrancarRespaldo()
      },
    })

    return () => {
      vivo = false
      clearTimeout(revisar)
      frenarRespaldo()
      cancelar?.()
    }
  }, [epId, paciente.id])

  // Después de descargar la ortesis en la consulta, el reporte se rearma solo.
  const recargarResumenes = async () => {
    if (epId) setResumenes(await fuente.resumenesDe(epId))
  }

  const ep = episodios?.find((e) => e.id === epId)
  const dias = useMemo(
    () => (resumenes ?? []).map(indices).sort((a, b) => a.fecha.localeCompare(b.fecha)),
    [resumenes],
  )
  const visibles = ventana ? dias.slice(-ventana) : dias
  const semana = dias.slice(-7)

  if (!episodios) return <p className="cargando">Cargando…</p>

  return (
    <article className="reporte">
      <header className="rp-cabecera">
        <div>
          <h1>{paciente.nombre} {paciente.apellido}</h1>
          <p className="rp-id">
            <span>{paciente.codigo}</span>
            {paciente.documento && <span>DNI {paciente.documento}</span>}
          </p>
        </div>
        {episodios.length > 1 && (
          <label className="selector-episodio">
            Tratamiento
            <select value={epId ?? ''} onChange={(e) => setEpId(e.target.value)}>
              {episodios.map((e) => (
                <option key={e.id} value={e.id}>
                  {e.fin ? `${fmt.fechaLarga(e.inicio)} a ${fmt.fechaLarga(e.fin)}` : 'Actual'}: {e.lesion}
                </option>
              ))}
            </select>
          </label>
        )}
      </header>

      {!ep ? (
        <div className="vacio"><p>Este paciente no tiene tratamientos cargados.</p></div>
      ) : (
        <>
          <dl className="rp-episodio">
            <div><dt>Lesión</dt><dd>{ep.lesion}, miembro {ep.miembro}</dd></div>
            <div><dt>{ep.fin ? 'Duración' : 'Día de tratamiento'}</dt><dd>
              {ep.fin ? `${diasEntre(ep.inicio, ep.fin)} días` : diasEntre(ep.inicio) + 1}
              <span className="suave"> desde el {fmt.fechaLarga(ep.inicio)}</span>
            </dd></div>
            <div><dt>Ortesis</dt><dd>{ep.dispositivo_serie ? `N.º ${ep.dispositivo_serie}` : 'Devuelta'}</dd></div>
          </dl>

          <Indicacion episodio={ep} historia={indicaciones} onCambio={recargarIndicacion} />

          {resumenes === null ? (
            <p className="cargando">Cargando registros…</p>
          ) : dias.length === 0 ? (
            <div className="vacio">
              <h2>Sin registros todavía</h2>
              <p>Los datos aparecen cuando el paciente sincroniza la app o cuando descargás la ortesis en la consulta.</p>
            </div>
          ) : (
            <>
              <section className="bloque">
                <h2>{ep.fin ? `Última semana del tratamiento` : `Últimos ${semana.length} días`}</h2>
                <div className="metricas">
                  <Metrica valor={fmt.pct(media(semana.map((d) => d.cumplimiento)))} nombre="Cumplimiento"
                    ayuda="Del tiempo que apoyó, qué parte estuvo por debajo del límite." />
                  {ep.limite_inf > 0 && (
                    <Metrica valor={fmt.pct(media(semana.map((d) => d.permanencia)))} nombre="Dentro de la indicación"
                      ayuda="Del tiempo que apoyó, qué parte estuvo entre el mínimo y el máximo." />
                  )}
                  <Metrica valor={fmt.num(media(semana.map((d) => d.dosis_sobrecarga)))} unidad="%PC·min"
                    nombre="Dosis de sobrecarga diaria" ayuda="Cuánto y durante cuánto tiempo superó el límite, promedio por día." />
                  <Metrica valor={fmt.num(Math.max(...semana.map((d) => d.pico)))} unidad="%PC" nombre="Carga pico" />
                  <Metrica valor={fmt.num(media(semana.map((d) => d.excedencias)))} nombre="Excedencias por día" />
                  <Metrica valor={fmt.num(media(semana.map((d) => d.horas_uso)), 1)} unidad="h" nombre="Apoyo por día" />
                </div>
                {observaciones(dias, ep).length > 0 && (
                  <ul className="observaciones">
                    {observaciones(dias, ep).map((o) => <li key={o}>{o}</li>)}
                  </ul>
                )}
              </section>

              <section className="bloque">
                <div className="bloque-cabecera">
                  <h2>Evolución</h2>
                  <div className="segmentado" role="group" aria-label="Período">
                    {[[7, '7 días'], [14, '14 días'], [0, 'Todo']].map(([v, t]) => (
                      <button key={v} aria-pressed={ventana === v} onClick={() => setVentana(v)}>{t}</button>
                    ))}
                  </div>
                </div>
                <GraficoDosis dias={visibles} cambios={(indicaciones ?? []).slice(1)} />
              </section>

              <section className="bloque">
                <h2>Cómo repartió el apoyo cada día</h2>
                <CarrilVentana dias={visibles} conMinimo={ep.limite_inf > 0} />
              </section>
            </>
          )}

          {!ep.fin && (
            <section className="bloque">
              <div className="bloque-cabecera">
                <h2>La app del paciente</h2>
                <button onClick={() => setMostrarQr((v) => !v)}>
                  {mostrarQr ? 'Ocultar el código' : 'Mostrar el código'}
                </button>
              </div>
              {mostrarQr && (
                <div className="alta-qr">
                  <QrVinculacion episodio={ep} tamano={180} />
                  <div>
                    <p>El paciente lo escanea desde la app y queda vinculado a este tratamiento, sin crear una cuenta.</p>
                    <p className="suave">
                      Sirve también si cambió de teléfono: mostráselo de nuevo y listo. El código anterior deja de
                      funcionar solo cuando se cierra el tratamiento.
                    </p>
                  </div>
                </div>
              )}
              <AppDelPaciente ep={ep} />
              <EquipoCargado ep={ep} />
            </section>
          )}

          {!ep.fin && <Consultorio episodio={ep} onCerrado={onCambio} onDatos={recargarResumenes} />}
        </>
      )}
    </article>
  )
}

// Si el paciente escaneó el código y cuándo sincronizó por última vez. La app avisa cada
// vez que habla con el servidor, incluso cuando no trae datos nuevos: el acuse que manda
// apenas se escanea el QR es lo que marca la vinculación.
function AppDelPaciente({ ep }) {
  // Refresco suave para que "hace unos segundos" no se quede congelado entre sincronizaciones.
  const [, redibujar] = useState(0)
  useEffect(() => {
    const t = setInterval(() => redibujar((n) => n + 1), 30000)
    return () => clearInterval(t)
  }, [])

  if (!ep.vinculada_en) {
    return (
      <p className="nota">
        El paciente todavía no escaneó el código. Mientras tanto la ortesis sigue registrando:
        los datos llegan igual cuando la descargues en la consulta.
      </p>
    )
  }
  const sinDatosHace = ep.ultima_sincronizacion
    ? (Date.now() - new Date(ep.ultima_sincronizacion).getTime()) / 86400000
    : null

  return (
    <p className={sinDatosHace > 3 ? 'nota' : undefined}>
      App vinculada el <strong>{fmt.fechaLarga(ep.vinculada_en.slice(0, 10))}</strong>.{' '}
      Última sincronización <strong>{fmt.hace(ep.ultima_sincronizacion)}</strong>.
      {sinDatosHace > 3 && ' Puede que haya dejado de abrir la app.'}
    </p>
  )
}

// Qué tiene cargado la ortesis de verdad, según lo último que informó. Es la forma de
// confirmar que la indicación llegó al equipo y que alguien la confirmó con el pulsador:
// un límite enviado por Bluetooth no entra en vigencia hasta ese momento.
function EquipoCargado({ ep }) {
  const v = ep.equipo_visto
  if (!v) {
    return (
      <p className="nota">
        La ortesis todavía no informó su configuración. Aparece cuando el paciente sincroniza la app
        o cuando la descargás en la consulta.
      </p>
    )
  }
  const igual = (a, b) => Math.abs(Number(a) - Number(b)) < 0.05
  const limitesOk = igual(v.limite_sup, ep.limite_sup) && igual(v.limite_inf, ep.limite_inf)
  const pesoOk = !ep.peso_kg || igual(v.peso_kg, ep.peso_kg)
  const episodioOk = !v.episodio || v.episodio === ep.id.replace(/-/g, '').slice(0, 16)
  const cuando = ep.equipo_visto_en
    ? new Date(ep.equipo_visto_en).toLocaleString('es-AR', { day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' })
    : null

  return (
    <div className="equipo-cargado">
      <p>
        La ortesis {v.serie ? <strong>N.º {v.serie}</strong> : 'conectada'}
        {v.firmware && <span className="suave"> (firmware {v.firmware})</span>}
        {cuando && <span className="suave"> informó el {cuando}</span>}:{' '}
        {v.limite_inf > 0
          ? `entre ${fmt.num(v.limite_inf)} y ${fmt.num(v.limite_sup)} %`
          : `hasta ${fmt.num(v.limite_sup)} %`} del peso corporal, con {fmt.num(v.peso_kg)} kg de peso.
      </p>
      <ul className="observaciones">
        {limitesOk && pesoOk && episodioOk && <li>Coincide con la indicación de este tratamiento.</li>}
        {!limitesOk && (
          <li>
            <strong>Los límites no coinciden</strong> con la indicación
            ({ep.limite_inf > 0 ? `${fmt.num(ep.limite_inf)} a ` : 'hasta '}{fmt.num(ep.limite_sup)} %).
            Enviala de nuevo desde la consulta y confirmala con el botón del equipo.
          </li>
        )}
        {!pesoOk && (
          <li><strong>El peso no coincide</strong>: el tratamiento dice {fmt.num(ep.peso_kg)} kg. Los %PC salen mal.</li>
        )}
        {!episodioOk && (
          <li><strong>Esta ortesis está asignada a otro tratamiento.</strong> Reasignala antes de usarla.</li>
        )}
        {v.hay_pendiente && (
          <li>
            Hay un cambio <strong>esperando confirmación</strong>: el paciente tiene que mantener apretado
            el botón de la ortesis 2 segundos para que entre en vigencia.
          </li>
        )}
      </ul>
    </div>
  )
}

function Metrica({ valor, unidad, nombre, ayuda }) {
  return (
    <div className="metrica" title={ayuda}>
      <span className="m-valor">{valor}{unidad && <small> {unidad}</small>}</span>
      <span className="m-nombre">{nombre}</span>
    </div>
  )
}
