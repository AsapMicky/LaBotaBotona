// `fmt.hace` es lo que hace que la línea de sincronización se lea como algo vivo.
// Es una función pura, así que se testea sin navegador.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { fmt } from './indices.js'

const hace = (ms) => new Date(Date.now() - ms).toISOString()
const seg = 1000
const min = 60 * seg
const hora = 60 * min
const dia = 24 * hora

test('sin fecha no inventa nada', () => {
  assert.equal(fmt.hace(null), '—')
  assert.equal(fmt.hace(undefined), '—')
  assert.equal(fmt.hace('cualquier cosa'), '—')
})

test('lo recién pasado', () => {
  assert.equal(fmt.hace(hace(0)), 'hace unos segundos')
  assert.equal(fmt.hace(hace(45 * seg)), 'hace unos segundos')
})

test('minutos y horas, con el singular bien puesto', () => {
  assert.equal(fmt.hace(hace(1 * min)), 'hace 1 minuto')
  assert.equal(fmt.hace(hace(5 * min)), 'hace 5 minutos')
  assert.equal(fmt.hace(hace(1 * hora)), 'hace 1 hora')
  assert.equal(fmt.hace(hace(3 * hora)), 'hace 3 horas')
})

test('días', () => {
  assert.equal(fmt.hace(hace(1 * dia)), 'hace 1 día')
  assert.equal(fmt.hace(hace(3 * dia)), 'hace 3 días')
  assert.equal(fmt.hace(hace(7 * dia)), 'hace 7 días')
})

test('pasada la semana, la cuenta no dice nada: va la fecha', () => {
  const texto = fmt.hace(hace(30 * dia))
  assert.match(texto, /^el \d+ de \w+ de \d{4}$/)
})

test('una fecha futura no dice "hace menos uno"', () => {
  assert.equal(fmt.hace(new Date(Date.now() + 5 * min).toISOString()), 'hace unos segundos')
})
