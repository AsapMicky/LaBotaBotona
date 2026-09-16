#include "dosimetria.h"
#include <algorithm>

namespace dosi {

Dosimetro::Dosimetro(const Limites& lim) : lim_(lim) {}

void Dosimetro::reiniciar() {
  acum_ = Acumulado{};
  // Si el paciente está en medio de una excedencia a medianoche, el evento
  // sigue abierto pero no se vuelve a contar en el día nuevo.
}

void Dosimetro::actualizar(float c, float dt) {
  if (dt <= 0) return;
  const float L = lim_.L, Lmin = lim_.Lmin, Cap = lim_.Capoyo;
  const double dtMin = dt / 60.0;

  if (c > acum_.pico) acum_.pico = c;

  // Dosis de sobrecarga: acumula siempre que C > L
  if (c > L) {
    acum_.dosisSobrecarga += (c - L) * dtMin;
    acum_.tExceso_s += dt;
  }

  const bool apoyo = c > Cap;
  if (apoyo) {
    acum_.tCarga_s += dt;
    if (c < Lmin) {
      acum_.tSub_s += dt;
      acum_.dosisSubcarga += (Lmin - c) * dtMin;
    }
  }

  // Eventos de excedencia con histéresis y retardo
  if (!enEvento_) {
    if (c > L) {
      enEvento_ = true;
      tBajoHist_s_ = 0;
      acum_.excedencias++;
    }
  } else {
    if (c < lim_.histeresis * L) {
      tBajoHist_s_ += dt;
      if (tBajoHist_s_ > lim_.retardoFin_s) enEvento_ = false;
    } else {
      tBajoHist_s_ = 0;
    }
  }

  if (enEvento_)            regimen_ = Regimen::Exceso;
  else if (!apoyo)          regimen_ = Regimen::SinApoyo;
  else if (c < Lmin)        regimen_ = Regimen::Subcarga;
  else                      regimen_ = Regimen::Ventana;
}

void AgregadorMinuto::iniciar(uint32_t ts, const Acumulado& base) {
  actual_ = RegistroMinuto{};
  actual_.ts = ts;
  sumaCarga_ = 0;
  tApoyo_ = 0;
  dosisBase_ = dosisUlt_ = base.dosisSobrecarga;
  excBase_ = excUlt_ = base.excedencias;
}

void AgregadorMinuto::agregar(float c, float dt, const Acumulado& despues, float Capoyo) {
  if (c > Capoyo) {
    sumaCarga_ += c * dt;
    tApoyo_ += dt;
  }
  actual_.cargaPico = std::max(actual_.cargaPico, c);
  dosisUlt_ = despues.dosisSobrecarga;
  excUlt_ = despues.excedencias;
}

RegistroMinuto AgregadorMinuto::cerrar(uint32_t tsNuevo) {
  RegistroMinuto r = actual_;
  r.cargaMedia = tApoyo_ > 0 ? static_cast<float>(sumaCarga_ / tApoyo_) : 0.0f;
  // Si el acumulado se reinició a medianoche, dosisUlt_ < dosisBase_
  r.dosis = static_cast<float>(dosisUlt_ >= dosisBase_ ? dosisUlt_ - dosisBase_ : dosisUlt_);
  uint32_t exc = excUlt_ >= excBase_ ? excUlt_ - excBase_ : excUlt_;
  r.excedencias = static_cast<uint8_t>(exc > 255 ? 255 : exc);
  r.segApoyo = static_cast<uint16_t>(tApoyo_ + 0.5);

  Acumulado base;
  base.dosisSobrecarga = dosisUlt_;
  base.excedencias = excUlt_;
  iniciar(tsNuevo, base);
  return r;
}

}  // namespace dosi
