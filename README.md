# Dosímetro de carga plantar — Grupo 6

Instrumentación Biomédica II · ITBA · 2026
Idan Mizrahi · Miguel Á. Obeid · Juan Ignacio Aldana

Plantilla instrumentada integrada a una ortesis de miembro inferior que mide la carga de apoyo,
avisa al paciente cuando excede el límite prescripto y acumula una **dosis de sobrecarga** que el
médico revisa entre consultas.

## Qué hay en el repo

| Carpeta | Qué es | Estado |
|---|---|---|
| `docs/` | Protocolo BLE (el contrato), modelo de datos, decisiones justificadas, plan de avances | listo para discutir |
| `firmware/` | ESP32 (PlatformIO). Hoy la carga sale de un **potenciómetro**; la lógica de dosis es la final | esqueleto funcional |
| `backend/` | Supabase: esquema SQL con permisos por médico, datos de prueba, función de subida | esqueleto |
| `app-paciente/` | Flutter. Semáforo, excedencias del día, batería. Modo simulado sin hardware | esqueleto |
| `web-medico/` | React + Vite. Lista de pacientes y reporte de adherencia. Funciona con datos simulados | funcional con mocks |
| `hardware/` | KiCad (a futuro) | vacío |

## Arranque rápido

**Web del médico (sin nada más instalado que Node 20):**
```bash
cd web-medico && npm install && npm run dev
```
Sin variables de entorno usa datos simulados. Con `VITE_SUPABASE_URL` y `VITE_SUPABASE_ANON_KEY` en `.env.local` usa Supabase.

**Tests de la lógica de dosis (sin placa):**
```bash
cd firmware && pio test -e native
```

**Firmware en un ESP32 con potenciómetro:**
```bash
cd firmware && pio run -e esp32s3 -t upload && pio device monitor
```
Potenciómetro de 10 kΩ entre 3,3 V y GND, cursor al pin indicado en `firmware/src/placa.h`.

**App del paciente:**
```bash
cd app-paciente
flutter create . --project-name dosimetro_paciente --platforms android,ios   # solo la primera vez
flutter pub get
flutter run                                  # modo simulado (default)
flutter run --dart-define=SIMULADO=false     # BLE real, necesita celular físico
```
Después del `flutter create`, agregar los permisos de Bluetooth del bloque de abajo en
`android/app/src/main/AndroidManifest.xml` (el emulador de Android **no** tiene Bluetooth).

```xml
<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
```

## Cómo trabajamos

1. Cada tarea es un issue (ver `docs/plan-de-avances.md` y `scripts/crear-issues.sh`).
2. Una rama por issue, PR a `main`, CI verde antes de mergear.
3. Con Claude Code: pedir primero un plan, revisarlo, después implementar. El contexto está en `CLAUDE.md`.
4. **Cualquier cambio al protocolo BLE** toca a la vez `docs/protocolo-ble.md`, `docs/protocolo-vectores.json`, `firmware/lib/protocolo`, `app-paciente/lib/dispositivo/codec_ble.dart` (y `modelo.dart` si cambia el dato) y sus tests.
