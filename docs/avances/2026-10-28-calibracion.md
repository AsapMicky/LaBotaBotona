# Calibración del dosímetro de carga plantar

28 de octubre de 2026

## Objetivo y alcance

La calibración convierte la lectura de cada FSR, en mV, en carga en gramos. Así el límite, la alarma y la dosis de sobrecarga del dosímetro quedan en unidades físicas en lugar de unidades del circuito.

Se calibró el FSR0 con su capa de EVA el 28/10/2026, con 9 cargas entre 0 y 2800 g. La tabla resultante se aplica a los tres FSR del prototipo y ya está cargada en el firmware.

- **Cubre:** la respuesta del conjunto sensor + electrónica a cargas estáticas crecientes, el umbral de detección y la saturación.
- **No cubre:** el pasaje a porcentaje de peso corporal (%PC). Requiere una calibración global con el sujeto parado sobre una balanza y queda pendiente.

## Cadena de medición calibrada

La calibración se hizo sobre la cadena completa, desde el FSR con su EVA hasta los mV que lee el firmware. El firmware usa el resultado, una tabla de mV a gramos, en cada lectura.

```
[ FSR 402 + EVA → CD4051B → MCP6002 (transimpedancia, Rf = 4,7 kΩ) → ADC interno del ESP32 → mV en el firmware ]
                                    (todo esto queda incluido en la curva)
                                                    ↓
                                   tabla mV → g + interpolación lineal
```

Todo lo que está dentro del recuadro queda incluido en la curva medida: no hace falta conocer por separado el Ron del multiplexor, la ganancia del amplificador ni el error del ADC.

## Criterio: una calibración de punta a punta y simplificada

Se eligió calibrar el sistema completo, de gramos a mV leídos por el firmware, con un solo sensor y una sola pasada en carga creciente. Es una calibración menos completa que una caracterización metrológica, pero es suficiente para el objetivo del dispositivo y se puede repetir en minutos.

**De punta a punta, no por partes.** El hardware del prototipo es el final: multiplexor CD4051B, amplificador MCP6002 y ADC interno del ESP32. Al calibrar la cadena entera quedan incluidos, sin medirlos por separado:

- la resistencia de encendido (Ron) del CD4051B, que queda en serie con el FSR y no es despreciable cuando el FSR baja a cientos de ohms con carga alta;
- las tolerancias de Rf (4,7 kΩ) y de la tensión de referencia del amplificador;
- la alinealidad del ADC del ESP32, que con atenuación de 11 dB tiene como rango recomendado 150 a 2450 mV (Espressif), mientras que la escala del prototipo llega a ~3000 mV.

La contrapartida es que la tabla vale solo para esta electrónica: si se cambia el multiplexor, Rf o el microcontrolador, hay que recalibrar.

**Un solo sensor para los tres.** Los tres FSR son del mismo modelo (Interlink FSR 402). El fabricante declara una variación entre unidades de ±6 % dentro de un mismo lote, menor que la histéresis del propio sensor (~10 %) (datasheet). Calibrar cada uno por separado mejoraría poco el resultado final.

**Tabla con interpolación, no un modelo ajustado.** La respuesta tiene cuatro zonas de forma distinta: umbral sin respuesta, subida empinada, aplanamiento y saturación. Una única función (lineal, potencia o logarítmica) ajustaría mal alguna de ellas. La tabla reproduce exactamente cada punto medido, es fácil de auditar y se actualiza cambiando números, sin tocar el algoritmo.

**Qué se resigna.** No se caracterizaron la histéresis (rama de descarga), el creep bajo carga sostenida, la repetibilidad entre pasadas ni el efecto de la temperatura. Se declaran como limitaciones y se proponen ensayos cortos para acotarlas.

## Método

Se aplicaron masas conocidas sobre el FSR0 montado con su capa de EVA y se registró la lectura en mV que entrega el firmware, desde 0 hasta la saturación.

**Montaje.** El FSR0 se colocó con la misma capa de EVA que va en la plantilla, porque la EVA es parte del transductor: reparte la carga y define cuánto llega al área activa. La carga se aplicó a través de una pieza rígida centrada sobre el área activa del sensor (círculo de ~13 mm en el FSR 402), con un recipiente encima donde se colocaron las masas.

