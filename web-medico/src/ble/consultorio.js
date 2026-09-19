// Conexión desde la computadora del consultorio con Web Bluetooth (Chrome / Edge).
// Protocolo: docs/protocolo-ble.md
//
// Es el camino "de mínima" de la decisión 001: aunque el paciente nunca haya instalado
// la app, el médico enchufa la ortesis en la consulta y se lleva todo lo que tenga guardado.
const base = (n) => `6f1a${n.toString(16).padStart(4, '0')}-8b3c-4d5e-9a10-2c7e5b3d9f00`
const SERVICIO = base(0)
const RESUMEN = base(2)
const CONTROL = base(3)
const HIST_DATOS = base(4)
const CONFIG = base(5)
const HORA = base(6)
const INFO = base(7)
const RESUMENES = base(8)

const OP_HISTORIAL = 1
const OP_RESUMENES = 3
export const SEQ_FIN = 0xffff
export const TAM_RESUMEN = 28
export const TAM_REGISTRO = 12

export const bluetoothDisponible = () => typeof navigator !== 'undefined' && !!navigator.bluetooth

/** Fecha local `AAAA-MM-DD` del inicio del día, igual que la calcula la app. */
function fechaLocal(epoch) {
  const d = new Date(epoch * 1000)
  const p = (n) => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`
}

/** Resumen diario de 28 B (0002 y los paquetes de 0008), listo para `subir-datos`. */
export function leerResumen(v, o = 0) {
  return {
    fecha: fechaLocal(v.getUint32(o, true)),
    dosis_sobrecarga: v.getFloat32(o + 4, true),
    dosis_subcarga: v.getFloat32(o + 8, true),
    t_carga_s: v.getUint32(o + 12, true),
    t_exceso_s: v.getUint32(o + 16, true),
    t_sub_s: v.getUint32(o + 20, true),
    pico: v.getUint16(o + 24, true) / 10,
    excedencias: v.getUint16(o + 26, true),
  }
}

/** Info de 32 B (0007): quién es el equipo y a qué tratamiento está asignado. */
export function leerInfo(v) {
  const txt = (o, n) => {
    const b = new Uint8Array(v.buffer, v.byteOffset + o, n)
    const fin = b.indexOf(0)
    return new TextDecoder().decode(fin === -1 ? b : b.subarray(0, fin))
  }
  return {
    protocolo: v.getUint8(0),
    firmware: `${v.getUint8(1)}.${v.getUint8(2)}.${v.getUint8(3)}`,
    serie: txt(4, 12),
    episodio: txt(16, 16),
  }
}

/** Configuración de 13 B (0005): lo que el equipo tiene cargado, más lo pendiente. */
export function leerConfig(v) {
  const x10 = (o) => v.getUint16(o, true) / 10
  return {
    limite_sup: x10(0),
    limite_inf: x10(2),
    peso_kg: x10(4),
    pendiente_sup: x10(6),
    pendiente_inf: x10(8),
    pendiente_peso_kg: x10(10),
    hay_pendiente: v.getUint8(12) !== 0,
  }
}

/** Registro por minuto de 12 B (paquetes de 0004). */
export function leerRegistro(v, o = 0) {
  return {
    ts: new Date(v.getUint32(o, true) * 1000).toISOString(),
    carga_media: v.getUint16(o + 4, true) / 10,
    carga_pico: v.getUint16(o + 6, true) / 10,
    dosis: v.getUint16(o + 8, true) / 100,
    excedencias: v.getUint8(o + 10),
    seg_apoyo: v.getUint8(o + 11) * 4,
  }
}

function pedido(op, desde) {
  const d = new DataView(new ArrayBuffer(5))
  d.setUint8(0, op)
  d.setUint32(1, Math.floor(desde.getTime() / 1000), true)
  return d
}

const conTiempo = (promesa, ms, mensaje) =>
  Promise.race([promesa, new Promise((_, rechazar) => setTimeout(() => rechazar(new Error(mensaje)), ms))])

export async function conectarOrtesis() {
  const equipo = await navigator.bluetooth.requestDevice({
    filters: [{ services: [SERVICIO] }],
  })
  const servidor = await equipo.gatt.connect()
  const servicio = await servidor.getPrimaryService(SERVICIO)
  const car = (uuid) => servicio.getCharacteristic(uuid)

  const hora = new DataView(new ArrayBuffer(6))
  const ahora = new Date()
  hora.setUint32(0, Math.floor(ahora.getTime() / 1000), true)
  hora.setInt16(4, -ahora.getTimezoneOffset(), true)
  await (await car(HORA)).writeValue(hora)

  /**
   * Descarga por notificaciones: se pide por 0003 y el equipo contesta en paquetes
   * numerados hasta mandar el de fin. Igual para minutos (0004) y resúmenes (0008).
   */
  async function descargar({ uuidDatos, op, desde, tamRegistro, leer, alAvanzar }) {
    const datos = await car(uuidDatos)
    const control = await car(CONTROL)
    const items = []
    let esperado = 0
    let terminar, fallar
    const fin = new Promise((res, rej) => { terminar = res; fallar = rej })

    const alLlegar = (ev) => {
      const v = ev.target.value
      if (v.byteLength < 2) return
      const seq = v.getUint16(0, true)
      if (seq === SEQ_FIN) return terminar()
      if (seq !== esperado) return fallar(new Error(`Se perdió el paquete ${esperado} de la descarga.`))
      esperado++
      const n = Math.floor((v.byteLength - 2) / tamRegistro)
      for (let i = 0; i < n; i++) items.push(leer(v, 2 + i * tamRegistro))
      alAvanzar?.(items.length)
    }

    datos.addEventListener('characteristicvaluechanged', alLlegar)
    await datos.startNotifications()
    try {
      await control.writeValue(pedido(op, desde))
      await conTiempo(fin, 90000, 'La ortesis dejó de responder durante la descarga.')
    } finally {
      datos.removeEventListener('characteristicvaluechanged', alLlegar)
      await datos.stopNotifications().catch(() => {})
    }
    return items
  }

  return {
    nombre: equipo.name,
    async leerInfo() {
      return leerInfo(await (await car(INFO)).readValue())
    },
    /** Asigna el episodio: se guardan los primeros 16 caracteres hex del UUID. */
    async escribirEpisodio(episodioId) {
      const id = episodioId ? episodioId.replace(/-/g, '').slice(0, 16) : ''
      const b = new Uint8Array(16)
      b.set(new TextEncoder().encode(id))
      await (await car(INFO)).writeValue(b)
    },
    /** Propone límites. Quedan pendientes hasta que se confirmen con el botón del equipo. */
    async proponerLimites({ limite_sup, limite_inf, peso_kg }) {
      const d = new DataView(new ArrayBuffer(6))
      d.setUint16(0, Math.round(limite_sup * 10), true)
      d.setUint16(2, Math.round((limite_inf || 0) * 10), true)
      d.setUint16(4, Math.round((peso_kg || 0) * 10), true)
      await (await car(CONFIG)).writeValue(d)
    },
    /** Los límites y el peso que el equipo tiene cargados ahora mismo. */
    async leerConfig() {
      return leerConfig(await (await car(CONFIG)).readValue())
    },
    /** El día en curso, que el equipo todavía está acumulando. */
    async leerResumenHoy() {
      return leerResumen(await (await car(RESUMEN)).readValue())
    },
    /** Los días ya cerrados que el equipo guardó al pasar cada medianoche. */
    descargarResumenes(desde = new Date(0), alAvanzar) {
      return descargar({
        uuidDatos: RESUMENES, op: OP_RESUMENES, desde,
        tamRegistro: TAM_RESUMEN, leer: leerResumen, alAvanzar,
      })
    },
    /** El perfil intradiario, minuto a minuto. */
    descargarHistorial(desde = new Date(0), alAvanzar) {
      return descargar({
        uuidDatos: HIST_DATOS, op: OP_HISTORIAL, desde,
        tamRegistro: TAM_REGISTRO, leer: leerRegistro, alAvanzar,
      })
    },
    desconectar: () => equipo.gatt.disconnect(),
  }
}
