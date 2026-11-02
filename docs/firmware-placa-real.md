# Firmware de la placa real — briefing

Este documento es para quien (persona o Claude Code) tome el firmware cuando exista la placa.
Explica **por qué** el software está como está, qué parte ya funciona y no hay que tocar, y qué
falta construir. Leelo entero antes de escribir una línea: hay varias decisiones que parecen
arbitrarias y no lo son.

Contexto general del proyecto: `CLAUDE.md` en la raíz. Este documento no lo reemplaza.

> **Antes que nada, leer `docs/avances/`.** Este briefing se escribió en septiembre, cuando no había
> electrónica armada, y suponía una cadena que al final no se usó. En octubre el equipo armó, validó y
> calibró el prototipo, y **esa cadena es la definitiva**: CD4051B, MCP6002 con Rf = 4,7 kΩ, ADC interno
> del **ESP32 clásico** y valores en gramos. No ADG708, no OPA2333, no ADS1115, no ESP32-S3.
>
> Las secciones corregidas están marcadas. Donde este documento y `docs/avances/` discrepen, mandan
> los informes.
>
> Además existe un firmware que ya funciona, `dosimetro_calibrado.ino` (Arduino IDE, 28/10), fuera de este
> repo: lee los 3 FSR, da la alarma, calcula los indicadores, corrige el cero, maneja reloj, registro
> en LittleFS y pantalla. **No implementa BLE.** Lo que falta no es escribir todo de nuevo, sino unir
> ese firmware con el protocolo y la dosimetría que ya están acá.

---

## 1. Lo que ya funciona y no hay que romper

Hoy el firmware corre en un **ESP32 devkit con un potenciómetro** que simula la carga. Todo lo
demás es el código definitivo: la dosimetría, el protocolo BLE, el cierre del día, el semáforo,
los límites pendientes. Eso ya está probado y tiene tests.

| Módulo | Qué es | Estado |
|---|---|---|
| `lib/dosimetria` | integra la dosis a 50 Hz, agrega por minuto, detecta excedencias | listo, 9 tests |
| `lib/protocolo` | serializa los paquetes BLE | listo, 9 tests contra vectores compartidos |
| `src/main.cpp` | servidor BLE, semáforo, botón, cierre del día | funcional con potenciómetro |
| `src/placa.h` | pines | solo devkit, falta la placa final |

La app del paciente y la web del médico **ya están terminadas y probadas contra un teléfono real**.
Están esperando a la placa. Si el firmware respeta el protocolo, no hay que tocar nada del otro lado.

---

## 2. Las reglas que no se negocian

Vienen de la cátedra y de las decisiones del grupo. Romper cualquiera de estas es un error de
diseño, no una preferencia:

1. **Las métricas se calculan en el microcontrolador.** La app y la web solo muestran. El motivo
   es que el celular puede estar apagado, sin batería o en otra habitación: si el cálculo
   dependiera de él, se perderían datos. El equipo integra a 50 Hz y guarda el resultado.
2. **El paciente nunca ve valores crudos ni %PC.** Solo semáforo, excedencias del día y batería.
   Por eso la característica de estado en vivo **no incluye** la carga instantánea, a propósito.
3. **El exceso se muestra en ámbar, no en rojo.** Pedido explícito de la cátedra.
4. **El dispositivo no guarda datos personales.** Solo el ID del episodio (16 caracteres hex).
   Ni nombre, ni documento, ni nada que identifique a la persona. Ley 25.326, datos de salud.
5. **Un límite enviado por BLE queda pendiente hasta confirmarse con el pulsador del equipo.**
   Ningún cambio remoto mueve el umbral sin validación presencial. Ya está implementado:
   pulsación larga de 2 segundos.
6. **No se guarda señal cruda en la flash.** Agregados por minuto, nada más. El cálculo está en
   `docs/decisiones/003`: la señal cruda serían 69 MB por día y no entra.
7. **Español rioplatense** en nombres de dominio, comentarios y documentación (`dosis`, `episodio`,
   `excedencia`, `carga`). El código existente ya está así; seguí la misma línea.

