# Informe de avances — Dosímetro de carga plantar para ortesis

Instrumentación Biomédica II · 22 de octubre de 2026

## Resumen

Al 22 de octubre de 2026 el prototipo en protoboard mide con 3 FSR, da alarma por sobrecarga, calcula la dosis y el cumplimiento, corrige la deriva del cero, guarda un registro por minuto con fecha y hora y lo muestra en pantalla. Falta calibrar (todo se expresa todavía en mV, no en % del peso corporal) y correr los ensayos de validación.

Este informe reconstruye en orden cronológico cómo llegamos hasta acá: qué hicimos en cada etapa, qué decidimos, por qué, y los errores que cometimos en el camino.

| Fecha (2026) | Etapa | Resultado |
|---|---|---|
| 17 ago | Selección del proyecto | Matriz de 4 ideas; elegimos la ortesis aunque quedó 3.ª |
| 19 ago | Definición | Dosímetro de carga: primero el indicador, sin análisis de marcha |
| 20 ago | Estudio y anteproyecto | Guía de la electrónica y anteproyecto en formato de cátedra |
| 25 sep | Revisión de la cátedra | Se mantiene el multiplexor, se saca el ADC externo, esquemático en KiCad |
| 30 sep – 8 oct | Preparación | Listas de componentes y plan de armado por fases |
| 8 oct | Primer armado | Placa quemada, cable sin datos, aliasing de 50 Hz, op-amp equivocado |
| 9 – 11 oct | Cadena validada | MCP6002, Rf de 4,7 kΩ, 50 lecturas por segundo por canal |
| 11 oct | Firmware del dosímetro | Alarma, indicadores y seguidor de línea de base |
| 16 oct | Periféricos | Reloj, registro en flash, pantalla y botones |
| 20 – 22 oct | Cátedra y calibración | Consulta de un docente y preparación de la calibración |

## Etapa 1 — Selección del proyecto (17 de agosto)

Elegimos la ortesis con monitoreo de carga (idea 8) aunque la matriz de decisión la ubicó tercera. El primer puesto fue el monitor de diuresis.

**Punto de partida.** Un cuatrimestre (16 semanas), presupuesto flexible de unos USD 300–400, acceso a impresión 3D, laboratorio con instrumental y fabricación de PCB. No teníamos contacto clínico confirmado, y eso pesó en toda la evaluación.

**Cómo comparamos.** Armamos una matriz con cinco criterios ponderados: contenido de instrumentación (25 %), relevancia clínica (20 %), factibilidad (20 %), validabilidad sin pacientes (20 %) y novedad (15 %). Evaluamos las cuatro ideas que habíamos enviado; las ideas 3 a 6 no entraron en la comparación.

| Idea | Puntaje | Posición |
|---|---|---|
| 7 — Monitor de diuresis | 4,65 | 1.° |
| 2 — Detector UV portátil | 3,90 | 2.° |
| 8 — Ortesis con monitoreo de carga | 3,65 | 3.° (elegida) |
| 1 — Bastón inteligente | 2,60 | 4.° |

El ranking resultó robusto: aun quitando el criterio de validabilidad sin pacientes, la diuresis seguía primera (4,56 contra 3,63 del UV y 3,56 de la ortesis).

**Hallazgos técnicos de la evaluación.** Al revisar hojas de datos y literatura encontramos problemas concretos en casi todas las ideas:

- El sensor UV VEML6075 (idea 2) está discontinuado desde 2019 y no tiene reemplazo directo; la alternativa era el AS7331.
- El IMU MPU6050 está fuera de producción y no se recomienda para diseños nuevos.
- El sensor de distancia VL53L1X (idea 1) cae de 400 cm a unos 73 cm bajo luz ambiente fuerte, así que un bastón de exterior no podía depender solo de él.
- El caudalímetro de turbina de la idea 7 no sirve: su caudal mínimo es unas 800 veces mayor que una diuresis real.
- El FSR de la idea 8 es un mal instrumento cuantitativo: histéresis del 10–30 %, deriva bajo carga sostenida y dependencia del área de contacto.

**Por qué la ortesis.** La adoptamos por preferencia de trabajar en biomecánica antes que en la cadena puramente analógica que exigía la diuresis, y con la condición de buscar contacto con un kinesiólogo o traumatólogo. Ese contacto sigue pendiente. La debilidad del FSR quedó identificada desde el primer día como el problema técnico central del proyecto.

## Etapa 2 — Definición del dosímetro (19 de agosto)

Definimos el proyecto como un dosímetro de carga plantar: mide cuánta carga soportó el pie de un paciente con fractura, avisa si se pasa del límite prescripto y le da al profesional un indicador objetivo de cuánto se cuidó entre consultas.

**Primer tropiezo: el proyecto se nos fue de alcance.** Las primeras versiones del documento incluían análisis de marcha, IMU, fases del paso, cadencia y centro de presión. Las descartamos porque distorsionaban la intención: nada de eso aporta a saber cuánta carga recibió el hueso. Rehicimos el documento acotado (23 páginas) y quedó escrito como regla: el dispositivo no analiza la marcha.

**El concepto.** Igual que un dosímetro de radiación acumula la dosis recibida sin saber qué hacía la persona, este acumula la carga mecánica sobre un hueso en consolidación. Los 8 sensores se justifican solo por cobertura de la planta, porque la carga no se reparte uniforme y se desplaza.

El indicador se diseñó primero y de él salieron los requisitos. El número principal es la dosis de sobrecarga, con C(t) la carga en % del peso corporal (PC) y L el límite prescripto:

