import { Bar, CartesianGrid, ComposedChart, Legend, Line, ReferenceLine, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { fmt } from '../datos/indices.js'

/**
 * [cambios] son las indicaciones posteriores a la inicial. Se marcan porque la dosis de
 * sobrecarga es la integral de lo que excede el límite: si el límite cambió, las barras
 * de antes y las de después no miden lo mismo. La línea de cumplimiento sí es comparable,
 * porque es relativa al límite que regía cada día.
 */
export default function GraficoDosis({ dias, cambios = [] }) {
  const datos = dias.map((d) => ({ ...d, etiqueta: fmt.fecha(d.fecha) }))

  // Un cambio se dibuja sobre el primer día visible desde que rige. Si el cambio es
  // posterior al último día con datos, todavía no hay nada que separar.
  const marcas = cambios
    .map((c) => {
      const dia = datos.find((d) => d.fecha >= c.desde)
      return dia ? { etiqueta: dia.etiqueta, desde: c.desde } : null
    })
    .filter(Boolean)
    .filter((m, i, todas) => todas.findIndex((x) => x.etiqueta === m.etiqueta) === i)

  return (
    <div className="grafico">
      <ResponsiveContainer width="100%" height={280}>
        <ComposedChart data={datos} margin={{ top: 8, right: 8, bottom: 0, left: 0 }}>
          <CartesianGrid stroke="var(--linea)" vertical={false} />
          <XAxis dataKey="etiqueta" tick={{ fontSize: 12 }} tickLine={false} axisLine={false} minTickGap={16} />
          <YAxis yAxisId="d" tick={{ fontSize: 12 }} tickLine={false} axisLine={false} width={44}
            label={{ value: '%PC·min', angle: -90, position: 'insideLeft', fontSize: 11, dy: 30 }} />
          <YAxis yAxisId="c" orientation="right" domain={[0, 100]} tick={{ fontSize: 12 }} tickLine={false}
            axisLine={false} width={52} tickFormatter={(v) => `${v} %`} />
          <Tooltip
            formatter={(v, n) => (n === 'Cumplimiento' ? fmt.pct(v) : `${fmt.num(v)} %PC·min`)}
            labelStyle={{ fontWeight: 600 }}
          />
          <Legend iconType="circle" wrapperStyle={{ fontSize: 13 }} />
          {marcas.map((m) => (
            <ReferenceLine
              key={m.desde}
              yAxisId="d"
              x={m.etiqueta}
              stroke="var(--petroleo)"
              strokeDasharray="4 4"
              label={{ value: 'nueva indicación', position: 'top', fontSize: 11, fill: 'var(--petroleo)' }}
            />
          ))}
          <Bar yAxisId="d" dataKey="dosis_sobrecarga" name="Dosis de sobrecarga" fill="var(--ambar)" radius={[3, 3, 0, 0]} maxBarSize={28} />
          <Line yAxisId="c" dataKey="cumplimiento" name="Cumplimiento" stroke="var(--petroleo)" strokeWidth={2.5} dot={false} />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  )
}