---

## 3. El contrato: el protocolo BLE

`docs/protocolo-ble.md` es **la fuente de verdad**. No es documentación que describe el código: es
el contrato que el código tiene que cumplir. Hay tres clientes que dependen de él.

### La regla de los cinco archivos

Cualquier cambio al protocolo toca **en el mismo commit**:

1. `docs/protocolo-ble.md`
2. `docs/protocolo-vectores.json`
3. `firmware/lib/protocolo/protocolo.h`
4. `app-paciente/lib/dispositivo/codec_ble.dart`
5. los tests de los dos lados

### Los vectores compartidos

`docs/protocolo-vectores.json` tiene paquetes de ejemplo en hexadecimal con sus valores. Lo leen
**los tres clientes**:

- `firmware/test/test_protocolo` — el firmware **codifica** y compara byte a byte.
- `app-paciente/test/vectores_test.dart` — la app **decodifica** y compara valores.
- `web-medico/src/ble/consultorio.test.js` — la web **decodifica** y compara valores.

Si corrés un byte en el firmware, fallan los tests de los tres lados. Esto existe porque un byte
corrido entre la placa y la app, sin esta red, aparece recién con el hardware en la mano y a dos
días de la entrega. **No lo desarmes.**

### Las ocho características

| UUID | Qué | Propiedades |
|---|---|---|
| `6f1a0001` | estado en vivo, 8 B | read, notify a 1 Hz |
| `6f1a0002` | resumen del día **en curso**, 28 B | read |
| `6f1a0003` | pedidos de descarga, 5 B | write |
| `6f1a0004` | registros por minuto | notify |
| `6f1a0005` | configuración (límites y peso) | read, write |
| `6f1a0006` | hora | write |
| `6f1a0007` | info y episodio | read, write |
| `6f1a0008` | resúmenes de días **cerrados** | notify |

Detalle importante: un resumen de día cerrado tiene **exactamente el mismo formato de 28 bytes**
que el del día en curso. Un solo codificador, `proto::codificarResumen`, sirve para los dos.

---

## 4. Los dos caminos de los datos

Están en `docs/decisiones/005`. Los dos ya funcionan del lado de la app y de la web.

```
                        ┌──────────────► app del paciente ──HTTPS──┐
                        │   BLE (1 Hz + descarga)                  │
   ortesis (flash =     │                                          ▼
   fuente de verdad) ───┤                                       Supabase
                        │                                          ▲
                        └──────────► web del médico ───────────────┘
                            BLE en la consulta        el médico lee con su cuenta
                            (Web Bluetooth)
```

**Camino 1, entre consultas.** El paciente abre la app, la app se conecta por BLE, baja lo que el
equipo tenga guardado y lo sube a Supabase cuando hay señal. Sube al abrirse, cada vez que el
equipo se conecta, cada 15 minutos y a pedido. Si no hay señal, queda en una cola local y no se
pierde nada.

**Camino 2, en la consulta.** El médico aprieta un botón en la web, el navegador se conecta por
Web Bluetooth y descarga lo mismo. Sirve aunque el paciente nunca haya instalado la app.

**Lo que esto significa para el firmware:** el equipo no sabe ni le importa quién lo está
descargando. Contesta lo mismo a los dos. No hay lógica de "ya se lo di a la app": el equipo
guarda y entrega cuantas veces se lo pidan, y los dos caminos escriben con `upsert` del otro lado,
así que reenviar nunca duplica.

Consecuencia de diseño: **el equipo no borra lo que entregó**. Solo borra cuando se cierra el
episodio (se le escriben 16 ceros en `6f1a0007`), que es la devolución del equipo.

---

## 5. Cómo los tres comparten la misma identidad

Esto es una funcionalidad, no un detalle, y tiene una consecuencia directa sobre el firmware.

**El problema.** La app se conecta a la ortesis que mejor se escucha. En un consultorio con varias
ortesis prendidas, esa puede no ser la del paciente. Si la app subiera esos datos, la ficha de una
persona quedaría con las mediciones de otra. En un contexto clínico eso es grave.

