# 001 · Bluetooth, Wi-Fi o memoria extraíble

**Estado:** propuesta · **Pedido por:** cátedra (audio, septiembre 2026)

## Opciones
1. **Wi-Fi en el equipo** que sube directo a la nube.
2. **BLE al celular del paciente**, que reenvía a la nube con su propia conexión.
3. **Memoria extraíble** (SD) que el médico lee en la consulta.
4. **Flash interna + descarga por BLE en la consulta** desde la web del médico.

## Análisis
- Wi-Fi en el equipo obliga a configurar la red de cada domicilio (que puede no existir), consume bastante más que BLE
  y agrega credenciales de terceros dentro de un equipo que rota entre pacientes.
- La SD exige abrir la carcasa o dejar una ranura: peor estanqueidad y limpieza en un equipo que se reusa,
  riesgo de pérdida de la tarjeta con datos de salud.
- BLE ya es necesario para la app del paciente, y el celular casi siempre tiene datos móviles.
- La flash interna del ESP32-S3-N16 (16 MB) alcanza para años de agregados por minuto (ver 003).

## Decisión
La **flash interna es la fuente de verdad** y el registro nunca depende de la conectividad.
- **De mínima:** descarga por BLE en la consulta (opción 4). Cumple lo mismo que "sacar la memoria" sin abrir el equipo.
- **De máxima:** la app del paciente sincroniza los resúmenes cuando tiene conexión (opción 2), y el médico ve la
  evolución entre consultas.
- Wi-Fi del equipo queda desactivado.
