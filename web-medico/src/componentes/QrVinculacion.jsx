import { useEffect, useState } from 'react'
import QRCode from 'qrcode'

/**
 * Lo que viaja en el QR. Dos cosas, y las dos hacen falta:
 *  - `t`: el token del episodio, que es la credencial con la que la app sube datos.
 *  - `e`: el identificador corto del episodio, el mismo que el médico le escribe a la
 *    ortesis por Bluetooth. Con eso la app puede verificar que la ortesis que está
 *    leyendo sea la de este tratamiento y no la de otro paciente.
 *
 * El nombre del paciente no va acá ni al equipo: vive solo en la base (decisión 002).
 */
export function cargaDelQr(episodio) {
  return JSON.stringify({
    t: episodio.token_sync,
    e: episodio.id.replace(/-/g, '').slice(0, 16),
  })
}

export default function QrVinculacion({ episodio, tamano = 220 }) {
  const [qr, setQr] = useState(null)
  const [error, setError] = useState(null)

  useEffect(() => {
    let vigente = true
    QRCode.toDataURL(cargaDelQr(episodio), { margin: 1, width: tamano })
      .then((url) => { if (vigente) setQr(url) })
      .catch((e) => { if (vigente) setError(e.message) })
    return () => { vigente = false }
  }, [episodio, tamano])

  if (error) return <p className="error">No se pudo generar el código: {error}</p>
  if (!qr) return <p className="nota">Generando el código…</p>
  return <img src={qr} alt="Código QR para vincular la app del paciente" width={tamano} height={tamano} />
}
