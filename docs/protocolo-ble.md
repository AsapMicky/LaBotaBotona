# Protocolo BLE — v1

Contrato entre el firmware y las apps. Todos los enteros son **little-endian**. Los valores de carga se
transmiten en décimas de %PC (`x10`) para evitar flotantes.

**Servicio:** `6f1a0000-8b3c-4d5e-9a10-2c7e5b3d9f00`
**Nombre anunciado:** `DOSI-<serie>` (ej. `DOSI-0003`)
**MTU:** la app pide 247.

| Característica | UUID | Propiedades | Tamaño |
|---|---|---|---|
| Estado en vivo | `6f1a0001-…` | read, notify (1 Hz) | 8 B |
| Resumen del día | `6f1a0002-…` | read | 28 B |
| Control de historial | `6f1a0003-…` | write | 5 B |
| Datos de historial | `6f1a0004-…` | notify | 2 + 12·n B |
| Configuración | `6f1a0005-…` | read, write | R 13 B / W 6 B |
| Hora | `6f1a0006-…` | write | 6 B |
| Info y episodio | `6f1a0007-…` | read, write | R 32 B / W 16 B |

(Los UUID completos reemplazan `0000` del servicio por el número de la característica.)

## 0001 · Estado en vivo (8 B)
| Offset | Tipo | Campo |
|---|---|---|
| 0 | u8 | versión de protocolo (= 1) |
| 1 | u8 | regimen: 0 sin apoyo, 1 subcarga, 2 en ventana, 3 exceso |
| 2 | u16 | excedencias de hoy |
| 4 | u8 | batería [%] |
| 5 | u8 | flags: b0 cargando, b1 límite pendiente de confirmar, b2 hora no sincronizada, b3 sin episodio |
| 6 | u16 | cumplimiento de hoy ×10 [%] (0xFFFF si todavía no apoyó) |

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

## 0003 / 0004 · Historial (registros por minuto)
**Pedido (write 0003, 5 B):** `u8 op` + `u32 desde` (epoch UTC).
- `op = 1`: enviar todos los registros con `ts ≥ desde`.
- `op = 2`: cancelar.

**Respuesta (notify 0004):** `u16 secuencia` + hasta 15 registros de 12 B. `secuencia = 0xFFFF` con cero
registros marca el final.

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
cierra el episodio y **borra el historial** (devolución del equipo).

## Pendiente para versiones siguientes
- Emparejamiento con passkey (hoy cualquiera en rango puede leer; aceptable en banco, no en uso real).
- Guardar historial en LittleFS (hoy está en RAM en el prototipo).