**La solución: el ID de episodio es la clave que une a los tres.**

```
  web del médico                     app del paciente                  ortesis
 ────────────────                   ──────────────────                ─────────
  crea el episodio
  escribe el ID por BLE  ──────────────────────────────────────────►  lo guarda (0007)
  muestra el QR con
  {token, ID de episodio} ─────────►  lo guarda en el celular
                                      lee el ID del equipo (0007)  ◄──  lo informa
                                      ¿coinciden? recién ahí sube
                                      informa qué límites tiene   ◄──   los informa (0005)
  ve si la indicación llegó  ◄───────  y con qué peso calcula
```

Las tres reglas que aplica la app:

| Lo que dice el equipo | Qué hace la app |
|---|---|
| el mismo episodio que el QR | sube normalmente |
| **otro** episodio | **no sube nada** y avisa "esta no es tu ortesis" |
| sin episodio (nunca asignada) | sube igual: un equipo en blanco no contradice a nadie |

**Qué datos comparten.** El ID de episodio, los dos límites y el peso corporal. El peso importa
porque es lo que convierte fuerza en %PC: si el equipo tiene un peso distinto del que el médico
prescribió, todos los porcentajes salen mal, y la web lo marca.

**Qué NO comparten: el nombre y el documento.** No van al equipo ni al QR. El equipo rota entre
pacientes; si llevara datos personales, cada devolución sería una fuga. El nombre vive solo en
Supabase, donde las policies lo protegen por médico. Los tres sistemas hablan del mismo paciente
sin que el equipo sepa quién es. No agregues el nombre al protocolo por más cómodo que parezca.

### Lo que esto le exige al firmware, y hoy no cumple

**El episodio y los límites están en RAM.** Mirá `main.cpp`:

```cpp
static char episodio[16] = {0};
static float pesoActivo_kg = 70.0f;
...
Limites lim; lim.L = 20.0f; lim.Lmin = 10.0f;   // en setup()
```

Si el equipo se reinicia o se queda sin batería:

- **olvida a qué tratamiento pertenece**, y la app lo va a ver como "sin asignar";
- **vuelve a L = 20 %PC, Lmin = 10 %PC y 70 kg**, que son valores de fábrica que nadie prescribió.

Lo segundo es un problema de seguridad del paciente: el equipo sigue midiendo, sigue mostrando el
semáforo y sigue acumulando dosis, pero contra un límite inventado. **Guardalos en NVS**
(`Preferences.h`) al escribirlos y leelos en `setup()`. Es de las primeras cosas que hay que hacer,
y es barata.

Lo mismo vale para el offset horario y para la calibración de los canales cuando exista.

---

## 6. Cómo está organizado el firmware, y por qué

```
firmware/
├── lib/dosimetria/     C++ puro. Sin Arduino, sin hardware. Se testea en la PC.
├── lib/protocolo/      Serialización. Sin Arduino. Se testea en la PC.
├── src/                Todo lo que toca hardware. NO se testea en la PC.
└── test/               pio test -e native
```

La división importa: `lib/dosimetria` y `lib/protocolo` **no incluyen `Arduino.h`**, y por eso se
compilan y testean en la computadora con `pio test -e native`, sin placa. Ese es el único lugar
donde hoy se puede verificar algo. Si metés dependencias de hardware ahí, perdés los tests.

El entorno `native` de `platformio.ini` tiene `lib_ignore = NimBLE-Arduino` justamente para eso.
**Todo lo que agregues que toque hardware va en `src/`.**

### La lógica que ya está resuelta

`Dosimetro::actualizar(carga, dt)` hace el trabajo fino del Anexo A. Leelo (`lib/dosimetria/dosimetria.cpp`),
es corto, y tiene sutilezas que costaron:

- La excedencia arranca cuando la carga cruza L hacia arriba, y termina cuando baja de 0,9·L
  **sostenido más de 2 segundos**. Sin esa histéresis, una oscilación alrededor del umbral cuenta
  veinte excedencias en vez de una. Hay un test para eso.