$$D = \int \max\big(0,\; C(t) - L\big)\, dt \quad [\%PC \cdot min]$$

Se reporta junto con la carga pico del día, el tiempo de carga (C > 5 % PC), el tiempo en exceso (C > L), las excedencias y un índice de cumplimiento. Tomamos tres decisiones de criterio:

- **Dosis lineal.** No la ponderamos con un exponente porque no hay evidencia clínica para elegirlo; el pico se informa por separado.
- **Cumplimiento normalizado por el tiempo cargado**, (1 − T_exceso / T_carga) × 100. Normalizado por el día entero, un paciente que pasó el día sentado daría 99,9 %.
- **Excedencias con histéresis:** el evento arranca al cruzar L y cierra al bajar de 0,9·L por más de 2 s.

**El problema técnico central: la deriva del cero.** El FSR deriva bajo carga sostenida, y como el indicador es una integral, la deriva no se promedia: se acumula. Con un cero corrido 5 %, un paciente que apoyó al 18 % con límite de 20 % aparecería en 23 % y sumaría dosis todo el día. El reporte acusaría a quien se cuidó.

La solución fue un seguidor de línea de base que no necesita detectar fases de la marcha. Cada minuto guarda el mínimo de cada canal y conserva los últimos 15. Si los 3 valores más bajos concuerdan entre sí (dispersión menor al 2 % del fondo de escala), ese es el cero, y el offset se actualiza como 0,2·candidato + 0,8·offset. Elegimos un criterio de concordancia y no un umbral absoluto para evitar una dependencia circular: para saber si una lectura es cero habría que conocer el cero. Cuesta 240 bytes de RAM. Si no hay concordancia en 30 minutos, avisa en pantalla y queda la tara manual como respaldo.

**Decisiones de hardware.** Partimos de nueve especificaciones: 8 FSR 402, multiplexor ADG708 con amplificador de transimpedancia OPA2333, ADC ADS1115, sin IMU, solo buzzer, LED RGB, OLED con 4 pantallas y 2 botones, flash interna del ESP32-S3-WROOM-1-N16, reloj DS3231 con pila y un único regulador de 3,3 V (AP2112K). Los datos que más condicionaron el diseño:

| Dato | Consecuencia en el diseño |
|---|---|
| El FSR 402 mide 0,1–10 N (≈ 1 kgf), no 10 kg | Satura sobre ~60 % PC; el rango clínico (10–50 % PC) entra. Se declara como especificación |
| La capa de EVA es parte del transductor | Nunca se calibra el FSR desnudo |
| El Ron del multiplexor queda en serie con el FSR | ADG708 (8 Ω, error 0,47 %) en lugar del CD74HC4051 (~70 Ω, error 4–8 %) |
| Transimpedancia con Vref = 0,25 V y Rf = 15 kΩ | Salida de 0,25 a 2,45 V, proporcional a la conductancia del FSR |
| Repetibilidad del FSR ±2 % | El sensor es el cuello de botella, no el ADC |
| A 10 Hz el pico se subestima 10–15 % | 50 Hz por canal; lo fija el pico, no la dosis |
| Señal de 0,25–2,45 V | Un solo riel alcanza: 5 mV de rizado son 0,23 % del fondo de escala |
| Registro de 13 B/min = 19 kB/día | 4 MB alcanzan para 224 días |
| Consumo de 39 mA sin BLE y 110 mA con BLE | 2000 mAh dan 30–36 h reales |

Costo estimado: USD 305–425 (305–335 sin la bota).

**Calibración en dos niveles.** Primero por canal, con la capa de EVA, por la variabilidad de ±6 % entre unidades. Después global por sujeto contra una balanza, porque 8 sensores cubren solo el 8,5 % de la planta y su suma no es la carga total: un factor k por mínimos cuadrados.

**Ensayos centrales previstos.** V4 valida el seguidor de línea de base (3 h alternando apoyo y reposo, objetivo ±2 % PC). V5 valida la exactitud de la dosis contra un perfil de carga conocido: valida el indicador, no solo el sensor. V9 verifica que el dispositivo funcione una jornada completa sin el teléfono.

## Etapa 3 — Estudio de la electrónica y anteproyecto (20 de agosto)

Antes de documentar nos aseguramos de entender cada componente del sistema y su motivo, y después redactamos el anteproyecto con el formato de la cátedra.

**Recorrido por la electrónica.** Fuimos de lo general a lo particular: primero la cadena de señal completa, después el rol de cada bloque y por último el cableado pin a pin. Los conceptos que más nos costaron y que quedaron claros:

- **Por qué transimpedancia y no un divisor resistivo.** El divisor del tutorial típico es doblemente no lineal. En la transimpedancia se fija la tensión sobre el FSR y se mide la corriente, que es casi proporcional a la fuerza.
- **Las dos mitades del op-amp.** La mitad B es un buffer que copia la referencia de 0,25 V sin cargarla; la mitad A es la transimpedancia que usa esa referencia.
- **Por qué un op-amp de deriva cero.** La señal en reposo es chica (250 mV), y cualquier deriva térmica contaminaría justo el cero, que es lo más delicado del indicador.
- **El bus I²C** lleva dos cables compartidos y un solo par de resistencias de pull-up para todo el bus, no un par por chip.
- **La cadena de alimentación:** USB → TP4056 (carga y protección de la LiPo) → AP2112K → riel único de 3,3 V.