**Masas.** Cada carga se pesó en una balanza de cocina antes de apoyarla. Las cargas fueron 100, 250, 500, 750, 1000, 1500, 2000, 2500 y 2800 g, más el cero sin carga. Como saturación se registró la lectura máxima alcanzada, 3007 mV.

**Lectura.** Se usó el firmware del prototipo, que en cada canal promedia 10 lecturas en una ventana de 20 ms: ese promedio sobre un período completo de la red cancela la interferencia de 50 Hz. Las lecturas se observaron en el Monitor Serie del Arduino IDE.

**Registro.** Con cada carga la lectura no quedó fija sino que se movió dentro de un rango, que se anotó (por ejemplo, 1500–1680 mV con 750 g). Como valor de calibración se tomó el punto medio de cada rango.

**Secuencia.** Una sola pasada por carga, sin repeticiones y sin un tiempo de espera estandarizado antes de leer.

## Resultados

La lectura sube de 268 mV en vacío a 3007 mV en saturación. La mayor sensibilidad está entre 250 y 1000 g, y por encima de 1500 g la lectura casi no cambia.

| Carga (g) | Lectura observada (mV) | Valor usado (mV) | Sobre el cero, ΔV (mV) | Sensibilidad del tramo (mV/g) | Dispersión en carga (g) |
|---|---|---|---|---|---|
| 0 | 268 | 268 | 0 | — | — |
| 100 | 269 | No usado | 1 | — | Sin respuesta |
| 250 | 430–450 | 440 | 172 | 0,69 | ±11 |
| 500 | 790–830 | 810 | 542 | 1,48 | ±10 |
| 750 | 1500–1680 | 1590 | 1322 | 3,12 | ±32 |
| 1000 | 2153–2280 | 2217 | 1949 | 2,51 | ±53 |
| 1500 | 2600–2610 | 2605 | 2337 | 0,78 | ±16 |
| 2000 | 2688–2720 | 2704 | 2436 | 0,20 | ±72 |
| 2500 | 2809–2850 | 2830 | 2562 | 0,25 | ±73 |
| 2800 | 2912–2940 | 2926 | 2658 | 0,32 | Satura |

La sensibilidad del tramo es el cambio de ΔV desde el punto anterior dividido por el cambio de carga. La dispersión es el rango de lectura de cada carga convertido a gramos con la propia tabla; probablemente refleja el creep del sensor mientras la carga estaba apoyada.

- **Hasta ~150 g:** sin respuesta. Es el umbral de activación del FSR.
- **250–1000 g:** la zona de mejor resolución, con 1,5 a 3,1 mV por gramo.
- **1000–1500 g:** transición, con 0,8 mV por gramo.
- **Más de 1500 g:** la curva se aplana (0,2–0,3 mV por gramo) hasta saturar. Estas lecturas están por encima de 2450 mV, fuera del rango recomendado del ADC, así que parte del aplanamiento puede venir del ADC y no solo del FSR.

## Implementación en el firmware

El firmware convierte cada canal a gramos con la tabla y una interpolación lineal entre puntos. Después suma los canales, y sobre esa suma calcula la alarma, el límite y la dosis.

1. Se resta el cero de cada canal en mV. El cero lo mantiene el seguidor de línea de base, que no cambió.
2. La diferencia ΔV se convierte a gramos con la tabla (ΔV en mV → g): 0 → 0, 172 → 250, 542 → 500, 1322 → 750, 1949 → 1000, 2337 → 1500, 2436 → 2000, 2562 → 2500, 2658 → 2800.
3. Entre dos puntos de la tabla, la carga se calcula sobre la recta que los une:

   $$m(\Delta V) = m_{i-1} + (\Delta V - V_{i-1})\,\frac{m_i - m_{i-1}}{V_i - V_{i-1}}, \qquad V_{i-1} < \Delta V \le V_i$$