- El reposo **no** cuenta como subcarga. Estar sentado no es un déficit de carga. Por eso la dosis
  de subcarga solo acumula si hay apoyo efectivo (C > 5 %PC). Hay un test para eso.
- `AgregadorMinuto` saca la dosis del minuto restando acumulados, y maneja el caso del reinicio a
  medianoche (si el acumulado bajó, es que se reinició).

**No reescribas esto.** Si creés que tiene un error, escribí primero un test que lo demuestre.

---

## 7. Lo que hay que construir

### 7.1 Guardar en la flash (LittleFS) — lo más importante

Hoy el historial y los resúmenes viven en **RAM**:

```cpp
static std::vector<RegistroMinuto> historial;   // 3 días
static std::vector<ResumenDia> resumenes;       // 400 días
```

Sobreviven a la medianoche y a que el paciente no abra la app, que era el agujero grande. **No
sobreviven a un reinicio ni a que se agote la batería.** El equipo tiene que ser autónomo: esa es
parte de la consigna, y es el motivo de que la flash sea la fuente de verdad.

**Cuánto ocupa** (corregido con el hardware real; ver `docs/decisiones/003`):

| Qué | Tamaño | Por día | Por año |
|---|---|---|---|
| Registro por minuto | 18 B | 25,9 KB | 9,5 MB |
| Resumen diario | 28 B | 28 B | 10 KB |

El ESP32 clásico tiene **4 MB de flash**, de los que quedan **~1,5 MB para registro**: unos **58 días**
de uso continuo, no 1,5 años. Es suficiente para un tratamiento, que es el horizonte real del equipo,
pero conviene saberlo antes de prometer autonomía.

Dos aclaraciones para no confundir formatos:

- Los **18 B/min son el registro en flash**, que guarda más campos (hora, límite, pico, tiempo apoyado
  y en exceso, dosis, excedencias y señales de estado). Los **12 B/min del protocolo BLE** (0004) son
  otra cosa: lo que viaja al teléfono. No tienen por qué coincidir.
- El prototipo escribe cada 10 minutos para cuidar la flash, así que ante un corte se pierden como
  máximo 10 minutos. Al encender recupera los indicadores del día.

**Cómo encararlo.** Hacé lo mismo que hicimos en la app: una interfaz abstracta con dos
implementaciones, una en RAM para los tests y otra real para la placa.

```
lib/almacen/almacen.h        interfaz + implementación en RAM  → se testea en la PC
src/almacen_littlefs.{h,cpp} implementación con LittleFS       → solo en la placa
```

La interfaz necesita poco: agregar un registro por minuto, agregar un resumen de día, y **recorrer
desde una fecha** (no "devolver todo": no hay RAM para eso, y `enviarHistorial()` ya envía en
paquetes a medida que recorre).

Algo así, con un callback para no materializar listas:

```cpp
class Almacen {
 public:
  virtual void guardarMinuto(const RegistroMinuto& r) = 0;
  virtual void guardarDia(uint32_t inicioDia, const Acumulado& a) = 0;
  virtual void recorrerMinutos(uint32_t desde, void (*fn)(const RegistroMinuto&, void*), void* ctx) = 0;
  virtual void recorrerDias(uint32_t desde, void (*fn)(uint32_t, const Acumulado&, void*), void* ctx) = 0;
  virtual void borrarTodo() = 0;   // devolución del equipo
};
```

Si hacés esto bien, `enviarHistorial()` y `enviarResumenes()` en `main.cpp` casi no cambian: hoy
recorren un `std::vector`, después recorren el almacén.

**Disposición de archivos sugerida.** Append-only, que es lo que mejor se lleva con LittleFS:

- `/dias/AAAAMMDD.bin` — registros por minuto del día, uno atrás del otro (18 B en el formato de flash
  del prototipo; el de 12 B es el del protocolo BLE, no el de disco).
- `/resumenes.bin` — resúmenes de 28 B, uno atrás del otro.

Así, "recorrer desde una fecha" es abrir los archivos que correspondan, sin índices ni borrados en
el medio. Borrar un día viejo es borrar un archivo.

