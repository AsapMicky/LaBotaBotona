# Contexto para Claude Code

## El proyecto
Dosímetro de carga plantar integrado a una ortesis de miembro inferior (Instrumentación Biomédica II, ITBA, Grupo 6).
Tras una cirugía de miembro inferior (fractura o reparación tendinosa) el paciente debe apoyar por debajo de un
límite de carga prescripto. El dispositivo mide la carga, avisa en el momento y acumula un indicador que el médico
revisa entre consultas. El foco de ingeniería es que el indicador sea **confiable** pese a las limitaciones del FSR
(histéresis, deriva del cero bajo carga sostenida, variabilidad entre unidades).

## Estado actual (actualizar cuando cambie)

**Hay prototipo armado y calibrado.** Leer `docs/avances/` antes de tocar nada de hardware o firmware:
son los informes del equipo que lo armó y le ganan a cualquier otra cosa del repo.

- **La cadena del protoboard es la definitiva** (quedó fijada el 28/10/2026, porque la calibración está
  atada a esa electrónica exacta): 3 de 8 × FSR 402 con capa de EVA → **CD4051B** → **MCP6002**
  (transimpedancia, **Rf = 4,7 kΩ**) → **ADC interno del ESP32 clásico** (ESP-WROOM-32, GPIO34),
  DS3231, OLED SSD1306 con 2 botones, LED RGB (GPIO16/17/18), buzzer TMB12A05 (GPIO19).
- **No** son ADG708, OPA2333, ADS1115 ni ESP32-S3: eran el diseño original y quedaron atrás. El NTC se
  descartó, porque el seguidor de línea de base corrige el cero sea cual sea la causa.
- Flash: **4 MB**, de los que quedan ~1,5 MB para registro. No 16 MB.
- **El firmware que anda es `dosimetro_calibrado.ino` (Arduino IDE, 28/10) y todavía no está en este
  repo; cuando llegue va en `firmware/prototipo/`, tal cual, como referencia.**
  Lo que hay en `firmware/` es el esqueleto simulado con potenciómetro: la lógica de dosis y el
  protocolo BLE son los finales, la fuente de carga no.
- `hardware/` está vacía: el KiCad lo están terminando.

### Alimentación: sin regulador, con corrección ratiométrica
**No hay AP2112K ni ningún regulador.** La cátedra proveyó una LiPo 1S de 1000 mAh y los reguladores
disponibles no sirven con una celda de 3,2 a 4,2 V: un lineal necesita que la entrada supere su salida
por la tensión de caída, y ninguno lo cumple en ese rango. Así que el circuito se alimenta **directo de
la celda**, a través de un módulo TP4056 con protección, y el riel es la tensión de la batería.

La consecuencia es que **la medición pasa a depender de la batería**: la referencia de la transimpedancia
sale del riel con un divisor, pero el ADC convierte contra una referencia interna fija. Sin corregir,
una misma carga se lee hasta 27 % más alta con la celda recién cargada, y el equipo acusaría de
sobrecarga a un paciente que se cuidó.

Se corrige por software, sin agregar componentes: `V_corr = V_med · V_CAL / V_riel`, midiendo el riel
con el mismo ADC (GPIO35, divisor R17/R18) una vez por segundo. Como las dos lecturas pasan por el mismo
conversor, el error de ganancia de su referencia se cancela en el cociente. Las constantes están en
`placa.h`; `V_CAL_MV` se obtiene con el comando `v` del monitor serie, por USB y sin batería.

Dos cosas que se siguen de esto y conviene no romper:
- **La saturación se evalúa sobre el valor crudo** (`SAT_MV`), nunca sobre el corregido: el techo del
  ADC no se mueve con el riel.
- **Los umbrales de batería son relativos a `V_CAL_MV`**, para que alimentar por USB no dispare el aviso.

Limitación conocida: con la celda por encima de 3,6 V el ESP32 queda fuera de la tensión que especifica
Espressif. Funciona, pero sin garantía del fabricante. Un LDO de caída muy baja (MCP1700-3.3, HT7333)
lo resolvería manteniendo la corrección.

### Unidades: el equipo mide gramos, el contrato sigue en %PC
El dispositivo convierte cada canal a **gramos** con una tabla de mV a gramos (calibración del 28/10).
El protocolo BLE, la base de datos y la web siguen en **%PC**, que es el destino definido en el Anexo A.
El puente entre los dos es la **calibración global contra balanza, que todavía no se hizo**: hasta que
exista, los gramos del equipo son "gramos sobre los sensores", no la carga total sobre el pie.

No cambiar las unidades del protocolo ni del esquema por esto. Lo que falta es el factor, no el modelo.

## Mapa del repo
- `docs/protocolo-ble.md` — **el contrato** entre firmware y apps. Es la fuente de verdad.
- `docs/protocolo-vectores.json` — paquetes de ejemplo en hexa; los leen los tests de C++, de Dart y de JS.
- `docs/firmware-placa-real.md` — **briefing para escribir el firmware de la placa.** Leerlo antes de
  tocar `firmware/` para el hardware real: explica las decisiones tomadas y lo que falta.
- `docs/avances/` — **informes del hardware real.** La fuente de verdad sobre el prototipo: qué se armó,
  qué se decidió y la calibración. Leerlos antes de tocar `firmware/` o `hardware/`.
- `docs/modelo-datos.md`, `docs/decisiones/` — modelo y justificaciones (van al informe).
- `firmware/lib/dosimetria` — cálculo de dosis. C++ puro, sin Arduino, testeable en PC.
- `firmware/lib/protocolo` — serialización de los paquetes BLE.
- `firmware/src` — todo lo que depende del hardware.
- `backend/supabase` — esquema, permisos (RLS), datos de prueba, función de subida.
- `app-paciente` — Flutter. `lib/dispositivo/` abstrae simulado vs BLE real; `modelo.dart` es el dato,
  `codec_ble.dart` los bytes (decisión 005). `lib/vinculacion/` el token del QR; `lib/subida/` la cola local
  y la subida a `subir-datos` (nunca lee de Supabase).
- `web-medico` — React + Vite. `src/datos/fuente.js` abstrae mocks vs Supabase.

## Comandos
- Firmware tests: `cd firmware && pio test -e native`
- Firmware build: `cd firmware && pio run -e esp32dev` (el ESP32 clásico del prototipo; `-e esp32s3`
  solo si la placa final cambia)
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
- Cambios al protocolo: actualizar doc + `docs/protocolo-vectores.json` + `firmware/lib/protocolo` +
  `app-paciente/lib/dispositivo/codec_ble.dart` + tests en el mismo PR.
- Toda migración que cree una tabla en `public` incluye sus propios `grant` (ver `0007`). Supabase dejó
  de otorgarlos solo el 30/10/2026. `anon` no recibe permisos sobre ninguna tabla: el médico entra con
  cuenta y la app escribe por `subir-datos`.
- Antes de proponer un PR, correr los tests del módulo tocado.
