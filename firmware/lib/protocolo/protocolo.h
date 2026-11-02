// Serialización de paquetes BLE. Ver docs/protocolo-ble.md (fuente de verdad).
#pragma once
#include <cstdint>
#include <cstring>
#include "dosimetria.h"

namespace proto {

constexpr uint8_t VERSION = 1;

constexpr const char* UUID_SERVICIO   = "6f1a0000-8b3c-4d5e-9a10-2c7e5b3d9f00";
constexpr const char* UUID_ESTADO     = "6f1a0001-8b3c-4d5e-9a10-2c7e5b3d9f00";
constexpr const char* UUID_RESUMEN    = "6f1a0002-8b3c-4d5e-9a10-2c7e5b3d9f00";
constexpr const char* UUID_HIST_CTRL  = "6f1a0003-8b3c-4d5e-9a10-2c7e5b3d9f00";
constexpr const char* UUID_HIST_DATOS = "6f1a0004-8b3c-4d5e-9a10-2c7e5b3d9f00";
constexpr const char* UUID_CONFIG     = "6f1a0005-8b3c-4d5e-9a10-2c7e5b3d9f00";
constexpr const char* UUID_HORA       = "6f1a0006-8b3c-4d5e-9a10-2c7e5b3d9f00";
constexpr const char* UUID_INFO       = "6f1a0007-8b3c-4d5e-9a10-2c7e5b3d9f00";
constexpr const char* UUID_RESUMENES  = "6f1a0008-8b3c-4d5e-9a10-2c7e5b3d9f00";

constexpr size_t TAM_ESTADO = 8;
constexpr size_t TAM_RESUMEN = 28;
constexpr size_t TAM_REGISTRO = 12;
constexpr size_t TAM_CONFIG = 13;   // lectura de 0005
constexpr size_t TAM_INFO = 32;     // lectura de 0007
constexpr size_t LARGO_SERIE = 12;
constexpr size_t LARGO_EPISODIO = 16;
constexpr size_t REGISTROS_POR_PAQUETE = 15;
// 2 + 8×28 = 226 B, entra en una notificación con el MTU de 247 que pide la app.
constexpr size_t RESUMENES_POR_PAQUETE = 8;
constexpr uint16_t SEQ_FIN = 0xFFFF;

// Operaciones de la característica de control (0003).
enum Op : uint8_t {
  OP_HISTORIAL = 1,  // registros por minuto desde una fecha
  OP_CANCELAR = 2,   // cancela cualquier envío en curso
  OP_RESUMENES = 3,  // resúmenes de días cerrados desde una fecha
};

enum Flags : uint8_t {
  CARGANDO = 1 << 0,
  LIMITE_PENDIENTE = 1 << 1,
  SIN_HORA = 1 << 2,
  SIN_EPISODIO = 1 << 3,
  // El equipo está convirtiendo gramos a %PC con un factor provisorio, sin la calibración
  // global contra balanza. Los %PC que informa no tienen valor clínico y la web tiene que
  // decirlo. Ver docs/avances/ y docs/protocolo-ble.md.
  SIN_CALIBRACION = 1 << 4,
};

inline void put16(uint8_t* b, uint16_t v) { b[0] = v & 0xFF; b[1] = v >> 8; }
inline void put32(uint8_t* b, uint32_t v) { for (int i = 0; i < 4; i++) b[i] = (v >> (8 * i)) & 0xFF; }
inline void putF32(uint8_t* b, float f) { uint32_t v; std::memcpy(&v, &f, 4); put32(b, v); }
inline uint16_t get16(const uint8_t* b) { return b[0] | (b[1] << 8); }
inline uint32_t get32(const uint8_t* b) { return b[0] | (b[1] << 8) | (b[2] << 16) | ((uint32_t)b[3] << 24); }

inline uint16_t x10(double v) {
  if (v < 0) return 0;
  double r = v * 10.0 + 0.5;
  return r > 65534 ? 65534 : static_cast<uint16_t>(r);
}

inline void codificarEstado(uint8_t* b, dosi::Regimen reg, const dosi::Acumulado& a,
                            uint8_t bateria, uint8_t flags) {
  b[0] = VERSION;
  b[1] = static_cast<uint8_t>(reg);
  put16(b + 2, a.excedencias > 65535 ? 65535 : a.excedencias);
  b[4] = bateria;
  b[5] = flags;
  double c = a.cumplimiento();
  put16(b + 6, c < 0 ? 0xFFFF : x10(c));
}

inline void codificarResumen(uint8_t* b, uint32_t inicioDia, const dosi::Acumulado& a) {
  put32(b, inicioDia);
  putF32(b + 4, static_cast<float>(a.dosisSobrecarga));
  putF32(b + 8, static_cast<float>(a.dosisSubcarga));
  put32(b + 12, static_cast<uint32_t>(a.tCarga_s));
  put32(b + 16, static_cast<uint32_t>(a.tExceso_s));
  put32(b + 20, static_cast<uint32_t>(a.tSub_s));
  put16(b + 24, x10(a.pico));
  put16(b + 26, a.excedencias > 65535 ? 65535 : a.excedencias);
}

// Lo que el médico prescribe: los dos límites y el peso con el que se convierte a %PC.
// El constructor es explícito a propósito. Con solo inicializadores por miembro, esta struct
// deja de ser un agregado en C++11, y el core de Arduino para ESP32 compila en gnu++11 pase lo
// que pase en platformio.ini: `Ajustes{a, b, c}` no compilaba para la placa, aunque los tests
// en la PC (que sí usan gnu++17) pasaran. Así funciona con cualquiera de los dos.
struct Ajustes {
  float L = 0;
  float Lmin = 0;
  float peso_kg = 0;

