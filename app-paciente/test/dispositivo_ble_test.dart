// La conexión BLE en sí no se puede testear sin radio ni placa: `flutter_blue_plus`
// expone una API estática. Lo que sí se testea es la política de reintento, que es
// lo que decide si la app vuelve a engancharse sola cuando el paciente se aleja.
import 'package:dosimetro_paciente/dispositivo/dispositivo_ble.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('la espera crece y se corta en un minuto', () {
    expect(esperaReintento(1), const Duration(seconds: 2));
    expect(esperaReintento(2), const Duration(seconds: 4));
    expect(esperaReintento(3), const Duration(seconds: 8));
    expect(esperaReintento(4), const Duration(seconds: 16));
    expect(esperaReintento(5), const Duration(seconds: 32));
    expect(esperaReintento(6), const Duration(seconds: 60));
    expect(esperaReintento(50), const Duration(seconds: 60), reason: 'no crece para siempre');
  });

  test('nunca reintenta en cero', () {
    expect(esperaReintento(0).inSeconds, greaterThan(0));
  });
}