Quedaron fijados los valores de partida: divisor de 12,2 kΩ y 1 kΩ para Vref = 0,25 V, Rf = 15 kΩ, divisor de batería de 100 kΩ + 100 kΩ al 1 %, 10 kΩ fija para el divisor del NTC, filtro de 10 Ω + 22 µF en la alimentación analógica y pull-ups de 4,7 kΩ en I²C. Con todo eso armamos un documento de referencia de cableado.

**Tropiezo con el anteproyecto.** La primera versión salió como un documento técnico de referencia, centrado en la electrónica y los circuitos. No era lo que pedía la cátedra, así que lo rehicimos con la estructura clásica de anteproyecto: introducción, estado del arte, marco teórico, objetivos (general, de máxima y de mínima), lista tentativa de materiales, bibliografía y anexo.

Para el estado del arte y el marco teórico usamos referencias verificadas: Anderson et al. (2023), Braun et al. (2017), Merkle et al. (2025), Schofield et al. (2016), Paredes-Madrid et al. (2018), Ma et al. (2023), Glatt et al. (2017) y Castellarin et al. (2022). Después empezamos una presentación para acompañar el anteproyecto.

## Etapa 4 — Revisión de la cátedra y esquemático en KiCad (25 de septiembre)

Los profesores observaron que el multiplexor no hacía falta porque el ESP32 tiene pines suficientes. Mantuvimos el multiplexor, pero ese mismo día sacamos el ADC externo y pasamos a usar el ADC interno del microcontrolador.

**Por qué mantuvimos el multiplexor.** En pines tenían razón: el ADC1 del ESP32-S3 tiene 10 canales y entran los 8 FSR. Pero el multiplexor no estaba por falta de pines, sino para que los 8 canales compartan una sola cadena de acondicionamiento, con la misma ganancia, el mismo offset y la misma deriva térmica. Sin multiplexor había dos caminos, y ninguno nos convenció:

| Alternativa sin multiplexor | Ventaja | Costo |
|---|---|---|
| A. Divisor resistivo por canal, directo al ADC | Lo más simple y barato | Salida no lineal con la fuerza y error del ADC comparable al ±2 % del FSR, que se acumula en la integral |
| B. Ocho transimpedancias en paralelo | Mantiene la calidad | Entre dos y cuatro veces más componentes, área y consumo; 8 offsets distintos en lugar de uno |

Reconocimos que la opción A es defendible si se prioriza la simplicidad. Una forma de cerrar la discusión con datos propios sería un ensayo comparativo en banco: el mismo FSR con la misma EVA, leído por divisor + ADC interno y por multiplexor + transimpedancia, midiendo linealidad, ruido y repetibilidad.

**Sacamos el ADS1115.** Rehicimos el conexionado completo usando el ADC interno del ESP32-S3. La cadena analógica no cambió: la salida de 0,25–2,45 V entra en el rango del ADC con atenuación de 12 dB (≈ 0–3,1 V). Los recaudos que se agregaron:

- Usar solo el ADC1 (GPIO1 a GPIO10), porque el ADC2 comparte recursos con la radio.
- Un filtro RC en cada entrada del ADC, que además aísla al op-amp de la carga capacitiva del muestreo.
- Medir también Vref con el mismo ADC y trabajar con el cociente Vout/Vref, que cancela la variación del riel de 3,3 V y el error de ganancia del ADC.

El argumento de que "el sensor es el cuello de botella" se sostiene con menos margen: con el ADC interno y promediando queda un error del orden del 0,1 % del fondo de escala, unas 20 veces menor que el ±2 % del FSR.

**Error que encontramos en nuestro documento.** El PDF decía que el ADS1115 resolvía 0,06 % del fondo de escala por cuenta. En realidad era ~0,006 % (1 / 17 600 cuentas). El error no cambiaba ninguna conclusión, pero lo corregimos.

**Esquemático en KiCad.** Lo armamos componente por componente y pin por pin. Al revisar dos versiones sucesivas con un netlist aparecieron estos errores:

- El ESP32 no tenía conectada su alimentación de 3,3 V.
- El OPA2333 figuraba como tres referencias distintas en lugar de U7A, U7B y U7C.
- Faltaban la resistencia de pull-up y el capacitor del pin EN.
- No había conexión USB de datos para programar el microcontrolador.
- Los FSR y el NTC estaban dibujados dentro del esquemático de la placa; en la PCB solo va su conector (un JST de 10 vías).
- Faltaban capacitores de desacople en casi todos los integrados.
- Había una resistencia de valor no estándar (12,2 kΩ), que pasó a 12 kΩ.

Otras decisiones del esquemático:

- **Cargador.** El cargador que teníamos resultó ser el integrado MCP73831 suelto y no un módulo TP4056; más adelante lo reemplazamos por un módulo TP4056 externo con USB-C.
- **Multiplexor.** Dibujamos el CD4051B como sustituto del ADG708, sabiendo que su Ron a 3,3 V es de cientos de ohms y puede superar 1 kΩ, en serie con un FSR que baja a 1,7 kΩ.
- **Microcontrolador.** Pasamos del módulo ESP32-S3-WROOM-1 suelto a la placa de desarrollo ESP32-S3-DevKitC-1, con su mapeo de pines completo. Hubo que liberar el GPIO38, que maneja el LED RGB propio de la placa.

## Etapa 5 — Preparación del prototipo (30 de septiembre al 8 de octubre)

Decidimos empezar con 3 FSR en protoboard y validar la cadena de a un bloque por vez, con un criterio de "pasa / no pasa" en cada paso, antes de sumar el resto.

