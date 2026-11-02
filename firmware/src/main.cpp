// Simulador del dosímetro: la carga sale de un potenciómetro.
// Todo lo demás (dosis, semáforo, protocolo BLE) es el código definitivo.
#include <Arduino.h>
#include <NimBLEDevice.h>
#include <Preferences.h>
#include <esp_sleep.h>
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

// ---------------- Calibración global ----------------
//
// El equipo mide gramos sobre los sensores. El contrato con la app y la web es %PC, y el
// puente es este factor: cuánta carga corporal representa cada gramo medido. Hace falta
// porque los FSR cubren una fracción de la planta, así que su suma no es la carga del pie.
//
// Se obtiene con el sujeto parado sobre una balanza (calibración global, pendiente). Hasta
// entonces vale K_PROVISORIO y el equipo lo declara por el flag SIN_CALIBRACION, para que la
// web no muestre como clínico un número que no lo es.
//
// K_PROVISORIO solo compensa que hay 3 de 8 sensores: 8/3. NO corrige la fracción de planta
// que los FSR no tocan, así que subestima. Es un valor para la demo, no para un informe.
static const float K_PROVISORIO = 8.0f / 3.0f;
static float kGlobal = K_PROVISORIO;
static bool calibracionGlobal = false;

/// Convierte lo que miden los sensores a porcentaje del peso corporal.
static float gramosAPorcentajePC(float gramos) {
  if (pesoActivo_kg <= 0.0f) return 0.0f;   // sin peso cargado no hay %PC posible
  return kGlobal * gramos / (pesoActivo_kg * 10.0f);
}

// ---------------- Persistencia ----------------
//
// El episodio y los límites TIENEN que sobrevivir a un reinicio. Si se pierden, el equipo
// vuelve a los valores de fábrica y queda midiendo contra un límite que nadie prescribió
// (ver docs/protocolo-ble.md, 0007).
static Preferences nvs;

static void guardarNvs() {
  nvs.putBytes("episodio", episodio, sizeof episodio);
  const Limites& l = dosimetro.limites();
  nvs.putFloat("L", l.L);
  nvs.putFloat("Lmin", l.Lmin);
  nvs.putFloat("peso", pesoActivo_kg);
  nvs.putShort("offset", offsetLocal_min);
  nvs.putFloat("k", kGlobal);
  nvs.putBool("calib", calibracionGlobal);
}

static void cargarNvs() {
  if (nvs.isKey("episodio")) nvs.getBytes("episodio", episodio, sizeof episodio);
  Limites l = dosimetro.limites();
  l.L = nvs.getFloat("L", l.L);
  l.Lmin = nvs.getFloat("Lmin", l.Lmin);
  dosimetro.setLimites(l);
  pesoActivo_kg = pesoPendiente_kg = nvs.getFloat("peso", pesoActivo_kg);
  offsetLocal_min = nvs.getShort("offset", offsetLocal_min);
  kGlobal = nvs.getFloat("k", K_PROVISORIO);
  calibracionGlobal = nvs.getBool("calib", false);
  limitePendiente = l;
}

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
// ---------------- Riel y batería ----------------
//
// No hay regulador: el riel es la celda. Medirlo con el mismo ADC que mide la señal permite
// dos cosas: corregir la lectura (ver `corregir()`) y saber cuánta batería queda.
static uint16_t rielMv = V_CAL_MV;

/// Promedia 16 lecturas del divisor R17/R18. Se llama una vez por segundo: tarda ~1 ms y no
/// toca la ventana de 20 ms del muestreo.
static void medirRiel() {
  uint32_t suma = 0;
  for (int i = 0; i < 16; i++) suma += analogReadMilliVolts(PIN_RIEL);
  const uint32_t mv = (suma / 16) * 2;   // el divisor es 1:2
  // Fuera de rango significa pin desconectado o medición sin sentido: se descarta en vez de
  // corregir con un número inventado.
  if (mv >= 2500 && mv <= 4500) rielMv = static_cast<uint16_t>(mv);
}

/// Lleva una lectura a la tensión de riel que había durante la calibración.
///
/// Sin esto, una misma carga se leería hasta 27 % más alta con la batería recién cargada, y el
/// equipo acusaría de sobrecarga a un paciente que se cuidó. Es exactamente el error que el
/// proyecto existe para evitar.
static float corregir(float mv) {
  return rielMv > 0 ? mv * static_cast<float>(V_CAL_MV) / rielMv : mv;
}

