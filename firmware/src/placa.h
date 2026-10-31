// Pines según la placa.
//
// El prototipo real es un ESP32 clásico (ESP-WROOM-32, DevKit de 38 pines). Los pines de abajo
// salen del informe del 22/10 (ver docs/avances/). El código de este repo todavía lee un
// potenciómetro: la cadena de FSR vive en `alarma_con_display.ino`, fuera del repo.
#pragma once

#if defined(PLACA_S3)
  // Alternativa si la placa final termina siendo un S3. No es la que está armada.
  #define PIN_POT        4     // ADC1_CH3
  #define PIN_BOTON      0     // BOOT: pulsación larga confirma el límite
  #define PIN_BUZZER     5
  #define PIN_NEOPIXEL   48    // LED RGB integrado del devkit S3
  #define SERIE          "0001"

#else  // ESP32 clásico (ESP-WROOM-32): la placa del prototipo
  // Entrada del ADC. En el simulador le entra un potenciómetro; en la cadena real le entra
  // la salida del MCP6002, que a su vez recibe el canal que seleccionó el CD4051B.
  #define PIN_POT        34
  #define PIN_BOTON      33    // botón B: mantenido 3 s hace la tara
  #define PIN_BUZZER     19    // buzzer activo TMB12A05, directo al pin
  #define PIN_LED        2     // LED de la placa. OJO: el RGB del prototipo está en otro pin,
                               // que todavía no quedó documentado. Ver nota de abajo.
  #define SERIE          "0002"

  // Pines de la cadena real, para cuando se porte el firmware del prototipo.
  #define PIN_MUX_A      25    // selección de canal del CD4051B
  #define PIN_MUX_B      26
  #define PIN_MUX_C      27
  #define PIN_BOTON_A    32    // cambia de pantalla en el OLED
#endif

// GPIO que NO se pueden usar en el ESP32 clásico:
//   0, 1, 2, 3, 5, 12, 15 — arranque o puerto serie
//   6 a 11               — los usa la flash interna
// Conectar la salida del op-amp al GPIO1 (TX) ya costó un ESP32 quemado.

// El potenciómetro simula la carga: extremo a extremo = 0 a CARGA_MAX_SIM %PC
#define CARGA_MAX_SIM   60.0f
#define FS_HZ           50

// PENDIENTE (no inventar, confirmar con quien armó el prototipo):
//   - el pin del LED RGB;
//   - los pines de I²C del DS3231 y el OLED (el ESP32 clásico usa 21/22 por defecto en Arduino).
