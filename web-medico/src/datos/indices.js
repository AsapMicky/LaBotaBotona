// Índices del Anexo A, calculados a partir de un resumen diario.
export function indices(r) {
  const tVentana = r.t_carga_s - r.t_exceso_s - r.t_sub_s
  const conApoyo = r.t_carga_s > 0
  return {
    ...r,
    t_ventana_s: tVentana,
    cumplimiento: conApoyo ? 100 * (1 - r.t_exceso_s / r.t_carga_s) : null,
    permanencia: conApoyo ? (100 * tVentana) / r.t_carga_s : null,
    frac_sub: conApoyo ? r.t_sub_s / r.t_carga_s : 0,
    frac_ventana: conApoyo ? tVentana / r.t_carga_s : 0,
    frac_exceso: conApoyo ? r.t_exceso_s / r.t_carga_s : 0,
    horas_uso: r.t_carga_s / 3600,
  }
}

const media = (xs) => (xs.length ? xs.reduce((a, b) => a + b, 0) / xs.length : null)

// Compara el cumplimiento de los últimos 7 días contra los 7 anteriores.
export function tendencia(resumenes) {
  const orden = [...resumenes].sort((a, b) => a.fecha.localeCompare(b.fecha)).map(indices)
  const c = (xs) => media(xs.map((x) => x.cumplimiento).filter((x) => x != null))
  const ultimos = c(orden.slice(-7))
  const previos = c(orden.slice(-14, -7))
  if (ultimos == null) return { ultimos: null, delta: null }
  return { ultimos, delta: previos == null ? null : ultimos - previos }
}

export const fmt = {
  pct: (v) => (v == null ? '—' : `${v.toFixed(1).replace('.', ',')} %`),
  num: (v, d = 0) => (v == null ? '—' : v.toFixed(d).replace('.', ',')),
  fecha: (iso) => new Date(iso + 'T12:00:00').toLocaleDateString('es-AR', { day: 'numeric', month: 'short' }),
  fechaLarga: (iso) =>
    iso ? new Date(iso + 'T12:00:00').toLocaleDateString('es-AR', { day: 'numeric', month: 'long', year: 'numeric' }) : '—',
  // Cuánto hace que pasó algo, en palabras. Pasada una semana la cuenta deja de decir
  // nada útil y conviene la fecha.
  hace: (iso) => {
    if (!iso) return '—'
    const ms = Date.now() - new Date(iso).getTime()
    if (Number.isNaN(ms)) return '—'
    const seg = Math.max(0, Math.floor(ms / 1000))
    if (seg < 60) return 'hace unos segundos'
    const min = Math.floor(seg / 60)
    if (min < 60) return `hace ${min} ${min === 1 ? 'minuto' : 'minutos'}`
    const hs = Math.floor(min / 60)
    if (hs < 24) return `hace ${hs} ${hs === 1 ? 'hora' : 'horas'}`
    const dias = Math.floor(hs / 24)
    if (dias < 8) return `hace ${dias} ${dias === 1 ? 'día' : 'días'}`
    return `el ${fmt.fechaLarga(iso.slice(0, 10))}`
  },
}

export function diasEntre(desdeIso, hastaIso) {
  const a = new Date(desdeIso + 'T12:00:00')
  const b = hastaIso ? new Date(hastaIso + 'T12:00:00') : new Date()
  return Math.max(0, Math.round((b - a) / 86400000))
}
