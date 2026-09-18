// Simulador del dosímetro: la carga sale de un potenciómetro.
// Todo lo demás (dosis, semáforo, protocolo BLE) es el código definitivo.
#include <Arduino.h>
#include <NimBLEDevice.h>
#include <sys/time.h>
#include <vector>
#include "placa.h"
#include "dosimetria.h"
#include "protocolo.h"

using namespace dosi;

// ---------------- Estado global ----------------
static Dosimetro dosimetro;
static AgregadorMinuto agregador;
static std::vector<RegistroMinuto> historial;   // TODO(avance 4): LittleFS
static const size_t HIST_MAX = 1440 * 3;        // 3 días en RAM

// Resúmenes de días ya cerrados (característica 0008). El día en curso no está acá:
// ese sale de 0002 a partir del acumulado vivo. El equipo tiene que poder pasar días
// sin ver un celular y no perder nada.
struct ResumenDia {
  uint32_t inicioDia;
  Acumulado acum;
};
static std::vector<ResumenDia> resumenes;       // TODO(avance 4): LittleFS
static const size_t RESUMENES_MAX = 400;        // más de un año de tratamiento

static Limites limitePendiente;
static bool hayPendiente = false;
static float pesoActivo_kg = 70.0f, pesoPendiente_kg = 70.0f;
static bool horaSincronizada = false;
static int16_t offsetLocal_min = -180;
static char episodio[16] = {0};

static NimBLECharacteristic* chEstado, *chResumen, *chHistDatos, *chConfig, *chInfo, *chResumenes;
static bool clienteConectado = false;

// Pedidos pendientes de envío (los atiende loop, no el callback)
static volatile bool histPedido = false;
static uint32_t histDesde = 0;
static volatile bool resPedido = false;
static uint32_t resDesde = 0;

// ---------------- Utilidades ----------------
static uint32_t ahoraEpoch() { return static_cast<uint32_t>(time(nullptr)); }
static uint32_t minutoActual() { return ahoraEpoch() / 60 * 60; }
static uint32_t inicioDiaLocal() {
  int64_t local = static_cast<int64_t>(ahoraEpoch()) + offsetLocal_min * 60;
  return static_cast<uint32_t>(local / 86400 * 86400 - offsetLocal_min * 60);
}
static bool sinEpisodio() {
  for (char c : episodio) if (c != 0) return false;
  return true;
}
static uint8_t leerBateria() { return 100; }  // TODO: divisor al ADS1115

static float leerCarga() {
  // TODO(avance 4): reemplazar por barrido ADG708 + ADS1115 + calibración + línea de base
  int crudo = analogRead(PIN_POT);
  return crudo / 4095.0f * CARGA_MAX_SIM;
}

static void mostrarSemaforo(Regimen r) {
  uint8_t R = 0, G = 0, B = 0;
  switch (r) {
    case Regimen::SinApoyo: R = 0;  G = 0;  B = 8;  break;   // tenue
    case Regimen::Subcarga: R = 20; G = 20; B = 0;  break;
    case Regimen::Ventana:  R = 0;  G = 30; B = 10; break;
    case Regimen::Exceso:   R = 40; G = 12; B = 0;  break;   // ámbar
  }
#if defined(PIN_NEOPIXEL)
  neopixelWrite(PIN_NEOPIXEL, R, G, B);
#else
  digitalWrite(PIN_LED, r == Regimen::Exceso ? HIGH : LOW);
#endif
}

// ---------------- Paquetes ----------------
static void publicarEstado() {
  uint8_t flags = 0;
  if (hayPendiente) flags |= proto::LIMITE_PENDIENTE;
  if (!horaSincronizada) flags |= proto::SIN_HORA;
  if (sinEpisodio()) flags |= proto::SIN_EPISODIO;
  uint8_t b[proto::TAM_ESTADO];
  proto::codificarEstado(b, dosimetro.regimen(), dosimetro.acumulado(), leerBateria(), flags);
  chEstado->setValue(b, sizeof b);
  if (clienteConectado) chEstado->notify();

  uint8_t r[proto::TAM_RESUMEN];
  proto::codificarResumen(r, inicioDiaLocal(), dosimetro.acumulado());
  chResumen->setValue(r, sizeof r);
}

static void publicarConfig() {
  uint8_t b[13];
  const Limites& a = dosimetro.limites();
  proto::put16(b, proto::x10(a.L));
  proto::put16(b + 2, proto::x10(a.Lmin));
  proto::put16(b + 4, proto::x10(pesoActivo_kg));
  proto::put16(b + 6, proto::x10(limitePendiente.L));
  proto::put16(b + 8, proto::x10(limitePendiente.Lmin));
  proto::put16(b + 10, proto::x10(pesoPendiente_kg));
  b[12] = hayPendiente;
  chConfig->setValue(b, sizeof b);
}