**Particiones.** Hace falta una tabla propia; la que trae PlatformIO por defecto no deja espacio.
Creá `firmware/particiones.csv`:

```
# Name,     Type, SubType, Offset,   Size,     Flags
nvs,        data, nvs,     0x9000,   0x5000,
factory,    app,  factory, 0x10000,  0x200000,
littlefs,   data, spiffs,  0x210000, 0x1F0000,
```

Es para los **4 MB del ESP32 clásico**: 2 MB de aplicación y ~1,9 MB de LittleFS. Sin OTA, que no se
usa y liberarlo da espacio de registro. El prototipo hoy corre con el esquema por defecto del Arduino
IDE, que deja ~1,5 MB.

> **Cambiar la tabla de particiones borra el LittleFS.** No es un problema en esta transición, porque
> el registro que hay hoy está en mV y hay que borrarlo igual con `xBORRAR`. Pero conviene saberlo: si
> alguien cambia la tabla más adelante con un tratamiento en curso, se pierde el historial del
> paciente. Bajar los datos antes.

y en `platformio.ini`, en el entorno `esp32dev`:

```ini
board_build.partitions = particiones.csv
board_build.filesystem = littlefs
```

**Trampa conocida:** el subtipo tiene que decir `spiffs` aunque el sistema de archivos sea
LittleFS. Es como lo busca la librería. Si ponés `littlefs` no monta y el error no lo dice.

**Desgaste.** Un registro por minuto son 1440 escrituras por día. LittleFS hace wear leveling y un
bloque de 4 KB entra unos 340 registros, así que son unas 4 escrituras de bloque por día. Para
100.000 ciclos de borrado, no es un problema. No te pongas a optimizar esto antes de medirlo.

**Corte de luz.** LittleFS es resistente a cortes por diseño, pero cerrá o hacé `flush` del archivo
después de cada minuto. Un registro perdido es aceptable; un sistema de archivos corrupto no.

### 7.2 Leer los sensores de verdad

Hoy:

```cpp
static float leerCarga() {
  int crudo = analogRead(PIN_POT);
  return crudo / 4095.0f * CARGA_MAX_SIM;
}
```

La cadena real es: **3 de 8 × FSR 402 con EVA → CD4051B (multiplexor) → MCP6002 (transimpedancia,
Rf = 4,7 kΩ) → ADC interno del ESP32 clásico (GPIO34)**. Sin NTC: se descartó.

**Buena noticia: casi todo esto ya está resuelto** en `dosimetro_calibrado.ino`, el firmware del
prototipo. Leé `docs/avances/` antes de escribir nada, porque el trabajo que falta no es construir
esto de cero, sino traerlo acá y unirlo con la dosimetría y el BLE que ya están.

Aplicá el mismo patrón que con el almacenamiento: una interfaz `FuenteCarga` con
`FuentePotenciometro` (la de hoy, para seguir probando sin plantilla) y `FuenteFsr` (la nueva).
Así se cambia una clase sin tocar ni la dosimetría ni el BLE.

**Lo que ya está resuelto en el prototipo, y hay que portar tal cual:**

1. **Muestreo sin ruido de red.** En cada ventana de 20 ms se recorren todos los canales 10 veces,
   cada 2 ms, y se promedia cada uno. Diez muestras repartidas sobre un ciclo completo de 50 Hz
   cancelan la interferencia de red, y cada canal entrega sus 50 lecturas por segundo.

   **Sobre el filtro RC hay que distinguir dos cosas**, porque se confunden y una funciona y la
   otra no:

   | | Qué es | Veredicto |
   |---|---|---|
   | RC **lento** después del MUX, para filtrar los 50 Hz | Constante de tiempo comparable al ciclo de red | **No va.** Tiene que asentarse en cada cambio de canal, así que mezcla canales. Se intentó y falló; los 50 Hz se cancelan por firmware |
   | RC **rápido** en la entrada del ADC | 1 kΩ + 10 nF, τ ≈ 10 µs | **Sí va.** No filtra nada de la señal: es un reservorio de carga para el muestreo del ADC, y aísla al op-amp de su carga capacitiva |

   Por eso **C13 pasa de 100 nF a 10 nF** en el esquemático: con 100 nF el RC se vuelve lento y cae
   en el primer caso.
