# Firmware de la placa real — briefing

Este documento es para quien (persona o Claude Code) tome el firmware cuando exista la placa.
Explica **por qué** el software está como está, qué parte ya funciona y no hay que tocar, y qué
falta construir. Leelo entero antes de escribir una línea: hay varias decisiones que parecen
arbitrarias y no lo son.

Contexto general del proyecto: `CLAUDE.md` en la raíz. Este documento no lo reemplaza.

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

## 5. Cómo está organizado el firmware, y por qué

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

## 6. Lo que hay que construir

### 6.1 Guardar en la flash (LittleFS) — lo más importante

Hoy el historial y los resúmenes viven en **RAM**:

```cpp
static std::vector<RegistroMinuto> historial;   // 3 días
static std::vector<ResumenDia> resumenes;       // 400 días
```

Sobreviven a la medianoche y a que el paciente no abra la app, que era el agujero grande. **No
sobreviven a un reinicio ni a que se agote la batería.** El equipo tiene que ser autónomo: esa es
parte de la consigna, y es el motivo de que la flash sea la fuente de verdad.

**Cuánto ocupa** (de `docs/decisiones/003`):

| Qué | Tamaño | Por día | Por año |
|---|---|---|---|
| Registro por minuto | 12 B | 17,3 KB | 6,3 MB |
| Resumen diario | 28 B | 28 B | 10 KB |

Con una partición de 10 MB entran más de 1,5 años de uso continuo. El ESP32-S3-WROOM-1-N16 tiene
16 MB de flash.

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

- `/dias/AAAAMMDD.bin` — registros de 12 B del día, uno atrás del otro.
- `/resumenes.bin` — resúmenes de 28 B, uno atrás del otro.

Así, "recorrer desde una fecha" es abrir los archivos que correspondan, sin índices ni borrados en
el medio. Borrar un día viejo es borrar un archivo.

**Particiones.** Hace falta una tabla propia; la que trae PlatformIO por defecto no deja espacio.
Creá `firmware/particiones.csv`:

```
# Name,     Type, SubType, Offset,   Size,     Flags
nvs,        data, nvs,     0x9000,   0x5000,
otadata,    data, ota,     0xe000,   0x2000,
app0,       app,  ota_0,   0x10000,  0x400000,
littlefs,   data, spiffs,  0x410000, 0xBF0000,
```

y en `platformio.ini`, en el entorno `esp32s3`:

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

### 6.2 Leer los sensores de verdad

Hoy:

```cpp
static float leerCarga() {
  int crudo = analogRead(PIN_POT);
  return crudo / 4095.0f * CARGA_MAX_SIM;
}
```

La cadena real es: **8 × FSR 402 + NTC → ADG708 (multiplexor) → OPA2333 (transimpedancia) →
ADS1115 (ADC de 16 bits, I²C) → ESP32-S3**.

Aplicá el mismo patrón que con el almacenamiento: una interfaz `FuenteCarga` con
`FuentePotenciometro` (la de hoy, para seguir probando sin plantilla) y `FuenteFsr` (la nueva).
Así se cambia una clase sin tocar ni la dosimetría ni el BLE.

**Lo que hay que resolver, en orden:**

1. **Presupuesto de tiempo.** La dosimetría corre a 50 Hz. Con 8 canales multiplexados son 400
   conversiones por segundo. El ADS1115 llega a 860 muestras por segundo, o sea 1,16 ms por
   conversión: 8 canales son 9,3 ms, y quedan unos 10 ms de margen por ciclo. **Es ajustado.**
   Tené en cuenta el tiempo de establecimiento después de conmutar el multiplexor. El NTC no hace
   falta leerlo a 50 Hz: una vez por segundo alcanza y de paso libera tiempo.
2. **De fuerza a %PC.** El dosímetro trabaja en porcentaje del peso corporal. El peso llega por
   BLE en la característica de configuración y hoy se guarda en `pesoActivo_kg` **sin usarse**,
   porque el potenciómetro simula %PC directamente. La fuente real tiene que hacer la cuenta:
   sumar las fuerzas de los 8 canales en kg y dividir por `pesoActivo_kg`.
