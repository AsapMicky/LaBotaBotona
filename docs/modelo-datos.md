# Modelo de datos

```
medico 1───n paciente 1───n episodio n───0..1 dispositivo
                               │
                               ├──n resumen_diario   (1 por día)
                               └──n registro_minuto  (perfil intradiario)
```

- **Paciente**: `id` (UUID) + `codigo` legible (`P-000123`). El DNI se guarda como dato de referencia, nunca como clave
  (evita duplicados: mismo número con distinto sexo registral, errores de tipeo, extranjeros).
- **Episodio**: un tratamiento concreto. Miembro (izquierdo/derecho), lesión, fecha de cirugía, límites L y Lmin,
  peso corporal, fechas de inicio y fin, dispositivo asignado y `token_sync` (lo usa la app del paciente para subir datos
  sin tener cuenta). Una re-lesión es **otro episodio** del mismo paciente.
- **Dispositivo**: número de serie y versión de firmware. Como máximo un episodio abierto por dispositivo.
- **Resumen diario / registro por minuto**: lo que baja del equipo, tal cual el protocolo.

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
