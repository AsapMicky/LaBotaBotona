// Vectores de referencia compartidos con la app (docs/protocolo-vectores.json).
// El firmware CODIFICA: arma cada paquete a partir de los valores de entrada y
// compara byte a byte con el hexa del archivo. La app hace lo inverso en
// app-paciente/test/vectores_test.dart. Un byte corrido rompe los dos lados.
#include <unity.h>
#include <ArduinoJson.h>
#include <cstdio>
#include <string>
#include <vector>
#include "dosimetria.h"
#include "protocolo.h"

using namespace dosi;

static JsonDocument doc;

static std::string leerArchivo(const char* ruta) {
  FILE* f = std::fopen(ruta, "rb");
  if (!f) return "";
  std::string s;
  char buf[4096];
  size_t n;
  while ((n = std::fread(buf, 1, sizeof buf, f)) > 0) s.append(buf, n);
  std::fclose(f);
  return s;
}

static std::vector<uint8_t> desdeHexa(const char* h) {
  std::vector<uint8_t> out;
  int nib = -1;
  for (const char* p = h; *p; ++p) {
    int v;
    if (*p >= '0' && *p <= '9') v = *p - '0';
    else if (*p >= 'A' && *p <= 'F') v = *p - 'A' + 10;
    else if (*p >= 'a' && *p <= 'f') v = *p - 'a' + 10;
    else continue;
    if (nib < 0) nib = v;
    else { out.push_back(static_cast<uint8_t>(nib * 16 + v)); nib = -1; }
  }
  return out;
}

static void compararBytes(const char* nombre, const std::vector<uint8_t>& esperado, const uint8_t* obtenido, size_t n) {
  char msg[160];
  std::snprintf(msg, sizeof msg, "[%s] tamaño", nombre);
  TEST_ASSERT_EQUAL_size_t_MESSAGE(esperado.size(), n, msg);
  for (size_t i = 0; i < n; i++) {
    std::snprintf(msg, sizeof msg, "[%s] byte %u", nombre, static_cast<unsigned>(i));
    TEST_ASSERT_EQUAL_HEX8_MESSAGE(esperado[i], obtenido[i], msg);
  }
}

void setUp() {}
void tearDown() {}

void test_cargar_vectores() {
  // pio test corre con el cwd en firmware/; el archivo está un nivel arriba.
  const char* rutas[] = {"../docs/protocolo-vectores.json", "docs/protocolo-vectores.json",
                         "../../docs/protocolo-vectores.json"};
  std::string json;
  for (const char* r : rutas) { json = leerArchivo(r); if (!json.empty()) break; }
  TEST_ASSERT_FALSE_MESSAGE(json.empty(), "no encontré docs/protocolo-vectores.json");
  DeserializationError e = deserializeJson(doc, json);
  TEST_ASSERT_EQUAL_STRING_MESSAGE("Ok", e.c_str(), "JSON inválido");
  TEST_ASSERT_EQUAL_UINT8(proto::VERSION, doc["version_protocolo"].as<uint8_t>());
}

void test_estado() {
  for (JsonObject v : doc["estado"].as<JsonArray>()) {
    JsonObject in = v["entrada"];
    Acumulado a;
    a.excedencias = in["excedencias"];
    a.tCarga_s = in["t_carga_s"].as<double>();
    a.tExceso_s = in["t_exceso_s"].as<double>();
    uint8_t b[proto::TAM_ESTADO];
    proto::codificarEstado(b, static_cast<Regimen>(in["regimen"].as<uint8_t>()), a,
                           in["bateria"].as<uint8_t>(), in["flags"].as<uint8_t>());
    compararBytes(v["nombre"], desdeHexa(v["bytes"]), b, sizeof b);
  }
}

static Acumulado acumuladoDesde(JsonObject in) {
  Acumulado a;
  a.dosisSobrecarga = in["dosis_sobrecarga"].as<double>();
  a.dosisSubcarga = in["dosis_subcarga"].as<double>();
  a.tCarga_s = in["t_carga_s"].as<double>();
  a.tExceso_s = in["t_exceso_s"].as<double>();
  a.tSub_s = in["t_sub_s"].as<double>();
  a.pico = in["pico"].as<float>();
  a.excedencias = in["excedencias"];
  return a;
}

void test_resumen() {
  for (JsonObject v : doc["resumen"].as<JsonArray>()) {
    JsonObject in = v["entrada"];
    uint8_t b[proto::TAM_RESUMEN];
    proto::codificarResumen(b, in["inicio_dia"].as<uint32_t>(), acumuladoDesde(in));
    compararBytes(v["nombre"], desdeHexa(v["bytes"]), b, sizeof b);
  }
}

static RegistroMinuto registroDesde(JsonObject in) {
  RegistroMinuto r;
  r.ts = in["ts"].as<uint32_t>();
  r.cargaMedia = in["carga_media"].as<float>();
  r.cargaPico = in["carga_pico"].as<float>();
  r.dosis = in["dosis"].as<float>();
  r.excedencias = in["excedencias"].as<uint8_t>();
  r.segApoyo = in["seg_apoyo"].as<uint16_t>();
  return r;
}

void test_registro() {
  for (JsonObject v : doc["registro"].as<JsonArray>()) {
    uint8_t b[proto::TAM_REGISTRO];
    proto::codificarRegistro(b, registroDesde(v["entrada"]));
    compararBytes(v["nombre"], desdeHexa(v["bytes"]), b, sizeof b);
  }
}

