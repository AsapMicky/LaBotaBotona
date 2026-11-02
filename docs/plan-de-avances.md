# Plan de avances

## Avance 1 — Contrato y maquetas
- [ ] Revisar y cerrar `protocolo-ble.md` entre los tres
- [ ] Discutir las decisiones 001–004 y llevarlas al profe
- [x] Crear proyecto en Supabase y correr la migración
- [x] Web del médico corriendo con datos simulados
- [x] App del paciente corriendo en modo simulado

## Avance 2 — Apps con datos
- [x] Web: login real de médico con Supabase
- [x] Web: alta de paciente y apertura de episodio (con QR del `token_sync`)
- [x] Web: reporte leyendo de Supabase
- [x] App: pantalla de vinculación por QR
- [ ] App: resumen del día

## Avance 3 — Demo punta a punta sin plantilla
- [ ] ESP32 + potenciómetro con el protocolo BLE real
- [ ] App conectada al ESP32: semáforo y excedencias reales
- [ ] App sube resúmenes a Supabase (función `subir-datos`) — la app ya lo hace con cola local; falta el proyecto de Supabase
- [x] Tests de dosimetría con perfiles sintéticos (escalón, oscilación en el umbral, reposo)
- [ ] Demo: girar el pote → semáforo ámbar → excedencia → aparece en la web

## Avance 4 — Hardware real
Esto en buena parte **ya está hecho**, pero en `dosimetro_calibrado.ino`, fuera del repo
(ver `docs/avances/`). Lo que falta es unirlo con el protocolo BLE y la dosimetría de acá.
- [x] Lectura de 3 FSR por CD4051B + MCP6002 + ADC interno del ESP32 clásico
- [x] Calibración contra pesas patrón: tabla de mV a gramos (28/10)
- [x] Seguimiento de línea de base (deriva del cero), validado con perfiles sintéticos
- [x] Historial en LittleFS, 18 B/min, con descarga en CSV
- [ ] Reemplazar `FuentePotenciometro` por la lectura real, acá en `firmware/`
- [ ] Calibración global contra balanza: el factor de gramos a %PC
- [ ] Sumar los 5 FSR que faltan