**Componentes para la protoboard (30 de septiembre).** La lista mínima fue: placa ESP32-S3-DevKitC-1 alimentada por USB, multiplexor CD4051B en cápsula DIP-16, OPA2333 con adaptador de SOIC-8 a DIP, 3 FSR 402, Rf de 15 kΩ, el divisor de referencia, capacitores de desacople de 100 nF, protoboard, cables y multímetro. Una regla quedó fija desde el principio: las patas del FSR no se sueldan, porque el calor derrite la carcasa plástica. El resto (OLED, reloj, NTC, buzzer, botones, batería, cargador y regulador) quedó para etapas posteriores.

**Lista para el sistema completo (8 de octubre).** Antes de ir al laboratorio armamos la lista de todo el sistema: cadena de medición, microcontrolador y reloj, alimentación, interfaz, pasivos, materiales de PCB, instrumental a pedir prestado y elementos de calibración (pesas patrón, balanza de piso, indentadores impresos en 3D). Marcamos lo que el laboratorio probablemente no tendría: los FSR, la goma EVA, la ortesis base, la batería y posiblemente el ESP32-S3-N16 y el OPA2333.

En la misma consulta confirmamos que no hace falta una memoria aparte: la flash interna de 16 MB del ESP32-S3-N16 alcanza para unos 224 días a 19 kB/día, con unas 5 escrituras diarias, muy lejos de su límite de desgaste. El riesgo real es perder el buffer si la batería se agota de golpe; se resuelve grabando antes de apagar, usando el divisor de batería que ya estaba en el diseño.

**Plan de armado por fases (8 de octubre).** Definimos el orden de validación: (0) preparación y rieles de alimentación; (1) ESP32 solo; (2) referencia de 0,25 V con el buffer; (3) transimpedancia con resistencias fijas de valor conocido; (4) multiplexor con resistencias de prueba, calculando su Ron; (5) FSR en lugar de las resistencias; (6) integración con el ESP32 y lectura por serial; (7) primeros ensayos del sensor con EVA. Sumamos un canal de referencia con una resistencia fija de 4,7 kΩ en el canal 7: si su lectura se mueve, el problema está en la electrónica y no en el sensor.

## Etapa 6 — Primer armado en protoboard (8 de octubre)

El primer día de armado terminó con una placa quemada y la cadena sin funcionar, pero dejó identificadas las cuatro causas: placa equivocada, cable sin datos, ruido de 50 Hz y un op-amp que no sirve a 3,3 V. Lo que pasó, en orden:

1. **No teníamos el OPA2333.** Teníamos un módulo con dos op-amps para protoboard. La primera respuesta fue una tabla de qué chips sirven a 3,3 V, y ahí ya figuraban el TL072 y el TL082 como chips que no arrancan a esa tensión. Pero no leímos la marca del integrado del módulo y armamos igual.
2. **Trajimos un multiplexor digital.** Teníamos un 74LS151 y preguntamos si reemplazaba al CD4051B. No sirve: es un selector digital que solo entrega un 0 o un 1, funciona en un solo sentido y necesita 5 V, con riesgo de dañar un pin del ESP32. El CD4051B es una llave analógica bidireccional que deja pasar la corriente real del FSR. Con el 74LS151 la transimpedancia nunca habría visto el sensor. Seguimos con el CD4051B.
3. **La placa no era la que creíamos.** Cableamos con los pines del esquemático de la ESP32-S3: la salida del op-amp al GPIO1 y el multiplexor a los GPIO11 a 13. No encontrábamos el GPIO11, el código no cargaba y la placa se calentaba. Con una foto se vio que era un ESP32 clásico (módulo ESP-WROOM-32, 38 pines). En el clásico el GPIO1 es el TX del puerto serie, el GPIO11 lo usa la flash interna y el GPIO12 es un pin de arranque. Además, en el entorno de Arduino estaba elegida la placa ESP32-S3.
4. **Se quemó el ESP32.** Remapeamos los pines, pero la placa ya no respondía ("No serial data received") y se calentaba aun desconectada de todo, hasta quedar hirviendo: corto interno permanente. La causa probable fue un corto en la protoboard (la placa es más ancha que la protoboard y una fila de pines puede quedar clavada en los rieles de alimentación), la salida del op-amp conectada al TX, o ambas.
5. **Segunda placa, fuera de la protoboard.** La placa de reemplazo, también un ESP32 clásico, no entraba en la protoboard. La dejamos sobre la mesa y llevamos con cables Dupont hembra-macho solo los 6 pines necesarios: 3V3, GND, GPIO34 (ADC), GPIO25, 26 y 27 (A, B y C del multiplexor). Ningún pin de la placa toca la protoboard. Quedaron prohibidos los GPIO0, 1, 2, 3, 5, 12 y 15 (arranque o serie) y del 6 al 11 (flash).
6. **La computadora no veía la placa.** Prendía el LED pero no aparecía ningún puerto COM. El cable micro-USB era el que venía con un Chromecast, que solo alimenta: no tiene hilos de datos. Compramos un cable homologado para datos y funcionó.
7. **Versión mínima del circuito.** Pedimos sacar todo lo que no fuera indispensable: los 4 capacitores, la resistencia serie del ADC y el buffer de la referencia. Señalamos que el diseño tiene dos op-amps (buffer y transimpedancia) y restituimos el buffer, que son solo dos conexiones.
8. **Una onda que no era el multiplexor.** Manteniendo el FSR apretado, la lectura subía y bajaba de forma regular. Era la red de 50 Hz, captada por los cables o por el cuerpo, submuestreada porque el código leía cada ~37 ms (aliasing). Promediando cada canal durante 20 ms (un ciclo completo de red) la onda desapareció.
9. **Lecturas sin sentido.** El reposo no daba los ~250 mV esperados, la salida bajaba al apretar en lugar de subir y solo tomaba dos valores (60 suelto, 250 apretado), sin importar la fuerza. Un salto brusco ante el primer contacto es normal en un FSR, porque pasa de circuito abierto a decenas de kΩ; la capa de EVA con precarga lo evita en uso. Pero una salida de dos estados indicaba un op-amp saturado.
10. **Era el TL082 (23:09).** El TL082 necesita unos 7 V como mínimo, sus entradas no funcionan cerca de GND (y Vref es 0,25 V) y cerca de ese límite invierte la salida (phase reversal). Ningún valor de Rf ni del divisor lo arreglaba: había que cambiar el chip.