3. **Calibración por canal.** Los FSR 402 varían mucho entre unidades. Hay que calibrar cada canal
   contra pesas patrón y guardar los coeficientes (en NVS, no en LittleFS). Sin esto, el número no
   significa nada.
4. **Deriva del cero.** Es el foco de ingeniería del proyecto: el FSR deriva bajo carga sostenida
   y tiene histéresis. Hace falta seguimiento de línea de base. Pensalo con tests primero, con
   perfiles sintéticos, como ya se hizo con la dosimetría: es la única forma de verificarlo sin
   estar parado arriba de la plantilla.
5. **Compensación por temperatura** con el NTC, si llegan los tiempos.

Los puntos 3, 4 y 5 son el corazón del trabajo de Instrumentación. Los puntos 1 y 2 son plomería.

### 6.3 Lo demás del hardware

| Qué | Hoy | Falta |
|---|---|---|
| Reloj | `settimeofday` desde BLE, se pierde al reiniciar | leer el **DS3231** al arrancar |
| Batería | `leerBateria()` devuelve 100 fijo | divisor resistivo + curva de LiPo |
| OLED | no existe | pantalla local, sin mostrar %PC al paciente |
| LED RGB y buzzer | funcionan | ajustar pines de la placa final |
| Pulsadores | uno solo (`PIN_BOTON`) | la placa final tiene dos |
| `src/placa.h` | pines del devkit | mapa de pines de la placa real |

El reloj merece una nota. Hoy, si el equipo se reinicia, `horaSincronizada` vuelve a falso, y
**un día sin hora sincronizada no se guarda**, porque no se sabría a qué fecha corresponde. Con el
DS3231 leído al arrancar, eso deja de ser un problema. Es más importante de lo que parece.

---

## 7. Cómo probar sin placa

Es lo que más te va a servir al principio:

```bash
cd firmware
pio test -e native          # 18 tests: dosimetría + protocolo
pio run -e esp32s3          # compila para la placa (no la necesita)
pio run -e esp32dev         # compila para el NodeMCU del simulador
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

## 8. Primeros pasos sugeridos

En este orden, porque cada uno desbloquea al siguiente:

1. **Mapa de pines** de la placa final en `src/placa.h`, aunque todavía no exista el hardware.
2. **Interfaz `FuenteCarga`**, con `FuentePotenciometro` moviendo ahí el código actual. Sin cambiar
   comportamiento. Los 18 tests tienen que seguir pasando.
3. **Interfaz `Almacen`** con la implementación en RAM, moviendo ahí los dos `std::vector`. Tests
   nuevos en `native` para la implementación en RAM. Sin cambiar comportamiento.
4. **`AlmacenLittleFs`** en `src/`, con la tabla de particiones. Probalo en un devkit antes de que
   llegue la placa: se puede.
5. **DS3231**, que arregla lo del día sin hora.
6. Recién ahí, **`FuenteFsr`** y la calibración, cuando haya electrónica.

Los pasos 2 y 3 son refactors puros: si algún test cambia de resultado, algo se rompió.

---

## 9. Trampas conocidas

- **No toques el protocolo sin actualizar los cinco archivos.** Si hace falta cambiarlo, frená y
  preguntale al grupo: la app y la web ya están desplegadas contra este contrato.
- **No metas `Arduino.h` en `lib/`.** Perdés los tests en la PC, que es lo único que tenés hasta
  que llegue la placa.
- **El subtipo de la partición de LittleFS se llama `spiffs`.** Sí, es confuso.
- **No guardes señal cruda**, por más tentador que sea para depurar. Si necesitás verla, hacelo
  por el puerto serie en un modo de calibración de banco, que nunca escribe en la flash.
- **El paciente no ve %PC.** Vale también para la OLED del equipo, no solo para la app.
- **El acumulado se reinicia a medianoche**, y `AgregadorMinuto` depende de detectar ese salto.
  Si cambiás el cierre del día, mirá `AgregadorMinuto::cerrar`.
- **El historial no se borra al entregarlo.** Solo al cerrar el episodio. Los dos caminos de
  descarga tienen que poder pedir lo mismo cuantas veces quieran.

---

## 10. Dónde está cada cosa

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
