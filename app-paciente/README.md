# App del paciente

Pantalla única pensada para alguien sin formación técnica: un semáforo, cuántas veces se pasó hoy y la batería.
Nunca muestra valores de carga (pedido de la cátedra).

- `lib/dispositivo/protocolo.dart` — decodifica los paquetes de `docs/protocolo-ble.md`.
- `lib/dispositivo/dispositivo_simulado.dart` — genera estados falsos para diseñar sin hardware.
- `lib/dispositivo/dispositivo_ble.dart` — conexión real con `flutter_blue_plus`.
- `lib/pantallas/inicio.dart` — la pantalla.

Ver el README raíz para `flutter create` y los permisos de Android.

## Pendiente
- Vinculación por QR (token del episodio) y subida a Supabase (`subir-datos`).
- Resumen semanal simple para el paciente.