La lección del día fue la misma tres veces: identificar cada placa y cada integrado por su marca antes de cablear. El aviso sobre el TL082 estaba escrito desde el primer paso del plan, y la placa clásica se podía reconocer antes de energizarla.

## Etapa 7 — Cadena de medición validada (9 al 11 de octubre)

Con un MCP6002 y Rf = 4,7 kΩ la cadena FSR → multiplexor → transimpedancia → ADC quedó funcionando, con 50 lecturas por segundo en cada canal.

**Elección del op-amp (9 de octubre).** Buscamos uno que funcionara seguro a 3,3 V y tuviera el mismo pinout que el TL082, para cambiarlo sin tocar cables. Los dos requisitos: alimentarse con 3 V o menos, y ser rail-to-rail o tener un rango de entrada que incluya GND. Además, cápsula DIP-8 para la protoboard.

| Op-amp | Alimentación | Rf | Comentario |
|---|---|---|---|
| MCP6002 (elegido) | 1,8–6 V | 15 kΩ | Rail-to-rail en entrada y salida, barato y fácil de conseguir |
| MCP6022 | 2,5–5,5 V | 15 kΩ | Igual de bueno, más caro |
| TLV2372 | 2,7–16 V | 15 kΩ | Rail-to-rail |
| OPA2340 | 2,7–5,5 V | 15 kΩ | Misma familia que el OPA2333 del diseño |
| LM358 | 3–32 V | 8,2 kΩ | Plan B: su salida no pasa de ~1,8 V |

Conseguimos el MCP6002, lo pusimos en el lugar del TL082 y el 11 de octubre confirmamos que la cadena respondía a la fuerza como correspondía.

**Saturación con Rf = 15 kΩ.** La señal hacía meseta muy rápido. El techo no eran los 3,3 V de alimentación sino el ADC del ESP32 clásico, que no lee más de ~3,1 V: la meseta (~2870 mV sobre la tara + ~250 mV de reposo) caía justo ahí. La salida satura cuando la resistencia del FSR baja de Rf / 11; con 15 kΩ eso es ~1,3 kΩ, y se alcanzaba apretando con un dedo. El diseño había supuesto que el FSR no bajaba de 1,7 kΩ. Subir la alimentación no era opción, porque superaría lo que el ADC puede leer, así que bajamos la ganancia:

| Rf | Satura cuando el FSR baja de |
|---|---|
| 15 kΩ (diseño) | ~1,3 kΩ |
| 10 kΩ | ~900 Ω |
| 4,7 kΩ (elegida) | ~420 Ω |
| 2,2 kΩ | ~200 Ω |

Elegimos 4,7 kΩ y funciona muy bien. Queda revalidarla con la capa de EVA y con la carga real del pie.

**50 lecturas por segundo en cada canal.** Al revisar el prototipo contra el diseño encontramos un conflicto: con el promedio de 20 ms por canal y 8 canales, cada canal se leía solo ~6 veces por segundo, y el diseño exige 50 para no subestimar el pico. La primera propuesta fue volver al filtro RC en la entrada del ADC, y fue un error que corregimos enseguida: ese filtro está después del multiplexor, tiene que estabilizarse cada vez que cambia el canal y no puede frenar una señal tan lenta como 50 Hz; si se lo hace más lento, mezcla los canales.

La solución quedó en el código: en cada ventana de 20 ms se recorren todos los canales 10 veces, cada 2 ms, y se promedia cada uno. Diez muestras repartidas en un ciclo completo de red cancelan los 50 Hz, y cada canal sigue entregando 50 lecturas por segundo. Un barrido de 8 canales tarda unos 8 × 110 µs y entra en el hueco de 2 ms. En hardware alcanza con dos desacoples de 100 nF, en el pin 8 del MCP6002 y en el pin 16 del CD4051B. Un RC de 1 kΩ y 10 nF en la entrada del ADC es opcional; el C13 de 100 nF del esquemático debe pasar a 10 nF.

**Dos diferencias con el diseño que quedaron abiertas.** El Ron del CD4051B, de cientos de ohms, pesa bastante con Rf = 4,7 kΩ y el FSR muy cargado: hay que medirlo y decidir si se absorbe en la calibración o se vuelve al ADG708. Y el esquemático es para el ESP32-S3 mientras el prototipo usa el clásico, con otros pines y otro ADC.

## Etapa 8 — Firmware del dosímetro (11 de octubre)

En un día el prototipo pasó de mostrar lecturas a funcionar como dosímetro: alarma, indicadores del día y corrección automática del cero.