2. **De mV a gramos.** Tabla de 9 puntos con interpolación lineal, de la calibración del 28/10. Se
   resta el cero de cada canal **en mV y después** se convierte, porque la curva no es lineal y
   hacerlo al revés da otro resultado. Fuera de la tabla: ΔV ≤ 0 da 0 g, y ΔV ≥ 2658 mV queda fijo
   en 2800 g (sensor saturado). La carga total es la suma de los canales.
3. **Deriva del cero.** El seguidor de línea de base está implementado y validado con perfiles
   sintéticos. Guarda el mínimo de cada canal por minuto, conserva los últimos 15, y si los 3 más
   bajos concuerdan actualiza el offset como 0,2·candidato + 0,8·offset. Tiene dos limitaciones
   medidas, que hay que declarar en el informe: tarda 15 minutos en corregir un cero que sube, y si
   el pie queda apoyado y quieto más de 15 minutos puede tomar esa carga como cero.

**Lo que sigue pendiente:**

4. **De gramos a %PC.** Es el agujero que queda. El dosímetro trabaja en porcentaje del peso
   corporal, el equipo hoy entrega gramos, y el puente es la **calibración global contra balanza,
   que no se hizo**. El peso llega por BLE en la característica de configuración y se guarda en
   `pesoActivo_kg` sin usarse. No alcanza con dividir por el peso: 3 sensores cubren una fracción
   de la planta, así que su suma no es la carga total. Hace falta el factor k por mínimos cuadrados
   con el sujeto parado sobre una balanza.
5. **Calibración por canal.** Hoy se usa una sola tabla para los tres FSR, porque la variación entre
   unidades que declara el fabricante (±6 %) es menor que la histéresis del propio sensor (~10 %).
   Si se mide y resulta mayor, habrá que una tabla por canal, guardada en NVS.
6. **Compensación por temperatura.** Descartada por ahora: el efecto estimado es ~2 % para ~10 °C,
   menor que la histéresis. Hay un ensayo de 15 minutos propuesto en el informe del 28/10 para
   medirlo en vez de estimarlo. Si diera más del 5 %, se revisa.

El punto 4 es el que le falta al proyecto para que el número tenga significado clínico.

### 7.3 Lo demás del hardware

Casi todo esto también está hecho en `dosimetro_calibrado.ino`: lo que falta es portarlo.

| Qué | En este repo | En el prototipo que anda |
|---|---|---|
| Reloj | `settimeofday` desde BLE, se pierde al reiniciar | **DS3231** por I²C, leído una vez por minuto, con cierre del día a medianoche |
| Alimentación y batería | riel medido por GPIO35, corrección ratiométrica, `leerBateria()` real, aviso y corte con *deep sleep* | LiPo 1S directa al riel por TP4056, **sin regulador**; misma corrección |
| OLED | no existe | SSD1306 por I²C (0x3C), 4 pantallas, **en una tarea del otro núcleo** porque dibujar tarda ~25 ms y rompería la ventana de 20 ms |
| LED RGB y buzzer | funcionan | buzzer activo TMB12A05 directo a GPIO19; falta ver si necesita transistor |
| Pulsadores | uno solo (`PIN_BOTON`) | dos: GPIO32 cambia de pantalla, GPIO33 mantenido 3 s hace la tara |
| `src/placa.h` | pines reales del ESP32 clásico y constantes de alimentación, ya actualizados | el mismo mapa de pines |

El reloj merece una nota. Hoy, si el equipo se reinicia, `horaSincronizada` vuelve a falso, y
**un día sin hora sincronizada no se guarda**, porque no se sabría a qué fecha corresponde. Con el
DS3231 leído al arrancar, eso deja de ser un problema. Es más importante de lo que parece.

---

## 8. Cómo probar sin placa

Es lo que más te va a servir al principio:

```bash
cd firmware
pio test -e native          # 20 tests: dosimetría + protocolo
pio run -e esp32dev         # compila para la placa del prototipo (no la necesita)
pio run -e esp32s3          # solo si la placa final cambia a un S3
```

