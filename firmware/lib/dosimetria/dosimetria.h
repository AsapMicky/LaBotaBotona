// Cálculo del indicador de cuidado (Anexo A del anteproyecto).
// C++ puro: no depende de Arduino, se testea en la PC con `pio test -e native`.
#pragma once
#include <cstdint>

namespace dosi {

enum class Regimen : uint8_t { SinApoyo = 0, Subcarga = 1, Ventana = 2, Exceso = 3 };

// Las unidades son %PC, como define el Anexo A. El prototipo real todavía trabaja en gramos
// (ver docs/avances/): usa 1000 g como límite provisorio y 150 g como umbral de apoyo, que es
// donde el FSR empieza a responder. La equivalencia entre esos números y estos depende de la
// calibración global contra balanza, que está pendiente. No cambiar los defaults por eso.
struct Limites {
  float L = 20.0f;        // límite superior [%PC]
  float Lmin = 0.0f;      // límite inferior [%PC]; 0 si el protocolo no lo prescribe
  float Capoyo = 5.0f;    // umbral de apoyo efectivo [%PC]
  float histeresis = 0.9f;        // la excedencia termina bajo histeresis·L
  float retardoFin_s = 2.0f;      // ...sostenido durante este tiempo
};

struct Acumulado {
  double dosisSobrecarga = 0;  // [%PC·min]
  double dosisSubcarga = 0;    // [%PC·min]
  double tCarga_s = 0;
  double tExceso_s = 0;
  double tSub_s = 0;
  float pico = 0;              // [%PC]
  uint32_t excedencias = 0;

  double tVentana_s() const { return tCarga_s - tExceso_s - tSub_s; }
  // Devuelven negativo si todavía no hubo apoyo.
  double cumplimiento() const { return tCarga_s > 0 ? (1.0 - tExceso_s / tCarga_s) * 100.0 : -1.0; }
  double permanencia() const { return tCarga_s > 0 ? tVentana_s() / tCarga_s * 100.0 : -1.0; }
};

class Dosimetro {
 public:
  explicit Dosimetro(const Limites& lim = Limites{});

  // Integra una muestra. carga en %PC, dt en segundos.
  void actualizar(float carga, float dt_s);

  void setLimites(const Limites& lim) { lim_ = lim; }
  const Limites& limites() const { return lim_; }

  const Acumulado& acumulado() const { return acum_; }
  void reiniciar();  // p. ej. a medianoche

  // Régimen para el semáforo: durante una excedencia devuelve Exceso aunque
  // la carga haya bajado un poco (histéresis), así no parpadea.
  Regimen regimen() const { return regimen_; }
  bool enExcedencia() const { return enEvento_; }

 private:
  Limites lim_;
  Acumulado acum_;
  Regimen regimen_ = Regimen::SinApoyo;
  bool enEvento_ = false;
  float tBajoHist_s_ = 0;
};

// Agregador de registros por minuto (docs/protocolo-ble.md, 12 B).
struct RegistroMinuto {
  uint32_t ts = 0;
  float cargaMedia = 0;
  float cargaPico = 0;
  float dosis = 0;
  uint8_t excedencias = 0;
  uint16_t segApoyo = 0;
};

class AgregadorMinuto {
 public:
  // Alimentar con la misma muestra y el acumulado posterior a actualizar().
  void agregar(float carga, float dt_s, const Acumulado& despues, float Capoyo);
  // Cierra el minuto en curso y lo devuelve; empieza uno nuevo con ts.
  RegistroMinuto cerrar(uint32_t tsNuevo);
  void iniciar(uint32_t ts, const Acumulado& base);

 private:
  RegistroMinuto actual_;
  double sumaCarga_ = 0;
  double tApoyo_ = 0;
  double dosisBase_ = 0;
  uint32_t excBase_ = 0;
  double dosisUlt_ = 0;
  uint32_t excUlt_ = 0;
};

}  // namespace dosi