**Alarma de sobrecarga.** El LED RGB marca verde, amarillo desde el 80 % del límite y rojo con el buzzer intermitente al superarlo. La alarma tiene histéresis: se apaga recién cuando la carga baja del 90 % del límite durante más de 2 s, igual que las excedencias del diseño. El límite es provisorio, 1500 mV de suma de canales, hasta que haya calibración.

**Tropiezo: una reescritura que rompió lo que andaba.** Para sumar los indicadores se reescribió el código de una vez, y dejó de funcionar: el LED no prendía, porque el código nuevo usaba el LED propio de la placa (GPIO2) en lugar del RGB, y el gráfico parecía trabado, porque imprimía una línea por segundo en lugar de 50. Pedimos hacerlo con más cuidado. Se rehízo partiendo del código que funcionaba y marcando con NUEVO cada línea agregada. Desde entonces trabajamos así: cada bloque nuevo se suma sobre la última versión que anda, marcado en el código.

**Indicadores del día.** Carga pico, tiempo apoyado (carga mayor a 100 mV), tiempo en exceso, excedencias, dosis de sobrecarga (en mV·min por ahora) y cumplimiento. Se consultan con el comando `i`, se ponen en cero con `r` y la tara se repite con `t`. Los verificamos en simulación contra un cálculo a mano: 5 s sobre el límite, 5 s debajo y 1 s más sobre el límite dieron 2 excedencias, 6 s en exceso, 11 s apoyado y 45,5 % de cumplimiento.

**Buzzer.** Usamos un buzzer activo TMB12A05, de 5 V nominales, conectado directo al GPIO19 para las pruebas. Se agregó un pitido corto al terminar la tara y el comando `b` para probarlo sin apretar los FSR.

**Seguidor de línea de base.** Lo implementamos como estaba en el diseño, sobre el código que ya funcionaba. Para probarlo sin esperar horas agregamos `MODO_RAPIDO`, en el que un "minuto" dura 5 s. Antes de llevarlo a la placa lo validamos en simulación con perfiles sintéticos: un cero que se corre, apretones periódicos como pasos y un canal que nunca concuerda, para ver el aviso de los 30 minutos (LED azul parpadeando, que se resuelve con una tara manual).

Las pruebas mostraron dos limitaciones del método, que hay que medir en el ensayo V4 y declarar en el informe final:

- Cuando el cero sube, la corrección recién empieza después de 15 minutos (80 s en modo rápido), porque un mínimo más bajo de la historia siempre gana. Como la deriva real del FSR es lenta, la demora es aceptable.
- Si el pie queda apoyado y quieto más de 15 minutos seguidos, el seguidor puede tomar esa carga como cero. El método supone que en 15 minutos el pie se levanta al menos 3 veces.

**¿Y el NTC?** Preguntamos si el seguidor usaba el termistor para corregir. No lo usa: mira el resultado y no la causa, así que corrige cualquier corrimiento del cero, sea por creep, temperatura o humedad. Lo que el seguidor no puede corregir es un cambio de sensibilidad con la temperatura, porque para eso necesitaría conocer la carga. Decidimos no agregar el NTC por ahora. Se justificaría solo si una calibración a dos temperaturas (ambiente y plantilla a temperatura del pie) muestra un cambio de sensibilidad grande frente al ±2 % de repetibilidad del FSR.

## Etapa 9 — Reloj, registro y pantalla (16 de octubre)

Sumamos el reloj de tiempo real, el registro en la flash interna y la pantalla con dos botones, en ese orden y sin tocar el muestreo de 50 Hz.

**Por qué ese orden.** El registro necesita fecha y hora en cada dato, y los indicadores tienen que cerrarse a medianoche porque el reporte es diario. El reloj es un módulo I²C simple y de poco riesgo, así que fue primero. La pantalla comparte el mismo bus, por lo que quedó para el final.

**Reloj DS3231.** Lo probamos primero con un programa aparte que escanea el bus I²C (direcciones 0x68 del reloj y 0x57 de la EEPROM del módulo) y verificamos la pila desenchufando el USB. Al integrarlo, la hora se lee una sola vez por minuto, en el cierre de cada minuto, para que la lectura I²C no altere la ventana de 20 ms. A medianoche se cierra el día y los indicadores vuelven a cero; con el comando `h` se pone la hora. El módulo trae un circuito de carga pensado para pilas recargables: con una CR2032 común no hace daño a 3,3 V, pero sí a 5 V, así que el módulo se alimenta siempre a 3,3 V.

**Registro en la flash.** Usamos LittleFS sobre la flash interna, en un archivo de 18 bytes por minuto con hora, límite, pico, tiempo apoyado y en exceso, dosis, excedencias y señales de estado. Son 5 bytes más que los 13 B/min previstos en el diseño, lo que acorta la autonomía del registro. Se escribe cada 10 minutos para cuidar la flash, así que ante un corte se pierden como máximo 10 minutos; al encender, el dispositivo recupera los indicadores del día. Comandos: `g` graba en el momento, `d` descarga un CSV (resumen por día y detalle por minuto) y `xBORRAR` borra todo. El ESP32 clásico tiene 4 MB de flash y no 16 MB, así que quedan unos 1,5 MB para registro.

**Pantalla y botones.** Un OLED GM009605 V4 (controlador SSD1306, dirección 0x3C) en el mismo bus que el reloj. Su pin dice SCK, que es lo mismo que SCL. Dibujar la pantalla tarda unos 25 ms, más que la ventana de 20 ms, así que la pantalla corre en una tarea aparte en el otro núcleo del ESP32: en el bucle principal habría roto el muestreo. Tiene cuatro pantallas: AHORA, HOY, REGISTRO y SENSOR. El botón A (GPIO32) cambia de pantalla; el botón B (GPIO33), mantenido 3 s en SENSOR, hace la tara. La pantalla se apaga sola tras 1 minuto sin botones y la alarma la vuelve a prender.

