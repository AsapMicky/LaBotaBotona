// Perfiles de carga sintéticos para validar el Anexo A sin hardware.
#include <unity.h>
#include "dosimetria.h"
#include "protocolo.h"

using namespace dosi;

static Limites lim(float L, float Lmin = 0) { Limites l; l.L = L; l.Lmin = Lmin; return l; }

// Aplica una carga constante durante t segundos a 50 Hz
static void mantener(Dosimetro& d, float c, float t) {
  const float dt = 0.02f;
  int n = static_cast<int>(t / dt + 0.5f);
  for (int i = 0; i < n; i++) d.actualizar(c, dt);
}

void setUp() {}
void tearDown() {}

void test_escalon_dosis() {
  Dosimetro d(lim(20));
  mantener(d, 30, 60);  // 10 %PC por encima durante 1 min
  TEST_ASSERT_DOUBLE_WITHIN(0.01, 10.0, d.acumulado().dosisSobrecarga);
  TEST_ASSERT_EQUAL_UINT32(1, d.acumulado().excedencias);
  TEST_ASSERT_DOUBLE_WITHIN(0.1, 60.0, d.acumulado().tExceso_s);
  TEST_ASSERT_FLOAT_WITHIN(0.01, 30.0f, d.acumulado().pico);
}

void test_bajo_limite_sin_dosis() {
  Dosimetro d(lim(20));
  mantener(d, 15, 120);
  TEST_ASSERT_EQUAL_DOUBLE(0.0, d.acumulado().dosisSobrecarga);
  TEST_ASSERT_EQUAL_UINT32(0, d.acumulado().excedencias);
  TEST_ASSERT_DOUBLE_WITHIN(0.01, 100.0, d.acumulado().cumplimiento());
}

void test_oscilacion_en_umbral_un_solo_evento() {
  Dosimetro d(lim(20));
  for (int i = 0; i < 20; i++) {  // 21 / 19 %PC alternando cada 0,5 s
    mantener(d, 21, 0.5f);
    mantener(d, 19, 0.5f);
  }
  TEST_ASSERT_EQUAL_UINT32(1, d.acumulado().excedencias);
}

void test_evento_termina_con_retardo() {
  Dosimetro d(lim(20));
  mantener(d, 25, 1);
  mantener(d, 10, 1.5f);                 // bajo 0,9·L pero menos de 2 s
  TEST_ASSERT_TRUE(d.enExcedencia());
  TEST_ASSERT_EQUAL_INT(static_cast<int>(Regimen::Exceso), static_cast<int>(d.regimen()));
  mantener(d, 10, 1);                    // ya pasaron 2,5 s
  TEST_ASSERT_FALSE(d.enExcedencia());
  mantener(d, 25, 1);                    // nueva excedencia
  TEST_ASSERT_EQUAL_UINT32(2, d.acumulado().excedencias);
}

void test_reposo_no_cuenta_como_subcarga() {
  Dosimetro d(lim(20, 10));
  mantener(d, 0, 300);                   // sentado
  TEST_ASSERT_EQUAL_DOUBLE(0.0, d.acumulado().dosisSubcarga);
  TEST_ASSERT_EQUAL_DOUBLE(0.0, d.acumulado().tCarga_s);
  TEST_ASSERT_TRUE(d.acumulado().cumplimiento() < 0);  // sin apoyo aún
  mantener(d, 7, 60);                    // apoya 3 %PC por debajo de Lmin
  TEST_ASSERT_DOUBLE_WITHIN(0.01, 3.0, d.acumulado().dosisSubcarga);
  TEST_ASSERT_DOUBLE_WITHIN(0.1, 60.0, d.acumulado().tSub_s);
}