  Ajustes() = default;
  Ajustes(float l, float lmin, float peso) : L(l), Lmin(lmin), peso_kg(peso) {}
};

/// 0005 · Configuración (13 B): activo, pendiente y si hay algo pendiente de confirmar.
inline void codificarConfig(uint8_t* b, const Ajustes& activo, const Ajustes& pendiente,
                            bool hayPendiente) {
  put16(b, x10(activo.L));
  put16(b + 2, x10(activo.Lmin));
  put16(b + 4, x10(activo.peso_kg));
  put16(b + 6, x10(pendiente.L));
  put16(b + 8, x10(pendiente.Lmin));
  put16(b + 10, x10(pendiente.peso_kg));
  b[12] = hayPendiente ? 1 : 0;
}

/// 0007 · Info y episodio (32 B). El episodio son 16 caracteres hex, o ceros si no hay.
/// Es el único identificador que guarda el equipo: nada de nombre ni documento.
inline void codificarInfo(uint8_t* b, uint8_t fwMayor, uint8_t fwMenor, uint8_t fwParche,
                          const char* serie, const char* episodio) {
  std::memset(b, 0, TAM_INFO);
  b[0] = VERSION;
  b[1] = fwMayor;
  b[2] = fwMenor;
  b[3] = fwParche;
  std::strncpy(reinterpret_cast<char*>(b + 4), serie, LARGO_SERIE);
  std::memcpy(b + 16, episodio, LARGO_EPISODIO);
}

inline void codificarRegistro(uint8_t* b, const dosi::RegistroMinuto& r) {
  put32(b, r.ts);
  put16(b + 4, x10(r.cargaMedia));
  put16(b + 6, x10(r.cargaPico));
  double d = r.dosis * 100.0 + 0.5;
  put16(b + 8, d > 65534 ? 65534 : static_cast<uint16_t>(d));
  b[10] = r.excedencias;
  uint16_t s = r.segApoyo / 4;
  b[11] = s > 15 ? 15 : static_cast<uint8_t>(s);
}

}  // namespace proto