static uint8_t leerBateria() {
  // Aproximación lineal entre el corte y la celda llena. La curva real de una LiPo no es
  // lineal; alcanza para el indicador del paciente, que solo necesita saber si tiene que
  // cargar. Con el equipo por USB el riel queda en V_CAL y esto da un valor bajo: es correcto,
  // porque en esa condición no hay batería de la cual informar.
  if (rielMv >= BAT_LLENA_MV) return 100;
  if (rielMv <= BAT_CORTE_MV) return 0;
  return static_cast<uint8_t>(100UL * (rielMv - BAT_CORTE_MV) / (BAT_LLENA_MV - BAT_CORTE_MV));
}

/// Carga en %PC. Hoy la simula un potenciómetro.
///
/// En la placa real esto pasa a ser: barrido de los canales por el CD4051B (10 pasadas en
/// 20 ms, que cancelan los 50 Hz de red), conversión de mV a gramos con la tabla de la
/// calibración del 28/10, resta del cero por canal ANTES de convertir, suma de los canales
/// y finalmente `gramosAPorcentajePC()`. El firmware del prototipo ya hace todo salvo el
/// último paso; ver docs/avances/ y docs/firmware-placa-real.md §7.2.
static bool saturado = false;

static float leerCarga() {
  const float crudoMv = analogReadMilliVolts(PIN_POT);
  // La saturación se decide sobre el valor CRUDO, antes de corregir: el techo del ADC está
  // donde está sin importar en qué anda el riel. Si se evaluara sobre el corregido, con la
  // batería llena el umbral se correría y el equipo leería un valor recortado como si fuera real.
  saturado = crudoMv >= SAT_MV;
  return corregir(crudoMv) / 3300.0f * CARGA_MAX_SIM;
}

/// El TMB12A05 es un buzzer **activo**: suena solo con que le llegue tensión, y genera su
/// propio tono. `tone()` le pone una frecuencia que no usa para nada.
static void pitar(uint16_t ms) {
  digitalWrite(PIN_BUZZER, HIGH);
  delay(ms);
  digitalWrite(PIN_BUZZER, LOW);
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
  // LED RGB de cátodo común, encendido/apagado por color. El ámbar del exceso sale como
  // rojo + verde, que es lo más cerca que se llega sin PWM. Si el grupo confirma el ámbar
  // (hoy el prototipo usa rojo), esto pasa a ledcWrite para graduar los tres canales.
  digitalWrite(PIN_LED_R, R > 0 ? HIGH : LOW);
  digitalWrite(PIN_LED_G, G > 0 ? HIGH : LOW);
  digitalWrite(PIN_LED_B, B > 0 ? HIGH : LOW);
#endif
}

// ---------------- Paquetes ----------------
static void publicarEstado() {
  uint8_t flags = 0;
  if (hayPendiente) flags |= proto::LIMITE_PENDIENTE;
  if (!horaSincronizada) flags |= proto::SIN_HORA;
  if (sinEpisodio()) flags |= proto::SIN_EPISODIO;
  if (!calibracionGlobal) flags |= proto::SIN_CALIBRACION;
  uint8_t b[proto::TAM_ESTADO];
  proto::codificarEstado(b, dosimetro.regimen(), dosimetro.acumulado(), leerBateria(), flags);
  chEstado->setValue(b, sizeof b);
  if (clienteConectado) chEstado->notify();

  uint8_t r[proto::TAM_RESUMEN];
  proto::codificarResumen(r, inicioDiaLocal(), dosimetro.acumulado());
  chResumen->setValue(r, sizeof r);
}

static void publicarConfig() {
  const Limites& a = dosimetro.limites();
  proto::Ajustes activo{a.L, a.Lmin, pesoActivo_kg};
  proto::Ajustes pendiente{limitePendiente.L, limitePendiente.Lmin, pesoPendiente_kg};
  uint8_t b[proto::TAM_CONFIG];
  proto::codificarConfig(b, activo, pendiente, hayPendiente);
  chConfig->setValue(b, sizeof b);
}

