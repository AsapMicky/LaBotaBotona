# Plan de avances

## Avance 1 — Contrato y maquetas
- [ ] Revisar y cerrar `protocolo-ble.md` entre los tres
- [ ] Discutir las decisiones 001–004 y llevarlas al profe
- [ ] Crear proyecto en Supabase y correr la migración
- [ ] Web del médico corriendo con datos simulados
- [ ] App del paciente corriendo en modo simulado

## Avance 2 — Apps con datos
- [ ] Web: login real de médico con Supabase
- [ ] Web: alta de paciente y apertura de episodio
- [ ] Web: reporte leyendo de Supabase
- [ ] App: pantalla de vinculación por QR
- [ ] App: resumen del día

## Avance 3 — Demo punta a punta sin plantilla
- [ ] ESP32 + potenciómetro con el protocolo BLE real
- [ ] App conectada al ESP32: semáforo y excedencias reales
- [ ] App sube resúmenes a Supabase (función `subir-datos`)
- [ ] Tests de dosimetría con perfiles sintéticos (escalón, oscilación en el umbral, reposo)
- [ ] Demo: girar el pote → semáforo ámbar → excedencia → aparece en la web

## Avance 4 — Hardware real
- [ ] Reemplazar `FuentePotenciometro` por lectura FSR + ADS1115 + ADG708
- [ ] Calibración por canal contra pesas patrón
- [ ] Seguimiento de línea de base (deriva del cero)
- [ ] Historial en LittleFS