**Tropiezos.** El código no compilaba porque faltaba instalar la librería U8g2. Después la pantalla no prendía aunque el cableado estaba bien: el primer módulo OLED vino dañado, y con uno nuevo funcionó.

**Qué sigue.** Al terminar evaluamos agregar el NTC y decidimos que lo siguiente es la calibración: hoy el límite, la dosis y el pico están en mV, y un profesional no prescribe "no pases de 1500 mV" sino "apoyá como mucho el 20 % de tu peso".

## Etapa 10 — Intercambio con la cátedra y preparación de la calibración (20 al 22 de octubre)

Un docente nos pidió el esquemático y una explicación de la etapa de adquisición, y en paralelo preparamos la calibración, que arranca la semana próxima.

**Consulta del docente (20 de octubre).** Santi, que dirige una tesis sobre una plataforma para pie diabético con FSR similares (rango de ~150 N), nos pidió el esquemático y cómo adquirimos la señal. Fuimos simplificando la respuesta hasta dejarla en pocas oraciones. El punto central: usamos transimpedancia en lugar de un divisor porque la salida queda proporcional a la conductancia del FSR, que es más lineal con la fuerza y simplifica la calibración. Una descripción inicial decía que el primer op-amp era "más que un buffer"; lo corregimos mirando el esquemático: es un buffer que entrega la tensión de referencia a la transimpedancia. Sobre la calibración aclaramos que está planificada y no hecha: primero por sensor con pesas conocidas, después un ajuste global por persona con una balanza. Nuestros FSR llegan a ~10 N cada uno, que alcanza porque solo se mide una fracción del peso corporal.

**Preparación de la calibración (22 de octubre).** La calibración se hará en casa, así que armamos la lista de lo que hay que llevar del laboratorio, pensada para que el proceso sea lo más simple posible. La decisión más importante es previa: la calibración queda atada a la cadena exacta. Si después se cambia el CD4051B por el ADG708, la Rf de 4,7 kΩ o el ADC interno por el ADS1115, hay que calibrar todo de nuevo. Por eso conviene fijar la cadena final antes de calibrar.

Lo esencial de la lista:

| Elemento | Para qué |
|---|---|
| Pesas patrón de 100 g, 200 g, 500 g y 1 kg | Calibración por canal; el FSR llega a ~1 kgf |
| Multímetro con cocodrilos | Medir el Ron del CD4051B y verificar tensiones |
| Resistencias al 1 % de 1 kΩ a 100 kΩ | Reemplazar al FSR y separar si un error viene del circuito o del sensor |
| Cable USB de datos de 2–3 m, probado | Que lo largo sea el USB y no los cables de los FSR |
| Cable UTP de 50–80 cm y headers hembra | Pares trenzados contra el ruido de 50 Hz; los FSR no se sueldan |
| Soporte impreso en 3D con pistón guiado, o un disco rígido de ~12 mm | Que la carga caiga siempre igual y dentro del área activa |
| Cinta y marcador | Numerar cada FSR y su cable: la calibración es por canal |
| Repuestos: ESP32, MCP6002 y CD4051B | Ya quemamos un ESP32 |
| Goma EVA del espesor final, balanza de baño y la bota | Calibración con el transductor real y calibración global parado |

El criterio de los cables sale de lo aprendido con el aliasing: los FSR son de alta impedancia y con cables largos captan los 50 Hz de la red, así que el ESP32 queda cerca del pie con cables cortos y lo largo es el USB a la computadora.

## Diseño original frente al prototipo actual

El prototipo se aparta del diseño en casi todos los bloques de la cadena, siempre por disponibilidad o por un problema encontrado al armar; varias de esas diferencias tienen que resolverse antes de calibrar.

| Bloque | Diseño | Prototipo | Motivo del cambio | Qué queda por decidir |
|---|---|---|---|---|
| Microcontrolador | ESP32-S3-WROOM-1-N16 | ESP32 clásico, DevKit de 38 pines | La placa disponible era un ESP32 clásico | Con cuál se hace la placa final; actualizar KiCad |
| Flash para registro | 16 MB | 4 MB (~1,5 MB para registro) | Viene con la placa | Recalcular la autonomía del registro |
| Multiplexor | ADG708 (Ron 8 Ω) | CD4051B (Ron de cientos de Ω) | Era el disponible | Medir el Ron; absorberlo en la calibración o volver al ADG708 |
| Op-amp | OPA2333 (SOIC-8) | MCP6002 (DIP-8, rail-to-rail) | El OPA2333 no entra en protoboard; el TL082 no funciona a 3,3 V | — |
| Rf | 15 kΩ | 4,7 kΩ | Con 15 kΩ el ADC saturaba con un dedo | Revalidar con EVA y la carga del pie; actualizar R8 en KiCad |
| ADC | ADS1115 (16 bits); el 25/9 pasó al interno del S3 | ADC interno del ESP32 clásico, GPIO34 | Decisión del 25 de septiembre | Interno o ADS1115, antes de calibrar |
| Filtro de 50 Hz | No previsto | Por código: 10 barridos de todos los canales en 20 ms | Aliasing de la red | Cambiar C13 de 100 nF a 10 nF en KiCad |
| Sensores | 8 FSR | 3 FSR | Validar de a poco | Sumar los 5 restantes |
| Registro | 13 B/min | 18 B/min en LittleFS | Más campos por registro | — |
| Buzzer | Piezo con transistor | Activo TMB12A05, directo a GPIO19 | Para pruebas | Verificar si hace falta transistor |
| Alimentación | LiPo + TP4056 + AP2112K | USB de la placa | Etapa de banco | Pasar a batería y medir consumo |
| NTC | En el esquemático | No agregado | El seguidor corrige el cero por cualquier causa | Solo si el ensayo V4 o la calibración a dos temperaturas lo justifican |

