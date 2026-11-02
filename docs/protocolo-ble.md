# Protocolo BLE — v1

Contrato entre el firmware y las apps. Todos los enteros son **little-endian**. Los valores de carga se
transmiten en décimas de %PC (`x10`) para evitar flotantes.

> **Nota de unidades (31/10/2026).** El prototipo real mide en **gramos**, no en %PC: convierte cada
> canal con una tabla de mV a gramos (calibración del 28/10, ver `docs/avances/`). El pasaje a %PC
> necesita la **calibración global contra balanza, que todavía no se hizo**, porque 3 sensores cubren
> una fracción de la planta y su suma no es la carga total sobre el pie.
>
> **Este contrato no cambia por eso.** El %PC es el destino definido en el Anexo A del anteproyecto, y
> lo que falta es el factor de conversión, no el modelo. Cuando el firmware real implemente BLE, tiene
> que entregar %PC: la conversión es responsabilidad suya, igual que el resto de las métricas
> (`CLAUDE.md`: las métricas se calculan en el microcontrolador).

**Servicio:** `6f1a0000-8b3c-4d5e-9a10-2c7e5b3d9f00`
**Nombre anunciado:** `DOSI-<serie>` (ej. `DOSI-0003`)
**MTU:** la app pide 247.

**Vectores de referencia:** `docs/protocolo-vectores.json` tiene paquetes de ejemplo en hexa con sus
valores. Los verifican `firmware/test/test_protocolo` (codifica y compara bytes) y
`app-paciente/test/vectores_test.dart` (decodifica y compara valores). Cualquier cambio a este documento
va con los vectores, el firmware, la app y los tests en el mismo commit.

| Característica | UUID | Propiedades | Tamaño |
|---|---|---|---|
| Estado en vivo | `6f1a0001-…` | read, notify (1 Hz) | 8 B |
| Resumen del día | `6f1a0002-…` | read | 28 B |
| Control de historial | `6f1a0003-…` | write | 5 B |
| Datos de historial | `6f1a0004-…` | notify | 2 + 12·n B |
| Configuración | `6f1a0005-…` | read, write | R 13 B / W 6 B |
| Hora | `6f1a0006-…` | write | 6 B |
| Info y episodio | `6f1a0007-…` | read, write | R 32 B / W 16 B |
| Resúmenes de días cerrados | `6f1a0008-…` | notify | 2 + 28·n B |

(Los UUID completos reemplazan `0000` del servicio por el número de la característica.)

## 0001 · Estado en vivo (8 B)
| Offset | Tipo | Campo |
|---|---|---|
| 0 | u8 | versión de protocolo (= 1) |
| 1 | u8 | regimen: 0 sin apoyo, 1 subcarga, 2 en ventana, 3 exceso |
| 2 | u16 | excedencias de hoy |
| 4 | u8 | batería [%] |
| 5 | u8 | flags: b0 cargando, b1 límite pendiente de confirmar, b2 hora no sincronizada, b3 sin episodio, b4 sin calibración global |
| 6 | u16 | cumplimiento de hoy ×10 [%] (0xFFFF si todavía no apoyó) |

**`b4 sin calibración global`.** El equipo mide gramos sobre los sensores y los pasa a %PC con un
factor `k`. Ese factor sale de pesar al paciente parado sobre una balanza con la bota puesta; hasta
que eso se haga, el equipo usa un valor provisorio y enciende este bit. La app no lo muestra (el
paciente no ve números), pero **la app lo sube en el bloque `equipo` y la web lo muestra en el
reporte**: sin eso, el médico no puede distinguir una dosis clínica de una que no lo es.

`k` vive en NVS y se borra al cerrar el episodio, porque la calibración es de la persona, no del
equipo.

No incluye la carga instantánea a propósito: el paciente no la ve.
`regimen = 3` se mantiene durante todo el evento de excedencia (con la histéresis del Anexo A), así el semáforo no parpadea.

## 0002 · Resumen del día (28 B)
| Offset | Tipo | Campo |
|---|---|---|
| 0 | u32 | inicio del día (epoch UTC del 00:00 local) |
| 4 | f32 | dosis de sobrecarga [%PC·min] |
| 8 | f32 | dosis de subcarga [%PC·min] |
| 12 | u32 | Tcarga [s] |
| 16 | u32 | Texceso [s] |
| 20 | u32 | Tsub [s] |
| 24 | u16 | carga pico ×10 [%PC] |
| 26 | u16 | excedencias |

Tventana = Tcarga − Texceso − Tsub. Cumplimiento y permanencia se derivan en la app.

