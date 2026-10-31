# Modelo de datos

```
medico 1───n paciente 1───n episodio n───0..1 dispositivo
                               │
                               ├──n indicacion      (historia de la prescripción)
                               ├──n resumen_diario   (1 por día)
                               └──n registro_minuto  (perfil intradiario)
```

- **Paciente**: `id` (UUID) + `codigo` legible (`P-000123`). El DNI se guarda como dato de referencia, nunca como clave
  (evita duplicados: mismo número con distinto sexo registral, errores de tipeo, extranjeros).
- **Episodio**: un tratamiento concreto. Miembro (izquierdo/derecho), lesión, fecha de cirugía, límites L y Lmin,
  peso corporal, fechas de inicio y fin, dispositivo asignado y `token_sync` (lo usa la app del paciente para subir datos
  sin tener cuenta). Una re-lesión es **otro episodio** del mismo paciente.
- **Indicación**: qué se le prescribió al paciente y desde cuándo. El episodio guarda la indicación
  **vigente** (es la que se le envía a la ortesis); la tabla guarda la historia. En rehabilitación la carga
  permitida se progresa y el peso de la persona cambia, así que esto no es opcional: sin la historia, los
  días viejos quedarían medidos contra un límite que ya no se ve por ningún lado. La escribe un trigger, así
  que ningún camino de la app puede olvidarse de registrarla.
- **Dispositivo**: número de serie y versión de firmware. Como máximo un episodio abierto por dispositivo.
- **Estado del equipo** (`episodios.equipo_visto`): lo último que la ortesis informó de sí misma cuando
  alguien la leyó. Sirve para confirmar que la indicación llegó al equipo y con qué peso está calculando.
- **Señales de la app** (`episodios.vinculada_en` y `ultima_sincronizacion`): cuándo el paciente escaneó
  el QR y cuándo habló por última vez con el servidor. Las escribe `subir-datos`, no la app, así que
  valen también para los teléfonos con una versión vieja instalada.
- **Resumen diario / registro por minuto**: lo que baja del equipo, tal cual el protocolo.

**Unidades.** Las cargas y las dosis se guardan en **%PC** y **%PC·min**, como define el Anexo A. El
prototipo hoy mide en gramos y el puente es la calibración global contra balanza, que está pendiente
(ver `docs/avances/`). El esquema no cambia por eso: lo que falta es el factor, no el modelo. Tener en
cuenta, para cuando llegue ese momento, que `episodios.limite_sup` es `numeric(4,1)` con un
`check (<= 100)`: está dimensionado para %PC y no aceptaría un valor en gramos.

## Quién accede a qué
| Rol | Cuenta | Ve |
|---|---|---|
| Médico | sí (email) | solo sus pacientes y episodios |
| Paciente | no | su propio episodio, vía el equipo y el token del QR |
| Dispositivo | no | nada personal: solo el ID de episodio |

## Flujo de alta y devolución
1. El médico crea el paciente (o lo busca) y abre un episodio con los límites.
2. Asigna una ortesis: la web escribe el ID de episodio en el equipo por BLE y muestra un QR con el `token_sync`.
3. El paciente escanea el QR con la app: queda vinculada al equipo y al episodio.
4. En la devolución el médico cierra el episodio: se hace una última descarga y se borra el equipo.