void test_particion_e_indices() {
  Dosimetro d(lim(20, 10));
  mantener(d, 7, 20);    // subcarga
  mantener(d, 15, 67);   // ventana
  mantener(d, 25, 13);   // exceso
  const Acumulado& a = d.acumulado();
  TEST_ASSERT_DOUBLE_WITHIN(0.1, 100.0, a.tCarga_s);
  TEST_ASSERT_DOUBLE_WITHIN(0.1, 67.0, a.tVentana_s());
  TEST_ASSERT_DOUBLE_WITHIN(0.1, 87.0, a.cumplimiento());
  TEST_ASSERT_DOUBLE_WITHIN(0.1, 67.0, a.permanencia());
}

void test_agregador_minuto() {
  Dosimetro d(lim(20));
  AgregadorMinuto ag;
  ag.iniciar(600, d.acumulado());
  const float dt = 0.02f;
  for (int i = 0; i < 1500; i++) {       // 30 s a 30 %PC
    d.actualizar(30, dt); ag.agregar(30, dt, d.acumulado(), 5);
  }
  for (int i = 0; i < 1500; i++) {       // 30 s sin apoyo
    d.actualizar(0, dt); ag.agregar(0, dt, d.acumulado(), 5);
  }
  RegistroMinuto r = ag.cerrar(660);
  TEST_ASSERT_EQUAL_UINT32(600, r.ts);
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 30.0f, r.cargaMedia);   // media solo con apoyo
  TEST_ASSERT_FLOAT_WITHIN(0.01f, 5.0f, r.dosis);         // 10 %PC × 0,5 min
  TEST_ASSERT_EQUAL_UINT8(1, r.excedencias);
  TEST_ASSERT_EQUAL_UINT16(30, r.segApoyo);
  RegistroMinuto r2 = ag.cerrar(720);
  TEST_ASSERT_EQUAL_FLOAT(0.0f, r2.dosis);                // el minuto siguiente arranca de cero
}

void test_codificacion_estado() {
  Dosimetro d(lim(20));
  mantener(d, 15, 87);
  mantener(d, 25, 13);
  uint8_t b[proto::TAM_ESTADO];
  proto::codificarEstado(b, d.regimen(), d.acumulado(), 76, proto::LIMITE_PENDIENTE);
  TEST_ASSERT_EQUAL_UINT8(1, b[0]);
  TEST_ASSERT_EQUAL_UINT8(3, b[1]);
  TEST_ASSERT_EQUAL_UINT16(1, proto::get16(b + 2));
  TEST_ASSERT_EQUAL_UINT8(76, b[4]);
  TEST_ASSERT_EQUAL_UINT8(proto::LIMITE_PENDIENTE, b[5]);
  TEST_ASSERT_UINT16_WITHIN(1, 870, proto::get16(b + 6));
}

void test_codificacion_registro() {
  RegistroMinuto r;
  r.ts = 1789500000; r.cargaMedia = 18.34f; r.cargaPico = 41.0f;
  r.dosis = 2.5f; r.excedencias = 3; r.segApoyo = 42;
  uint8_t b[proto::TAM_REGISTRO];
  proto::codificarRegistro(b, r);
  TEST_ASSERT_EQUAL_UINT32(1789500000u, proto::get32(b));
  TEST_ASSERT_EQUAL_UINT16(183, proto::get16(b + 4));
  TEST_ASSERT_EQUAL_UINT16(410, proto::get16(b + 6));
  TEST_ASSERT_EQUAL_UINT16(250, proto::get16(b + 8));
  TEST_ASSERT_EQUAL_UINT8(3, b[10]);
  TEST_ASSERT_EQUAL_UINT8(10, b[11]);
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_escalon_dosis);
  RUN_TEST(test_bajo_limite_sin_dosis);
  RUN_TEST(test_oscilacion_en_umbral_un_solo_evento);
  RUN_TEST(test_evento_termina_con_retardo);
  RUN_TEST(test_reposo_no_cuenta_como_subcarga);
  RUN_TEST(test_particion_e_indices);
  RUN_TEST(test_agregador_minuto);
  RUN_TEST(test_codificacion_estado);
  RUN_TEST(test_codificacion_registro);
  return UNITY_END();
}