static void publicarInfo() {
  uint8_t b[32] = {0};
  b[0] = proto::VERSION; b[1] = FW_MAYOR; b[2] = FW_MENOR; b[3] = FW_PARCHE;
  strncpy(reinterpret_cast<char*>(b + 4), SERIE, 12);
  memcpy(b + 16, episodio, 16);
  chInfo->setValue(b, sizeof b);
}

static void enviarHistorial() {
  uint8_t paquete[2 + proto::REGISTROS_POR_PAQUETE * proto::TAM_REGISTRO];
  uint16_t seq = 0;
  size_t n = 0;
  for (const auto& r : historial) {
    if (r.ts < histDesde) continue;
    proto::codificarRegistro(paquete + 2 + n * proto::TAM_REGISTRO, r);
    if (++n == proto::REGISTROS_POR_PAQUETE) {
      proto::put16(paquete, seq++);
      chHistDatos->setValue(paquete, 2 + n * proto::TAM_REGISTRO);
      chHistDatos->notify();
      n = 0;
      delay(8);
      if (!histPedido || !clienteConectado) return;  // cancelado
    }
  }
  if (n) {
    proto::put16(paquete, seq++);
    chHistDatos->setValue(paquete, 2 + n * proto::TAM_REGISTRO);
    chHistDatos->notify();
    delay(8);
  }
  proto::put16(paquete, proto::SEQ_FIN);
  chHistDatos->setValue(paquete, 2);
  chHistDatos->notify();
}

static void enviarResumenes() {
  uint8_t paquete[2 + proto::RESUMENES_POR_PAQUETE * proto::TAM_RESUMEN];
  uint16_t seq = 0;
  size_t n = 0;
  for (const auto& r : resumenes) {
    if (r.inicioDia < resDesde) continue;
    proto::codificarResumen(paquete + 2 + n * proto::TAM_RESUMEN, r.inicioDia, r.acum);
    if (++n == proto::RESUMENES_POR_PAQUETE) {
      proto::put16(paquete, seq++);
      chResumenes->setValue(paquete, 2 + n * proto::TAM_RESUMEN);
      chResumenes->notify();
      n = 0;
      delay(8);
      if (!resPedido || !clienteConectado) return;  // cancelado
    }
  }
  if (n) {
    proto::put16(paquete, seq++);
    chResumenes->setValue(paquete, 2 + n * proto::TAM_RESUMEN);
    chResumenes->notify();
    delay(8);
  }
  proto::put16(paquete, proto::SEQ_FIN);
  chResumenes->setValue(paquete, 2);
  chResumenes->notify();
}

// Cierra el día: guarda el acumulado con su fecha y arranca uno nuevo.
// Sin hora sincronizada no se guarda: no se sabría a qué día corresponde.
static void cerrarDia(uint32_t inicioDia) {
  if (!horaSincronizada) return;
  if (resumenes.size() >= RESUMENES_MAX) resumenes.erase(resumenes.begin());
  resumenes.push_back({inicioDia, dosimetro.acumulado()});
}

// ---------------- Callbacks BLE ----------------
class ServidorCB : public NimBLEServerCallbacks {
  void onConnect(NimBLEServer*) override { clienteConectado = true; }
  void onDisconnect(NimBLEServer*) override {
    clienteConectado = false;
    histPedido = false;
    resPedido = false;
    NimBLEDevice::startAdvertising();
  }
};

class EscrituraCB : public NimBLECharacteristicCallbacks {
  void onWrite(NimBLECharacteristic* c) override {
    NimBLEAttValue v = c->getValue();
    const uint8_t* d = v.data();
    size_t n = v.length();
    std::string uuid = c->getUUID().toString();

    if (uuid == proto::UUID_HIST_CTRL && n == 5) {
      if (d[0] == proto::OP_HISTORIAL) { histDesde = proto::get32(d + 1); histPedido = true; }
      else if (d[0] == proto::OP_CANCELAR) { histPedido = false; resPedido = false; }
      else if (d[0] == proto::OP_RESUMENES) { resDesde = proto::get32(d + 1); resPedido = true; }
    } else if (uuid == proto::UUID_CONFIG && n == 6) {
      limitePendiente = dosimetro.limites();
      limitePendiente.L = proto::get16(d) / 10.0f;
      limitePendiente.Lmin = proto::get16(d + 2) / 10.0f;
      pesoPendiente_kg = proto::get16(d + 4) / 10.0f;
      hayPendiente = true;
      publicarConfig();
    } else if (uuid == proto::UUID_HORA && n == 6) {
      timeval tv{static_cast<time_t>(proto::get32(d)), 0};
      settimeofday(&tv, nullptr);
      offsetLocal_min = static_cast<int16_t>(proto::get16(d + 4));
      horaSincronizada = true;
      agregador.iniciar(minutoActual(), dosimetro.acumulado());
    } else if (uuid == proto::UUID_INFO && n == 16) {
      memcpy(episodio, d, 16);
      if (sinEpisodio()) {          // devolución del equipo
        historial.clear();
        resumenes.clear();
        dosimetro.reiniciar();
      }
      publicarInfo();
    }
  }
};

