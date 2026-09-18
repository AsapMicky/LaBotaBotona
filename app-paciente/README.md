# App del paciente

Pantalla única pensada para alguien sin formación técnica: un semáforo, cuántas veces se pasó hoy y la batería.
Nunca muestra valores de carga (pedido de la cátedra).

- `lib/dispositivo/modelo.dart` — las clases del dato (estado, resumen, registro) y su `aJson()`; no saben de bytes.
- `lib/dispositivo/codec_ble.dart` — decodifica los paquetes de `docs/protocolo-ble.md`. `protocolo.dart` reexporta ambos.
- `lib/dispositivo/dispositivo_simulado.dart` — genera estados falsos para diseñar sin hardware.
- `lib/dispositivo/dispositivo_ble.dart` — conexión real con `flutter_blue_plus`.
- `lib/pantallas/inicio.dart` — la pantalla principal.
- `lib/vinculacion/vinculacion.dart` — el token del QR del médico, guardado en el teléfono (decisión 005). Sin cuenta.
- `lib/pantallas/escanear_qr.dart` y `lib/pantallas/vinculacion.dart` — escanear el código (o pegarlo a mano) y ver el estado.
- `lib/almacen/almacen.dart` — persistencia clave-valor abstraída (shared_preferences en el celular, memoria en tests).

Ver el README raíz y `docs/puesta-en-marcha-windows.md` para correrla.

## Pendiente
- Subida a Supabase (`subir-datos`) con cola local.
- Resumen semanal simple para el paciente.
