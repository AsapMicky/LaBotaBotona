# 003 · Qué se guarda en la flash

**Estado:** propuesta · **Actualizada:** 31/10/2026 con el hardware real (ver `docs/avances/`)

No se guarda señal cruda. Se guardan agregados por minuto, y el resumen del día.

| Qué | Cálculo | Por día |
|---|---|---|
| Señal cruda | 8 canales × 2 B × 50 Hz = 800 B/s | ≈ 69 MB — **no entra** en ningún lado |
| Agregados por minuto | 18 B × 1440 min | ≈ 26 KB |
| Resumen diario | 28 B | 28 B |

El indicador (dosis) se integra a 50 Hz en el microcontrolador; lo que se guarda es el resultado, no la
señal. La señal cruda solo se transmite en un modo de calibración de banco (a definir).

## Cuánto dura el registro

El diseño original suponía el ESP32-S3-WROOM-1-N16, con 16 MB de flash, y calculaba 13 B/min: de ahí
salía "10 MB alcanzan para más de 1,5 años".

**El hardware real es otro.** El prototipo usa un ESP32 clásico con **4 MB de flash**, y el registro
quedó en **18 B/min** porque guarda más campos que los previstos (hora, límite, pico, tiempo apoyado y
en exceso, dosis, excedencias y señales de estado).

| | Diseño original | Hardware real |
|---|---|---|
| Flash total | 16 MB | 4 MB |
| Disponible para registro | ~10 MB | ~1,5 MB (esquema por defecto) o ~1,9 MB (partición propia) |
| Registro por minuto | 13 B | 18 B |
| Autonomía | ~1,5 años | **~58 días** |

Cincuenta y ocho días alcanzan para un tratamiento, que es el horizonte real del equipo: el paciente
lo usa unas semanas y el médico lo descarga en cada consulta. Pero ya no hay margen para olvidarse de
descargar durante meses, así que conviene decirlo en el informe en vez de repetir el número viejo.

## Qué no cambia

- **Los 18 B/min son el formato en flash.** El registro por minuto del protocolo BLE (`0004`) son 12 B
  y lleva otros campos: es lo que viaja al teléfono, no lo que se guarda. No tienen por qué coincidir.
- Se escribe cada 10 minutos para cuidar la flash. Ante un corte se pierden como máximo 10 minutos, y
  al encender el equipo recupera los indicadores del día.
- 1440 escrituras por día son unas 4 escrituras de bloque con wear leveling. Frente a los 100.000
  ciclos de borrado del chip, no es un problema.
