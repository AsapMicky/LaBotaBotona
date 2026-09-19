# App del paciente

Pantalla única pensada para alguien sin formación técnica: un semáforo, cuántas veces se pasó hoy y la batería.
Nunca muestra valores de carga (pedido de la cátedra).

- `lib/dispositivo/modelo.dart` — las clases del dato (estado, resumen, registro) y su `aJson()`; no saben de bytes.
- `lib/dispositivo/codec_ble.dart` — decodifica los paquetes de `docs/protocolo-ble.md`. `protocolo.dart` reexporta ambos.
- `lib/dispositivo/dispositivo_simulado.dart` — genera estados falsos para diseñar sin hardware.
- `lib/dispositivo/dispositivo_ble.dart` — conexión real con `flutter_blue_plus`.
- `lib/pantallas/inicio.dart` — la pantalla principal.
- `lib/vinculacion/vinculacion.dart` — el token del QR del médico, guardado en el teléfono (decisión 005). Sin cuenta.
- `lib/pantallas/escanear_qr.dart` y `lib/pantallas/vinculacion.dart` — escanear el código (o pegarlo a mano), ver el estado y el envío.
- `lib/subida/` — `cola_subida.dart` (lo que bajó del equipo y falta subir, persistido), `cliente_subir_datos.dart`
  (POST a la función `subir-datos`) y `sincronizador.dart` (une equipo, cola y servidor: sube al conectar, al abrir,
  cada 15 min y a pedido, con reintentos). Solo conoce la interfaz `Dispositivo`.
- `lib/almacen/almacen.dart` — persistencia clave-valor abstraída (shared_preferences en el celular, memoria en tests).

## Cómo se sube

1. Cuando el equipo se conecta, lo primero es **verificar de quién es**: la app lee el episodio que tiene
   cargado la ortesis (0007) y lo compara con el que vino en el QR. Si es de otro tratamiento, no se toca
   nada y se avisa. La app se conecta a la ortesis que mejor se escucha, y en un consultorio esa puede no
   ser la del paciente.
2. Después le pide tres cosas y las encola en el teléfono: el resumen del día en curso, los resúmenes de
   los días ya cerrados que todavía no bajó, y los registros por minuto desde el último confirmado. Los
   días cerrados son los que tapan el hueco cuando el paciente pasa días sin abrir la app: el equipo los
   guarda solo, al pasar cada medianoche.
3. Si hay token y servidor, manda `{token, resumenes, registros}` a `subir-datos`. El servidor hace upsert por
   (episodio, fecha) y (episodio, minuto): reintentar nunca duplica.
4. Si falla (sin señal, servidor caído), reintenta con espera creciente (30 s … 15 min). Nada se borra hasta que
   el servidor confirma.
5. Si el servidor contesta que el episodio está cerrado, la app marca la vinculación como revocada y deja de insistir.

Sin `SUPABASE_URL` la app no sube nada y todo queda en el celular (sirve para diseñar). Para probar la subida sin
Supabase: `node scripts/subir-datos-falso.mjs` en la PC y correr la app con
`--dart-define=SUPABASE_URL=http://10.0.2.2:8787` (emulador) o la IP de la PC (celular en la misma red).

Para probar el backend real desde la PC, sin compilar para Android, con el mismo cliente que usa la app:

```bash
dart run tool/probar_subida.dart https://xxxx.supabase.co <token_del_QR>
```

Ver el README raíz y `docs/puesta-en-marcha-windows.md` para correrla.

## Pendiente
- Subida en segundo plano con la app cerrada (hoy sube con la app abierta).
- Resumen semanal simple para el paciente.
