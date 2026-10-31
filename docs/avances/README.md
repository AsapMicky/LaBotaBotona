# Avances del hardware

Informes escritos por el equipo que armó y validó el prototipo en protoboard. Son la fuente de verdad
sobre el hardware real: lo que está acá le gana a cualquier otra cosa del repo que diga lo contrario.

| Informe | Fecha | Qué cubre |
|---|---|---|
| [2026-10-22-informe-de-avances.md](2026-10-22-informe-de-avances.md) | 22/10/2026 | La historia completa, de la elección del proyecto al prototipo funcionando. Hardware, firmware, errores y lecciones |
| [2026-10-28-calibracion.md](2026-10-28-calibracion.md) | 28/10/2026 | Calibración del FSR0 con EVA: método, tabla de mV a gramos, fuentes de error y ensayos propuestos |

**El del 28/10 manda sobre el del 22/10** donde se contradigan. El informe del 22/10 deja varios bloques
"por decidir" (multiplexor, ADC, Rf, microcontrolador); el 28/10 los cierra: la cadena del protoboard es
la definitiva, porque la calibración quedó atada a esa electrónica exacta.

## Lo que quedó definido el 28/10

| Bloque | Definitivo |
|---|---|
| Microcontrolador | ESP32 clásico (ESP-WROOM-32, DevKit de 38 pines), 4 MB de flash |
| Multiplexor | CD4051B |
| Amplificador | MCP6002, transimpedancia con Rf = 4,7 kΩ |
| ADC | Interno del ESP32, por GPIO34 |
| Unidades | Gramos, con tabla de mV a gramos e interpolación lineal |

Cambiar cualquiera de esos cuatro bloques obliga a recalibrar: la tabla incluye el Ron del multiplexor,
las tolerancias de Rf y la alinealidad del ADC, todo junto.

## Lo que sigue pendiente

- **El pasaje de gramos a %PC.** Necesita la calibración global con el sujeto parado sobre una balanza.
  Hasta que exista, el equipo mide "gramos sobre los sensores", que no es la carga total sobre el pie.
- Los cinco FSR restantes: hoy son 3 de 8.
- Histéresis, creep, repetibilidad y temperatura: declaradas como limitaciones, con ensayos cortos
  propuestos en el informe del 28/10.