Y del otro lado, para confirmar que no rompiste el contrato:

```bash
cd app-paciente && flutter test    # 69 tests
cd web-medico && npm test          # 13 tests
```

Para probar contra el equipo real sin app, **nRF Connect** en un celular muestra el servicio y sus
características, y deja escribir a mano.

El guion completo de la demostración punta a punta está en `docs/prueba-en-vivo.md`.

---

## 9. Primeros pasos sugeridos

En este orden, porque cada uno desbloquea al siguiente:

1. **Guardar el episodio, los límites y el peso en NVS** (§5). Es corto, no necesita hardware nuevo
   y arregla que el equipo vuelva a valores de fábrica cuando se queda sin batería.
2. **Mapa de pines** de la placa final en `src/placa.h`, aunque todavía no exista el hardware.
3. **Interfaz `FuenteCarga`**, con `FuentePotenciometro` moviendo ahí el código actual. Sin cambiar
   comportamiento. Los 18 tests tienen que seguir pasando.
4. **Interfaz `Almacen`** con la implementación en RAM, moviendo ahí los dos `std::vector`. Tests
   nuevos en `native` para la implementación en RAM. Sin cambiar comportamiento.
5. **`AlmacenLittleFs`** en `src/`, con la tabla de particiones. Probalo en un devkit antes de que
   llegue la placa: se puede.
6. **DS3231**, que arregla lo del día sin hora.
7. Recién ahí, **`FuenteFsr`** y la calibración, cuando haya electrónica.

Los pasos 3 y 4 son refactors puros: si algún test cambia de resultado, algo se rompió.

---

## 10. Trampas conocidas

- **No toques el protocolo sin actualizar los cinco archivos.** Si hace falta cambiarlo, frená y
  preguntale al grupo: la app y la web ya están desplegadas contra este contrato.
- **No metas `Arduino.h` en `lib/`.** Perdés los tests en la PC, que es lo único que tenés hasta
  que llegue la placa.
- **El subtipo de la partición de LittleFS se llama `spiffs`.** Sí, es confuso.
- **No guardes señal cruda**, por más tentador que sea para depurar. Si necesitás verla, hacelo
  por el puerto serie en un modo de calibración de banco, que nunca escribe en la flash.
- **El paciente no ve %PC.** Vale también para la OLED del equipo, no solo para la app.
- **No le agregues el nombre del paciente al equipo**, por más que simplifique algo. El equipo rota
  entre personas y no puede llevar datos personales (§5).
- **El episodio y los límites tienen que sobrevivir a un reinicio.** Hoy no lo hacen (§5).
- **El acumulado se reinicia a medianoche**, y `AgregadorMinuto` depende de detectar ese salto.
  Si cambiás el cierre del día, mirá `AgregadorMinuto::cerrar`.
- **El historial no se borra al entregarlo.** Solo al cerrar el episodio. Los dos caminos de
  descarga tienen que poder pedir lo mismo cuantas veces quieran.

---

## 11. Dónde está cada cosa

| Necesitás | Andá a |
|---|---|
| Contexto general y reglas | `CLAUDE.md` |
| El contrato BLE | `docs/protocolo-ble.md` |
| Paquetes de ejemplo | `docs/protocolo-vectores.json` |
| Por qué BLE y no WiFi | `docs/decisiones/001-conectividad.md` |
| Por qué el paciente no tiene cuenta | `docs/decisiones/002-identificacion.md` |
| Cuánto entra en la flash | `docs/decisiones/003-almacenamiento.md` |
| Por qué se guarda el historial viejo | `docs/decisiones/004-historial-relesion.md` |
| Cómo se hablan equipo, app y web | `docs/decisiones/005-arquitectura-de-comunicacion.md` |
| Las definiciones del Anexo A | `CLAUDE.md`, sección Definiciones |
| Qué falta en todo el proyecto | `docs/plan-de-avances.md` |
| Cómo correr todo en Windows | `docs/puesta-en-marcha-windows.md` |