// El paquete de historial lo arma main.cpp (u16 secuencia + registros). Acá se
// verifica que la estructura del vector sea consistente con TAM_REGISTRO y SEQ_FIN.
void test_paquete_historial() {
  for (JsonObject v : doc["paquete_historial"].as<JsonArray>()) {
    std::vector<uint8_t> b = desdeHexa(v["bytes"]);
    JsonObject esp = v["esperado"];
    TEST_ASSERT_EQUAL_UINT16(esp["secuencia"].as<uint16_t>(), proto::get16(b.data()));
    size_t n = (b.size() - 2) / proto::TAM_REGISTRO;
    TEST_ASSERT_EQUAL_size_t(esp["cantidad"].as<size_t>(), n);
    TEST_ASSERT_EQUAL_size_t(2 + n * proto::TAM_REGISTRO, b.size());
    if (esp["secuencia"].as<uint16_t>() == proto::SEQ_FIN) TEST_ASSERT_EQUAL_size_t(0, n);
    // Cada registro del paquete tiene que ser uno de los vectores de "registro"
    for (size_t i = 0; i < n; i++) {
      const char* nombre = esp["registros"][i];
      bool hallado = false;
      for (JsonObject r : doc["registro"].as<JsonArray>()) {
        if (std::string(nombre) == r["nombre"].as<const char*>()) {
          uint8_t rb[proto::TAM_REGISTRO];
          proto::codificarRegistro(rb, registroDesde(r["entrada"]));
          compararBytes(nombre, std::vector<uint8_t>(b.begin() + 2 + i * proto::TAM_REGISTRO,
                                                     b.begin() + 2 + (i + 1) * proto::TAM_REGISTRO),
                        rb, proto::TAM_REGISTRO);
          hallado = true;
        }
      }
      TEST_ASSERT_TRUE_MESSAGE(hallado, "registro del paquete no está en la lista de vectores");
    }
  }
}

// Resúmenes de días cerrados (0008): mismo armado que el historial, con registros de 28 B.
void test_paquete_resumenes() {
  for (JsonObject v : doc["paquete_resumenes"].as<JsonArray>()) {
    std::vector<uint8_t> b = desdeHexa(v["bytes"]);
    JsonObject esp = v["esperado"];
    TEST_ASSERT_EQUAL_UINT16(esp["secuencia"].as<uint16_t>(), proto::get16(b.data()));
    size_t n = (b.size() - 2) / proto::TAM_RESUMEN;
    TEST_ASSERT_EQUAL_size_t(esp["cantidad"].as<size_t>(), n);
    TEST_ASSERT_EQUAL_size_t(2 + n * proto::TAM_RESUMEN, b.size());
    TEST_ASSERT_TRUE_MESSAGE(n <= proto::RESUMENES_POR_PAQUETE, "no entra en una notificación");
    if (esp["secuencia"].as<uint16_t>() == proto::SEQ_FIN) TEST_ASSERT_EQUAL_size_t(0, n);
    for (size_t i = 0; i < n; i++) {
      const char* nombre = esp["resumenes"][i];
      bool hallado = false;
      for (JsonObject r : doc["resumen"].as<JsonArray>()) {
        if (std::string(nombre) == r["nombre"].as<const char*>()) {
          JsonObject in = r["entrada"];
          uint8_t rb[proto::TAM_RESUMEN];
          proto::codificarResumen(rb, in["inicio_dia"].as<uint32_t>(), acumuladoDesde(in));
          compararBytes(nombre, std::vector<uint8_t>(b.begin() + 2 + i * proto::TAM_RESUMEN,
                                                     b.begin() + 2 + (i + 1) * proto::TAM_RESUMEN),
                        rb, proto::TAM_RESUMEN);
          hallado = true;
        }
      }
      TEST_ASSERT_TRUE_MESSAGE(hallado, "resumen del paquete no está en la lista de vectores");
    }
  }
}

// Estos los escribe la app y los DECODIFICA el firmware (callbacks de main.cpp).
void test_pedido_historial() {
  for (JsonObject v : doc["pedido_historial"].as<JsonArray>()) {
    std::vector<uint8_t> b = desdeHexa(v["bytes"]);
    TEST_ASSERT_EQUAL_size_t(5, b.size());
    TEST_ASSERT_EQUAL_UINT8(proto::OP_HISTORIAL, b[0]);
    TEST_ASSERT_EQUAL_UINT32(v["desde"].as<uint32_t>(), proto::get32(b.data() + 1));
  }
}

void test_pedido_resumenes() {
  for (JsonObject v : doc["pedido_resumenes"].as<JsonArray>()) {
    std::vector<uint8_t> b = desdeHexa(v["bytes"]);
    TEST_ASSERT_EQUAL_size_t(5, b.size());
    TEST_ASSERT_EQUAL_UINT8(proto::OP_RESUMENES, b[0]);
    TEST_ASSERT_EQUAL_UINT32(v["desde"].as<uint32_t>(), proto::get32(b.data() + 1));
  }
}

void test_hora() {
  for (JsonObject v : doc["hora"].as<JsonArray>()) {
    std::vector<uint8_t> b = desdeHexa(v["bytes"]);
    TEST_ASSERT_EQUAL_size_t(6, b.size());
    TEST_ASSERT_EQUAL_UINT32(v["epoch"].as<uint32_t>(), proto::get32(b.data()));
    TEST_ASSERT_EQUAL_INT16(v["offset_min"].as<int16_t>(), static_cast<int16_t>(proto::get16(b.data() + 4)));
  }
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_cargar_vectores);
  RUN_TEST(test_estado);
  RUN_TEST(test_resumen);
  RUN_TEST(test_registro);
  RUN_TEST(test_paquete_historial);
  RUN_TEST(test_paquete_resumenes);
  RUN_TEST(test_pedido_historial);
  RUN_TEST(test_pedido_resumenes);
  RUN_TEST(test_hora);
  return UNITY_END();
}
