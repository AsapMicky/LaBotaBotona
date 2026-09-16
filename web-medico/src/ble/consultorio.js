// Conexión desde la computadora del consultorio con Web Bluetooth (Chrome / Edge).
// Protocolo: docs/protocolo-ble.md
const base = (n) => `6f1a${n.toString(16).padStart(4, '0')}-8b3c-4d5e-9a10-2c7e5b3d9f00`
const SERVICIO = base(0)
const RESUMEN = base(2)
const CONFIG = base(5)
const HORA = base(6)
const INFO = base(7)

export const bluetoothDisponible = () => typeof navigator !== 'undefined' && !!navigator.bluetooth

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

  return {
    nombre: equipo.name,
    async leerInfo() {
      const v = await (await car(INFO)).readValue()
      const txt = (o, n) => new TextDecoder().decode(new Uint8Array(v.buffer, o, n)).replace(/\0+$/, '')
      return {
        protocolo: v.getUint8(0),
        firmware: `${v.getUint8(1)}.${v.getUint8(2)}.${v.getUint8(3)}`,
        serie: txt(4, 12),
        episodio: txt(16, 16),
      }
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
    async leerResumenHoy() {
      const v = await (await car(RESUMEN)).readValue()
      return {
        dosis_sobrecarga: v.getFloat32(4, true),
        dosis_subcarga: v.getFloat32(8, true),
        t_carga_s: v.getUint32(12, true),
        t_exceso_s: v.getUint32(16, true),
        t_sub_s: v.getUint32(20, true),
        pico: v.getUint16(24, true) / 10,
        excedencias: v.getUint16(26, true),
      }
    },
    desconectar: () => equipo.gatt.disconnect(),
  }
}