4. Fuera de la tabla: si ΔV ≤ 0 la carga es 0, y si ΔV ≥ 2658 mV la carga queda fija en 2800 g (sensor saturado).
5. La carga total es la suma de los gramos de los tres FSR.

Algunos detalles de la implementación:

- **Primero el cero, después la conversión.** Como la curva no es lineal, restar el cero en gramos daría otro resultado. La tabla se construyó con lecturas sobre el cero, así que el orden es consistente con la calibración.
- **El punto de 100 g no está en la tabla.** Con 100 g la lectura no cambió (269 mV contra 268 mV en vacío): está por debajo del umbral de activación del FSR. Incluirlo haría que 1 mV de ruido se leyera como 100 g.
- **Unidades.** El límite (provisorio, 1000 g), el umbral de pie apoyado (150 g), el pico, la dosis (g·min), el gráfico y el registro en flash pasaron a gramos. Solo la pantalla SENSOR, que muestra la deriva del cero, sigue en mV.
- **Comprobación.** Se probó la función de conversión fuera del microcontrolador: cada punto de la tabla devuelve exactamente su carga, y las lecturas por encima de la saturación (3007 mV) devuelven 2800 g.

## Efecto de la temperatura

No se agregó compensación por temperatura. El efecto estimado dentro de la bota es de un par de por ciento, menor que los errores propios del FSR, y se propone un ensayo corto para medirlo en lugar de estimarlo.

**Por qué cambia la temperatura.** La plantilla arranca a temperatura ambiente y se calienta por el contacto con el pie. Caminar sube varios grados más la temperatura de la planta: en un estudio con plantillas, la temperatura de la piel plantar subió del orden de 4–5 °C sobre la de reposo (Hall et al., 2004). Estimamos un cambio total del orden de 10 °C para el sensor; no lo medimos.

**Qué afecta.** La temperatura puede mover dos cosas distintas:

- **El cero (la lectura sin carga).** Lo corrige el seguidor de línea de base, que recalcula el cero a partir de los mínimos de cada minuto, sea cual sea la causa de la deriva.
- **La sensibilidad (los mV que da una misma carga).** El seguidor no la corrige, porque solo actúa sobre el cero. Este es el efecto que queda sin compensar.

**Cuánto pesa.** El datasheet de Interlink informa cambios de resistencia, con 1 kg aplicado, del orden de 10–15 % tras una hora a −40 °C y a +85 °C (datasheet). Escalado a un cambio de ~10 °C, resulta del orden de 2 %. Es menor que la histéresis (~10 %), que la deriva bajo carga (hasta 5 % por década de tiempo) y que la dispersión observada en esta calibración (±1 a ±5 %).

**Por qué no un NTC.** Un sensor de temperatura no corrige nada por sí solo. Para compensar habría que calibrar el FSR a varias temperaturas y construir una corrección, que es la caracterización que esta calibración decidió no hacer. Además, el sensor de temperatura del DS3231 mide la placa, no la plantilla, así que tampoco sirve para esto. Si el ensayo propuesto mostrara un efecto mayor que la histéresis, la decisión se revisaría.

**Ensayo propuesto (15 min).** Con una carga fija de ~500 g:

1. Anotar los gramos que muestra el dosímetro con el FSR + EVA a temperatura ambiente.
2. Calentar el FSR + EVA a temperatura de pie (20–30 min dentro de la bota puesta, o contra la piel).
3. Repetir la medición con la misma carga.
4. Criterio: si la diferencia es menor que 5 %, el efecto queda por debajo de la histéresis y se acepta sin compensar.

## Otras fuentes de error

La fuente de error dominante es el propio FSR (histéresis y deriva bajo carga), no la electrónica ni la calibración. Los valores del fabricante son del datasheet de Interlink, medidos con 1 kg.

