import { Bar, CartesianGrid, ComposedChart, Legend, Line, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import { fmt } from '../datos/indices.js'

export default function GraficoDosis({ dias }) {
  const datos = dias.map((d) => ({ ...d, etiqueta: fmt.fecha(d.fecha) }))
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
          <Bar yAxisId="d" dataKey="dosis_sobrecarga" name="Dosis de sobrecarga" fill="var(--ambar)" radius={[3, 3, 0, 0]} maxBarSize={28} />
          <Line yAxisId="c" dataKey="cumplimiento" name="Cumplimiento" stroke="var(--petroleo)" strokeWidth={2.5} dot={false} />
        </ComposedChart>
      </ResponsiveContainer>
    </div>
  )
}