static void iniciarBLE() {
  NimBLEDevice::init(std::string("DOSI-") + SERIE);
  NimBLEDevice::setMTU(247);
  NimBLEServer* srv = NimBLEDevice::createServer();
  srv->setCallbacks(new ServidorCB());
  NimBLEService* s = srv->createService(proto::UUID_SERVICIO);
  static EscrituraCB cb;

  chEstado    = s->createCharacteristic(proto::UUID_ESTADO, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::NOTIFY);
  chResumen   = s->createCharacteristic(proto::UUID_RESUMEN, NIMBLE_PROPERTY::READ);
  auto* ctrl  = s->createCharacteristic(proto::UUID_HIST_CTRL, NIMBLE_PROPERTY::WRITE);
  chHistDatos = s->createCharacteristic(proto::UUID_HIST_DATOS, NIMBLE_PROPERTY::NOTIFY);
  chConfig    = s->createCharacteristic(proto::UUID_CONFIG, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE);
  auto* hora  = s->createCharacteristic(proto::UUID_HORA, NIMBLE_PROPERTY::WRITE);
  chInfo      = s->createCharacteristic(proto::UUID_INFO, NIMBLE_PROPERTY::READ | NIMBLE_PROPERTY::WRITE);
  chResumenes = s->createCharacteristic(proto::UUID_RESUMENES, NIMBLE_PROPERTY::NOTIFY);

  for (auto* c : {ctrl, chConfig, hora, chInfo}) c->setCallbacks(&cb);
  s->start();

  NimBLEAdvertising* adv = NimBLEDevice::getAdvertising();
  adv->addServiceUUID(proto::UUID_SERVICIO);
  adv->setScanResponse(true);
  adv->start();
}

// ---------------- Setup / loop ----------------
void setup() {
  Serial.begin(115200);
  pinMode(PIN_BOTON, INPUT_PULLUP);
  pinMode(PIN_BUZZER, OUTPUT);
#if !defined(PIN_NEOPIXEL)
  pinMode(PIN_LED, OUTPUT);
#endif
  analogReadResolution(12);

  Limites lim;
  lim.L = 20.0f;
  lim.Lmin = 10.0f;
  dosimetro.setLimites(lim);
  limitePendiente = lim;

  iniciarBLE();
  publicarConfig();
  publicarInfo();
  agregador.iniciar(minutoActual(), dosimetro.acumulado());
  Serial.println("Dosimetro (simulador con potenciometro) listo");
}

void loop() {
  static uint32_t tMuestra = 0, tEstado = 0, tBoton = 0;
  static uint32_t minutoEnCurso = minutoActual();
  static uint32_t diaEnCurso = inicioDiaLocal();
  static bool excPrevio = false;
  const uint32_t ahora = millis();

  if (ahora - tMuestra >= 1000 / FS_HZ) {
    const float dt = (ahora - tMuestra) / 1000.0f;
    tMuestra = ahora;
    const float c = leerCarga();
    dosimetro.actualizar(c, dt);
    agregador.agregar(c, dt, dosimetro.acumulado(), dosimetro.limites().Capoyo);

    // Aviso sonoro corto al iniciar una excedencia
    if (dosimetro.enExcedencia() && !excPrevio) tone(PIN_BUZZER, 2000, 150);
    excPrevio = dosimetro.enExcedencia();
    mostrarSemaforo(dosimetro.regimen());
  }

  // Cierre de minuto y de día
  if (minutoActual() != minutoEnCurso) {
    minutoEnCurso = minutoActual();
    if (historial.size() >= HIST_MAX) historial.erase(historial.begin());
    historial.push_back(agregador.cerrar(minutoEnCurso));
    if (inicioDiaLocal() != diaEnCurso) {
      cerrarDia(diaEnCurso);   // queda disponible en 0008 hasta que la app lo baje
      diaEnCurso = inicioDiaLocal();
      dosimetro.reiniciar();
    }
  }

  if (ahora - tEstado >= 1000) {
    tEstado = ahora;
    publicarEstado();
    Serial.printf("C=%.1f%%PC reg=%d D=%.2f exc=%u\n", leerCarga(),
                  static_cast<int>(dosimetro.regimen()),
                  dosimetro.acumulado().dosisSobrecarga, dosimetro.acumulado().excedencias);
  }

  // Pulsación larga (2 s) confirma el límite pendiente
  if (digitalRead(PIN_BOTON) == LOW) {
    if (tBoton == 0) tBoton = ahora;
    if (hayPendiente && ahora - tBoton > 2000) {
      dosimetro.setLimites(limitePendiente);
      pesoActivo_kg = pesoPendiente_kg;
      hayPendiente = false;
      publicarConfig();
      tone(PIN_BUZZER, 3000, 80);
    }
  } else {
    tBoton = 0;
  }

  if (histPedido && clienteConectado) {
    enviarHistorial();
    histPedido = false;
  }

  if (resPedido && clienteConectado) {
    enviarResumenes();
    resPedido = false;
  }
}
