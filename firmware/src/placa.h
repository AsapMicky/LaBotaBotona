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
  #define PIN_POT        34    // ADC1: salida de la transimpedancia (o el pote en el simulador)
  #define PIN_RIEL       35    // ADC1: tensión del riel / 2, por el divisor R17/R18 de 100k
  #define PIN_BOTON      33    // SW1 "Menú/OK": tara y confirmación del límite
  #define PIN_BUZZER     19    // buzzer activo TMB12A05, directo al pin
  #define SERIE          "0002"

  // LED RGB de cátodo común, con 220 Ω en serie en cada color.
  #define PIN_LED_R      16
  #define PIN_LED_G      17
  #define PIN_LED_B      18

  // Pines de la cadena real, para cuando se porte el firmware del prototipo.
  #define PIN_MUX_A      25    // selección de canal del CD4051B
  #define PIN_MUX_B      26
  #define PIN_MUX_C      27
  #define PIN_BOTON_A    32    // SW2 "Siguiente": cambia de pantalla en el OLED
  #define PIN_I2C_SDA    21    // DS3231 y OLED SSD1306 comparten el bus
  #define PIN_I2C_SCL    22
#endif

// GPIO que NO se pueden usar en el ESP32 clásico:
//   0, 1, 2, 3, 5, 12, 15 — arranque o puerto serie
//   6 a 11               — los usa la flash interna
// Conectar la salida del op-amp al GPIO1 (TX) ya costó un ESP32 quemado.

// El potenciómetro simula la carga: extremo a extremo = 0 a CARGA_MAX_SIM %PC
#define CARGA_MAX_SIM   60.0f
#define FS_HZ           50

// ---------------- Alimentación ----------------
//
// No hay regulador. El circuito se alimenta directo de la celda LiPo 1S, así que el riel se
// mueve entre 3,2 V (casi descargada) y 4,2 V (recién cargada).
//
// Eso hace que la medición dependa de la batería: la referencia de la transimpedancia sale del
// riel con un divisor, pero el ADC convierte contra una referencia interna fija. Sin corregir,
// una misma carga leería hasta 27 % más con la batería llena, y el equipo marcaría sobrecargas
// que no pasaron. Se corrige por software midiendo el riel con el mismo ADC: el error de
// ganancia de la referencia interna afecta a las dos lecturas por igual y se cancela.
//
// V_CAL_MV es el riel que había durante la calibración. Se obtiene una sola vez, con el equipo
// por USB y la batería desconectada, con el comando `v` del monitor serie.
#define V_CAL_MV        3300
#define SAT_MV          2950   // techo del ADC. Se evalúa sobre el valor CRUDO, antes de corregir
#define BAT_AVISO_MV    (V_CAL_MV - 50)
#define BAT_CORTE_MV    (V_CAL_MV - 150)
#define BAT_CORTE_MS    10000  // sostenido, para que un pico del buzzer no apague el equipo
#define BAT_LLENA_MV    4200
