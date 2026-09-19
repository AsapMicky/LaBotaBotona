// La web es el tercer cliente del protocolo, además del firmware y la app: cuando el
// médico descarga la ortesis en la consulta, decodifica los mismos bytes. Este test la
// ata a docs/protocolo-vectores.json, igual que hacen los otros dos.
//
//   npm test        (usa el runner que ya trae Node, sin dependencias)
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { leerResumen, leerRegistro, leerInfo, leerConfig, SEQ_FIN, TAM_RESUMEN, TAM_REGISTRO } from './consultorio.js'

const vec = JSON.parse(readFileSync(new URL('../../../docs/protocolo-vectores.json', import.meta.url), 'utf8'))

const vista = (hexa) => {
  const b = Uint8Array.from(hexa.trim().split(/\s+/), (x) => parseInt(x, 16))
  return new DataView(b.buffer)
}
const cerca = (a, b, nombre) =>
  assert.ok(Math.abs(a - b) <= Math.abs(b) * 1e-6 + 1e-6, `${nombre}: ${a} != ${b}`)

/** Fecha local del inicio del día, calculada aparte para no depender del huso horario. */
const fechaDe = (epoch) => {
  const d = new Date(epoch * 1000)
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}

function compararResumen(r, esp) {
  assert.equal(r.fecha, fechaDe(esp.inicio_dia))
  cerca(r.dosis_sobrecarga, esp.dosis_sobrecarga, 'dosis_sobrecarga')
  cerca(r.dosis_subcarga, esp.dosis_subcarga, 'dosis_subcarga')
  assert.equal(r.t_carga_s, esp.t_carga_s)
  assert.equal(r.t_exceso_s, esp.t_exceso_s)
  assert.equal(r.t_sub_s, esp.t_sub_s)
  cerca(r.pico, esp.pico, 'pico')
  assert.equal(r.excedencias, esp.excedencias)
}

function compararRegistro(r, esp) {
  assert.equal(r.ts, new Date(esp.ts * 1000).toISOString())
  cerca(r.carga_media, esp.carga_media, 'carga_media')
  cerca(r.carga_pico, esp.carga_pico, 'carga_pico')
  cerca(r.dosis, esp.dosis, 'dosis')
  assert.equal(r.excedencias, esp.excedencias)
  assert.equal(r.seg_apoyo, esp.seg_apoyo)
}

test('versión del protocolo', () => {
  assert.equal(vec.version_protocolo, 1)
})

for (const v of vec.resumen) {
  test(`resumen del día: ${v.nombre}`, () => {
    const d = vista(v.bytes)
    assert.equal(d.byteLength, TAM_RESUMEN)
    compararResumen(leerResumen(d), v.esperado)
  })
}

for (const v of vec.registro) {
  test(`registro por minuto: ${v.nombre}`, () => {
    const d = vista(v.bytes)
    assert.equal(d.byteLength, TAM_REGISTRO)
    compararRegistro(leerRegistro(d, 0), v.esperado)
  })
}

for (const v of vec.info) {
  test(`info del equipo: ${v.nombre}`, () => {
    const i = leerInfo(vista(v.bytes))
    assert.equal(i.protocolo, v.esperado.protocolo)
    assert.equal(i.firmware, v.esperado.firmware)
    assert.equal(i.serie, v.esperado.serie)
    assert.equal(i.episodio, v.esperado.episodio)
  })
}

for (const v of vec.config) {
  test(`configuración del equipo: ${v.nombre}`, () => {
    const c = leerConfig(vista(v.bytes))
    cerca(c.limite_sup, v.esperado.limite_sup, 'limite_sup')
    cerca(c.limite_inf, v.esperado.limite_inf, 'limite_inf')
    cerca(c.peso_kg, v.esperado.peso_kg, 'peso_kg')
    cerca(c.pendiente_sup, v.esperado.pendiente_sup, 'pendiente_sup')
    cerca(c.pendiente_inf, v.esperado.pendiente_inf, 'pendiente_inf')
    cerca(c.pendiente_peso_kg, v.esperado.pendiente_peso_kg, 'pendiente_peso_kg')
    assert.equal(c.hay_pendiente, v.esperado.hay_pendiente)
  })
}

const porNombre = (lista) => Object.fromEntries(lista.map((x) => [x.nombre, x.esperado]))

for (const v of vec.paquete_resumenes) {
  test(`paquete de resúmenes: ${v.nombre}`, () => {
    const d = vista(v.bytes)
    const seq = d.getUint16(0, true)
    assert.equal(seq, v.esperado.secuencia)
    const n = Math.floor((d.byteLength - 2) / TAM_RESUMEN)
    assert.equal(n, v.esperado.cantidad)
    if (seq === SEQ_FIN) assert.equal(n, 0)
    const esperados = porNombre(vec.resumen)
    for (let i = 0; i < n; i++) {
      compararResumen(leerResumen(d, 2 + i * TAM_RESUMEN), esperados[v.esperado.resumenes[i]])
    }
  })
}

for (const v of vec.paquete_historial) {
  test(`paquete de historial: ${v.nombre}`, () => {
    const d = vista(v.bytes)
    const seq = d.getUint16(0, true)
    assert.equal(seq, v.esperado.secuencia)
    const n = Math.floor((d.byteLength - 2) / TAM_REGISTRO)
    assert.equal(n, v.esperado.cantidad)
    if (seq === SEQ_FIN) assert.equal(n, 0)
    const esperados = porNombre(vec.registro)
    for (let i = 0; i < n; i++) {
      compararRegistro(leerRegistro(d, 2 + i * TAM_REGISTRO), esperados[v.esperado.registros[i]])
    }
  })
}