## Errores y lecciones aprendidas

Registramos quince errores en dos meses, casi la mitad el primer día de armado; la mayoría se habría evitado identificando cada componente o verificando un paso antes de avanzar al siguiente.

| Fecha | Error | Qué provocó | Lección |
|---|---|---|---|
| 19 ago | Primeras versiones con análisis de marcha, IMU y centro de presión | Un proyecto que no respondía a su objetivo | Diseñar primero el indicador y derivar de él los requisitos |
| 20 ago | Anteproyecto escrito como referencia técnica | Hubo que rehacerlo | Confirmar el formato de la cátedra antes de redactar |
| 25 sep | El documento decía 0,06 % por cuenta del ADC | Un número 10 veces mayor que el real (0,006 %) | Revisar los cálculos del propio documento |
| 25 sep | Esquemático sin 3V3 en el ESP32, sin pin EN, sin USB de datos, sin desacoples | Una placa que no habría arrancado ni podido programarse | Revisar el esquemático con un netlist antes de pasar a PCB |
| 8 oct | Traer un 74LS151 como multiplexor | No habría medido nada y arriesgaba un GPIO | Distinguir una llave analógica de un selector digital |
| 8 oct | Creer que la placa era una ESP32-S3 | ADC cableado al TX del serie; código que no cargaba | Identificar la placa por la marca del módulo antes de cablear |
| 8 oct | Placa en la protoboard sin revisar el armado | Un ESP32 quemado | Placa fuera de la protoboard, revisar el armado antes de energizar, tener multímetro |
| 8 oct | Cable micro-USB de Chromecast | La computadora no veía la placa | Usar un cable de datos conocido |
| 8 oct | Sacar el buffer de la referencia al simplificar | Un circuito distinto del diseño | Simplificar sin cambiar la topología |
| 8 oct | Muestrear cada ~37 ms sin promediar | Una onda falsa por aliasing de 50 Hz | Promediar un ciclo de red completo; diagnosticar con una resistencia conocida |
| 8 oct | Usar un TL082 a 3,3 V | Salida invertida y de dos estados; horas de diagnóstico | Verificar la tensión mínima y si es rail-to-rail; leer la marca del chip |
| 11 oct | Rf de 15 kΩ elegida sobre la curva típica del FSR | El ADC saturaba con un dedo | Validar la ganancia con la fuerza real |
| 11 oct | Proponer un RC después del multiplexor para sacar los 50 Hz | Habría mezclado los canales sin filtrar la red | Un filtro después de un multiplexor tiene que asentarse en cada cambio de canal |
| 11 oct | Reescribir el código entero para sumar los indicadores | El LED dejó de prender y el gráfico se trabó | Sumar de a un bloque sobre la versión que anda, marcando lo nuevo |
| 16 oct | Sospechar del cableado del OLED | Revisar un cableado que estaba bien; el módulo venía dañado | Escanear el bus I²C y probar otro módulo antes de recablear |

## Estado actual y próximos pasos

El dispositivo funciona de punta a punta en banco con 3 FSR; lo que falta es darle significado clínico a sus números con la calibración y demostrar con ensayos que mide lo que dice medir.

**Qué funciona hoy.** Lectura de 3 FSR a 50 Hz por canal sin ruido de red, alarma con LED y buzzer, los seis indicadores del día, seguidor de línea de base con aviso y tara manual, reloj con cierre diario, registro por minuto en la flash con descarga en CSV, y pantalla de cuatro vistas con dos botones. El firmware vigente es `alarma_con_display.ino`, con cada bloque marcado en el código.

**Próximos pasos, en orden:**

- [ ] Fijar la cadena final antes de calibrar: medir el Ron del CD4051B y decidir multiplexor, ADC (interno o ADS1115) y Rf con la capa de EVA
- [ ] Calibración de nivel 1, por canal, con EVA y pesas patrón
- [ ] Calibración de nivel 2, global por sujeto, contra balanza
- [ ] Pasar límite e indicadores de mV a % del peso corporal y sumar el modo técnico en el botón B
- [ ] Poner `MODO_RAPIDO = false` y correr el ensayo V4 del seguidor (3 h)
- [ ] Ensayos V5 (exactitud de la dosis) y V9 (jornada completa sin teléfono)
- [ ] Sumar los 5 FSR restantes; el último exige liberar el canal 7 de referencia
- [ ] Decidir ESP32 clásico o S3 para la placa final y actualizar KiCad (R8 = 4,7 kΩ, C13 = 10 nF)
- [ ] Pasar a batería (LiPo, TP4056, AP2112K) y medir el consumo real
- [ ] Evaluar el NTC solo si el ensayo V4 o una calibración a dos temperaturas lo justifican

**Preguntas abiertas.** Tipo de lesión y etapa post-quirúrgica del paciente objetivo, usuario principal (paciente o profesional), uso individual o compartido, contacto con un kinesiólogo o traumatólogo, cronograma de 16 semanas por hitos y disponibilidad en la cátedra de la bota base y de las pesas patrón.
