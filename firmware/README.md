# Firmware

**Acá hay dos firmwares distintos y conviene no confundirlos.**

| | En este repo | `dosimetro_calibrado.ino` |
|---|---|---|
| Dónde | `firmware/`, PlatformIO | Arduino IDE, **fuera del repo** |
| Fuente de carga | potenciómetro simulado | 3 FSR 402 reales, calibrados en gramos |
| Dosimetría | la final, con 20 tests | la propia, validada a mano |
| Protocolo BLE | completo, verificado contra vectores | **no tiene** |
| Reloj, flash, pantalla | no | DS3231, LittleFS y OLED andando |

Ninguno de los dos está terminado: a este le falta el hardware, y a aquel le falta el BLE. **El
trabajo que sigue es unirlos**, no escribir uno nuevo.

## Qué hay acá

- `lib/dosimetria` — integra la dosis a 50 Hz, agrega por minuto y detecta excedencias con la
  histéresis del Anexo A. C++ puro, sin Arduino, corre en la PC.
- `lib/protocolo` — serializa los paquetes BLE de `docs/protocolo-ble.md`.
- `src/main.cpp` — servidor BLE, semáforo, botón y cierre del día, con la carga simulada.
- `src/placa.h` — pines. Ya tiene los del ESP32 clásico del prototipo.

## Comandos

```bash
pio test -e native
```

Corre los 20 tests de dosimetría y protocolo sin necesidad de placa. Es lo que verifica la CI.

```bash
pio run -e esp32dev
```

Compila para el ESP32 clásico, que es la placa del prototipo. El entorno `esp32s3` quedó por si la
placa final cambia.

> **Hoy esta compilación falla**, por un error anterior a los cambios de hardware: `proto::Ajustes`
> tiene inicializadores por miembro, y el core de Arduino para ESP32 compila con `-std=gnu++11`, que
> pisa el `-std=gnu++17` de `platformio.ini`. En C++11 eso impide la inicialización con llaves de
> `src/main.cpp:97`. Los tests del entorno `native` no lo notan porque no compilan `main.cpp`.

## Antes de tocar nada

Leer `docs/avances/` (los informes del hardware real) y `docs/firmware-placa-real.md` (el briefing,
ya corregido con la cadena definitiva).
