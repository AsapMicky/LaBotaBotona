# Contexto para Claude Code

## El proyecto
Dosímetro de carga plantar integrado a una ortesis de miembro inferior (Instrumentación Biomédica II, ITBA, Grupo 6).
Tras una cirugía de miembro inferior (fractura o reparación tendinosa) el paciente debe apoyar por debajo de un
límite de carga prescripto. El dispositivo mide la carga, avisa en el momento y acumula un indicador que el médico
revisa entre consultas. El foco de ingeniería es que el indicador sea **confiable** pese a las limitaciones del FSR
(histéresis, deriva del cero bajo carga sostenida, variabilidad entre unidades).

## Estado actual (actualizar cuando cambie)
- No hay electrónica armada. La carga se simula con un potenciómetro en un ESP32 devkit.
- Hardware previsto: 8×FSR 402 + NTC → ADG708 → OPA2333 (transimpedancia) → ADS1115 → ESP32-S3-WROOM-1-N16,
  RTC DS3231, OLED, LED RGB, buzzer, 2 pulsadores, LiPo 2000 mAh + TP4056 + AP2112K-3.3.

## Mapa del repo
- `docs/protocolo-ble.md` — **el contrato** entre firmware y apps. Es la fuente de verdad.
- `docs/modelo-datos.md`, `docs/decisiones/` — modelo y justificaciones (van al informe).
- `firmware/lib/dosimetria` — cálculo de dosis. C++ puro, sin Arduino, testeable en PC.
- `firmware/lib/protocolo` — serialización de los paquetes BLE.
- `firmware/src` — todo lo que depende del hardware.
- `backend/supabase` — esquema, permisos (RLS), datos de prueba, función de subida.
- `app-paciente` — Flutter. `lib/dispositivo/` abstrae simulado vs BLE real.
- `web-medico` — React + Vite. `src/datos/fuente.js` abstrae mocks vs Supabase.

## Comandos
- Firmware tests: `cd firmware && pio test -e native`
- Firmware build: `cd firmware && pio run -e esp32s3` (o `-e esp32dev` para NodeMCU)
- App: `cd app-paciente && flutter test` / `flutter run`
- Web: `cd web-medico && npm run dev` / `npm run build`

## Definiciones (Anexo A del anteproyecto)
C(t) = carga en %PC (porcentaje del peso corporal). L = límite superior, Lmin = límite inferior, Capoyo = 5 %PC.
- Dosis de sobrecarga: D = ∫ max(0, C − L) dt  [%PC·min]
- Dosis de subcarga: Dsub = ∫ max(0, Lmin − C) · 1[C > Capoyo] dt  [%PC·min]  (el reposo NO cuenta como déficit)
- Tcarga = t(C > Capoyo); Texceso = t(C > L); Tsub = t(Capoyo < C < Lmin); Tventana = t(Lmin ≤ C ≤ L)
- Cumplimiento = (1 − Texceso/Tcarga)·100 ; Permanencia en ventana = Tventana/Tcarga·100
- Excedencia: empieza cuando C cruza L hacia arriba; termina cuando C < 0,9·L por más de 2 s.

## Reglas
- Idioma: español rioplatense en UI, docs y nombres de dominio (`dosis`, `episodio`, `excedencia`).
- **El paciente nunca ve valores crudos ni %PC.** Solo semáforo, excedencias del día, batería.
- El exceso se muestra en ámbar/coral, no en rojo alarmante (pedido de la cátedra).
- **El dispositivo no guarda datos personales.** Solo el ID de episodio.
- Pacientes se identifican con ID interno (UUID + código legible), nunca con el DNI como clave.
- Las métricas se calculan en el microcontrolador; las apps solo las muestran.
- Un límite enviado por BLE queda *pendiente* hasta confirmarse con el pulsador del equipo.
- No se guarda señal cruda en la flash: agregados por minuto (ver `docs/decisiones/003`).
- Cambios al protocolo: actualizar doc + firmware + app + tests en el mismo PR.
- Antes de proponer un PR, correr los tests del módulo tocado.
