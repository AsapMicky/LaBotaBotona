// Pines según la placa. Ajustar al armar el prototipo.
#pragma once

#if defined(PLACA_S3)
  #define PIN_POT        4     // ADC1_CH3
  #define PIN_BOTON      0     // BOOT: pulsación larga confirma el límite
  #define PIN_BUZZER     5
  #define PIN_NEOPIXEL   48    // LED RGB integrado del devkit S3
  #define SERIE          "0001"
#else  // NodeMCU ESP32 (WROOM-32)
  #define PIN_POT        34
  #define PIN_BOTON      0
  #define PIN_BUZZER     25
  #define PIN_LED        2
  #define SERIE          "0002"
#endif

// El potenciómetro simula la carga: extremo a extremo = 0 a CARGA_MAX_SIM %PC
#define CARGA_MAX_SIM   60.0f
#define FS_HZ           50
