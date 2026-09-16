import { fmt } from '../datos/indices.js'

// Cada día es una franja: debajo del mínimo, dentro de la indicación, por encima del límite.
export default function CarrilVentana({ dias, conMinimo }) {
  const orden = [...dias].reverse()
  return (
    <div className="carril">
      <p className="carril-leyenda">
        {conMinimo && <span><i className="c-sub" /> Por debajo del mínimo</span>}
        <span><i className="c-ven" /> {conMinimo ? 'Dentro de la indicación' : 'Por debajo del límite'}</span>
        <span><i className="c-exc" /> Por encima del límite</span>
      </p>
      <ol>
        {orden.map((d) => (
          <li key={d.fecha}>
            <span className="carril-fecha">{fmt.fecha(d.fecha)}</span>
            <span className="carril-barra"
              aria-label={`${fmt.pct(d.frac_sub * 100)} debajo, ${fmt.pct(d.frac_ventana * 100)} dentro, ${fmt.pct(d.frac_exceso * 100)} encima`}>
              {d.frac_sub > 0 && <span className="c-sub" style={{ flexGrow: d.frac_sub }} />}
              <span className="c-ven" style={{ flexGrow: d.frac_ventana }} />
              {d.frac_exceso > 0 && <span className="c-exc" style={{ flexGrow: d.frac_exceso }}>
                {d.frac_exceso >= 0.08 && fmt.num(d.frac_exceso * 100) + ' %'}
              </span>}
            </span>
            <span className="carril-horas">{fmt.num(d.horas_uso, 1)} h</span>
            <span className="carril-exc">{d.excedencias} exc.</span>
          </li>
        ))}
      </ol>
    </div>
  )
}