static void publicarInfo() {
  uint8_t b[proto::TAM_INFO];
  proto::codificarInfo(b, FW_MAYOR, FW_MENOR, FW_PARCHE, SERIE, episodio);
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
      guardarNvs();     // el offset local define a qué día pertenece cada resumen
      agregador.iniciar(minutoActual(), dosimetro.acumulado());
    } else if (uuid == proto::UUID_INFO && n == 16) {
      memcpy(episodio, d, 16);
      if (sinEpisodio()) {          // devolución del equipo
        historial.clear();
        resumenes.clear();
        dosimetro.reiniciar();
        // La calibración global es de la persona, no del equipo: al cerrar el episodio
        // deja de valer y el siguiente paciente arranca otra vez sin calibrar.
        kGlobal = K_PROVISORIO;
        calibracionGlobal = false;
      }
      guardarNvs();
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

/// Apaga el equipo cuando la celda ya no da, sin perder el minuto en curso.
///
/// El corte tiene que sostenerse BAT_CORTE_MS: el buzzer y la radio hacen caer el riel por
/// instantes, y apagarse por uno de esos picos sería peor que seguir midiendo.
static void vigilarBateria(uint32_t ahora) {
  static uint32_t bajoDesde = 0;
  if (rielMv > BAT_CORTE_MV) { bajoDesde = 0; return; }
  if (bajoDesde == 0) { bajoDesde = ahora; return; }
  if (ahora - bajoDesde < BAT_CORTE_MS) return;

  // Lo último que se hace es guardar: un minuto a medias vale más que nada.
  historial.push_back(agregador.cerrar(minutoActual()));   // TODO(avance 4): a LittleFS
  guardarNvs();
  for (int i = 0; i < 3; i++) { pitar(120); delay(120); }
  Serial.println("Bateria agotada: apagando");
  Serial.flush();
  esp_deep_sleep_start();
}

// ---------------- Setup / loop ----------------
void setup() {
  Serial.begin(115200);
  pinMode(PIN_BOTON, INPUT_PULLUP);
  pinMode(PIN_BUZZER, OUTPUT);
#if !defined(PIN_NEOPIXEL)
  pinMode(PIN_LED_R, OUTPUT);
  pinMode(PIN_LED_G, OUTPUT);
  pinMode(PIN_LED_B, OUTPUT);
#endif
  analogReadResolution(12);
  medirRiel();   // antes de la primera lectura, para no corregir con un riel supuesto

  Limites lim;
  lim.L = 20.0f;
  lim.Lmin = 10.0f;
  dosimetro.setLimites(lim);
  limitePendiente = lim;

  // Lo guardado pisa a los valores de fábrica de arriba. Si el equipo se reinició en medio
  // de un tratamiento, tiene que seguir midiendo contra el límite de ese paciente.
  nvs.begin("dosimetro", false);
  cargarNvs();

  iniciarBLE();
  publicarConfig();
  publicarInfo();
  agregador.iniciar(minutoActual(), dosimetro.acumulado());
  Serial.println("Dosimetro (simulador con potenciometro) listo");
}

void loop() {
  // tMuestra arranca en millis(), no en 0: si no, la primera muestra integra todo el tiempo
  // transcurrido desde el arranque y mete una dosis falsa de varios segundos.
  static uint32_t tMuestra = millis(), tEstado = 0, tBoton = 0;
  static float ultimaCarga = 0;
  static uint32_t minutoEnCurso = minutoActual();
  static uint32_t diaEnCurso = inicioDiaLocal();
  static bool excPrevio = false;
  const uint32_t ahora = millis();

  if (ahora - tMuestra >= 1000 / FS_HZ) {
    const float dt = (ahora - tMuestra) / 1000.0f;
    tMuestra = ahora;
    const float c = leerCarga();
    ultimaCarga = c;
    dosimetro.actualizar(c, dt);
    agregador.agregar(c, dt, dosimetro.acumulado(), dosimetro.limites().Capoyo);

    // Aviso sonoro corto al iniciar una excedencia
    if (dosimetro.enExcedencia() && !excPrevio) pitar(150);
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
    medirRiel();
    vigilarBateria(ahora);
    publicarEstado();
    // Se imprime la última carga medida, no una lectura nueva: con el barrido real cada
    // llamada a leerCarga() bloquea 20 ms, y acá no hace falta medir de nuevo.
    Serial.printf("C=%.1f%%PC reg=%d D=%.2f exc=%u\n", ultimaCarga,
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
      guardarNvs();        // el límite confirmado tiene que sobrevivir a un reinicio
      publicarConfig();
      pitar(80);
    }
  } else {
    tBoton = 0;
  }

  // `v` imprime el riel medido. Es el procedimiento para obtener V_CAL_MV: se corre con el
  // equipo por USB y la batería desconectada, y el valor se carga en placa.h antes de calibrar.
  if (Serial.available() && Serial.read() == 'v') {
    medirRiel();
    Serial.printf("riel=%u mV  (V_CAL_MV actual: %d)  bateria=%u%%\n",
                  rielMv, V_CAL_MV, leerBateria());
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