| Fuente | Magnitud | Cómo se trata |
|---|---|---|
| Histéresis (carga contra descarga) | ~10 % (fabricante) | No caracterizada: la tabla es solo de carga creciente |
| Deriva bajo carga sostenida (creep) | < 5 % por década de tiempo (fabricante); rangos de lectura de ±1 a ±5 % en esta calibración | El seguidor corrige el cero, no la sensibilidad; no caracterizada |
| Variación entre unidades | ±6 % en un mismo lote (fabricante) | Una sola tabla para los tres FSR; se propone medirla |
| Repetibilidad de un mismo sensor | ±2 % (fabricante) | No medida (una sola pasada) |
| Temperatura | ~2 % estimado para ~10 °C | Sin compensar; ensayo propuesto |
| Umbral de activación | Sin respuesta con 100 g | Cargas menores a ~150 g por sensor se leen como 0; el umbral de pie apoyado es 150 g |
| Resolución en la zona alta | 0,2–0,3 mV/g entre 1500 y 2800 g, contra 1,5–3,1 mV/g entre 250 y 1000 g | Zona útil declarada: 250–1500 g por sensor |
| Saturación | 3007 mV, por encima de ~2800 g por sensor | Se recorta a 2800 g |
| Posición y área de contacto | No cuantificada | Carga centrada con pieza rígida; en la bota, el pie carga sobre un área mayor |
| Ron del CD4051B y alinealidad del ADC | Incluidos en la curva | Absorbidos por la calibración de punta a punta; vale mientras no cambie el hardware |

Hay además un límite de representatividad: la suma de tres sensores no es la carga total sobre el pie, porque los FSR cubren una fracción de la planta. Los gramos del dosímetro son "gramos sobre los sensores". Para expresar la carga en %PC hace falta la calibración global contra balanza, pendiente.

## Verificación propuesta

Cinco ensayos cortos, de 10–15 minutos cada uno, convierten las limitaciones de la tabla anterior en números medidos. Para todos se usa el firmware ya calibrado, que muestra gramos.

- [ ] **Exactitud fuera de la tabla:** apoyar cargas que no se usaron para calibrar (~400, ~600 y ~1200 g) y comparar los gramos del dosímetro con los de la balanza. Da el error de interpolación.
- [ ] **Repetibilidad:** repetir la pasada completa sobre el FSR0 y comparar con la primera.
- [ ] **Variación entre unidades:** apoyar la misma carga (~500 g) sobre el FSR1 y el FSR2, con la misma EVA y la misma pieza rígida.
- [ ] **Histéresis:** cargar hasta 1000 g y bajar a 500 g, y comparar con la lectura de 500 g en subida.
- [ ] **Temperatura:** el ensayo de la sección anterior (500 g en frío y a temperatura de pie).

## Limitaciones y conclusiones

El dosímetro ya mide en gramos, con una calibración trazable a masas pesadas en balanza y con una zona útil de 250 a 1500 g por sensor. Dentro de esa zona, la dispersión de lectura observada equivale a ±10–53 g (±1 a ±5 %).

Limitaciones:

- Se calibró un solo sensor, en una sola pasada y solo en carga creciente.
- No se caracterizaron la histéresis, el creep, la repetibilidad ni la temperatura; sus magnitudes vienen del fabricante o son estimaciones.
- Por debajo de ~150 g el sensor no responde, y por encima de 1500 g la resolución cae a 0,2–0,3 mV/g.
- La carga está en gramos sobre los sensores, no en %PC.

La simplificación fue deliberada: una caracterización completa (electrónica por separado, cada sensor, ciclos de carga y descarga, varias temperaturas) excedía el alcance del proyecto. Los errores que se resignan son del mismo orden que los del propio FSR, y los ensayos de verificación propuestos permiten acotarlos sin rehacer la calibración.

## Fuentes

- Interlink Electronics, *FSR 400 Series Data Sheet*: histéresis, deriva, repetibilidad, variación entre unidades y ensayos de temperatura.
- Espressif, *ESP-IDF v4.4.1, Analog to Digital Converter*: rango recomendado del ADC del ESP32 con atenuación de 11 dB.
- Hall, Shurr, Zimmerman y Saltzman (2004), *Plantar Foot Surface Temperatures with Use of Insoles*, Iowa Orthopaedic Journal 24:72–75: aumento de la temperatura plantar al caminar con plantillas.
- Datos propios: calibración del FSR0, 28/10/2026.