## 0003 · Pedidos de descarga
**Pedido (write 0003, 5 B):** `u8 op` + `u32 desde` (epoch UTC).
- `op = 1`: enviar los registros por minuto con `ts ≥ desde` (responde por 0004).
- `op = 2`: cancelar lo que esté en curso.
- `op = 3`: enviar los resúmenes de días ya cerrados con `inicio del día ≥ desde` (responde por 0008).

## 0004 · Datos de historial (registros por minuto)
`u16 secuencia` + hasta 15 registros de 12 B. `secuencia = 0xFFFF` con cero registros marca el final.

## 0008 · Resúmenes de días cerrados
`u16 secuencia` + hasta 8 resúmenes de **28 B, con el mismo formato que 0002**. `secuencia = 0xFFFF`
con cero resúmenes marca el final.

El equipo cierra el día a medianoche local: guarda el acumulado con su `inicio del día` y reinicia.
0002 es siempre el día **en curso**; 0008 son los días **terminados**. Entre los dos, el médico recibe
la serie completa aunque el paciente pase días sin abrir la app, que es la razón de existir de esta
característica: el registro no puede depender de que alguien sincronice a diario.

Un día sin hora sincronizada no se guarda: sin reloj no se sabe a qué fecha corresponde.

**Registro por minuto (12 B):**
| Offset | Tipo | Campo |
|---|---|---|
| 0 | u32 | inicio del minuto (epoch UTC) |
| 4 | u16 | carga media ×10 [%PC] (solo muestras con apoyo; 0 si no apoyó) |
| 6 | u16 | carga pico ×10 [%PC] |
| 8 | u16 | dosis de sobrecarga del minuto ×100 [%PC·min] |
| 10 | u8 | excedencias iniciadas en el minuto |
| 11 | u8 | segundos con apoyo / 4 (0–15) |

## 0005 · Configuración
**Lectura (13 B):** activo `u16 L×10, u16 Lmin×10, u16 peso×10 [kg]` + pendiente (mismos 6 B) + `u8 hay_pendiente`.
**Escritura (6 B):** `u16 L×10, u16 Lmin×10, u16 peso×10`. Queda **pendiente** hasta que se confirma con
pulsación larga en el equipo. Ningún cambio remoto modifica el umbral sin validación presencial.

## 0006 · Hora (6 B)
`u32 epoch UTC` + `i16 offset local [min]` (Argentina: −180). La app la escribe en cada conexión.

## 0007 · Info y episodio
**Lectura (32 B):** `u8 versión protocolo, u8 fw_mayor, u8 fw_menor, u8 fw_parche, char[12] serie, char[16] episodio`
(el episodio son los primeros 16 hex del UUID, o ceros si no hay).
**Escritura (16 B):** `char[16] episodio`. Solo la hace la web del médico al dar de alta. Escribir 16 ceros
cierra el episodio y **borra el historial y los resúmenes** (devolución del equipo).

El episodio es **el único identificador que guarda el equipo**, y es la clave que une a los tres:
el médico se lo escribe acá, el QR se lo pasa a la app, y la app lo usa para verificar que la
ortesis que está leyendo sea la de su paciente antes de subir nada. Ni nombre ni documento van al
equipo: rota entre pacientes (decisión 002, Ley 25.326).

**El equipo tiene que recordar el episodio y los límites entre reinicios.** Si los pierde al
quedarse sin batería, vuelve a los valores de fábrica y queda midiendo contra un límite que nadie
prescribió. Va en NVS, no en RAM.

## Pendiente para versiones siguientes
- **Que el firmware real implemente BLE.** `dosimetro_calibrado.ino` mide, calcula, guarda y muestra,
  pero no habla BLE: es lo que falta para cerrar el circuito con la app y la web.
- **El factor de gramos a %PC** (calibración global contra balanza). Sin eso el equipo no puede
  completar los campos de este protocolo con valores correctos.
- Emparejamiento con passkey (hoy cualquiera en rango puede leer; aceptable en banco, no en uso real).
- Guardar historial en LittleFS (en el esqueleto de este repo está en RAM; el prototipo real ya
  escribe en LittleFS, con otro formato de registro: 18 B/min, ver `docs/decisiones/003`).
- **Persistencia real.** Hoy tanto los registros por minuto como los resúmenes de días cerrados
  viven en RAM: sobreviven a la medianoche y a que el paciente no abra la app, pero no a un
  reinicio ni a que se agote la batería. Pasarlos a LittleFS es la tarea del Avance 4.
