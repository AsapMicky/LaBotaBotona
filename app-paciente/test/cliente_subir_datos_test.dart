import 'dart:convert';

import 'package:dosimetro_paciente/subida/cliente_subir_datos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const token = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

  test('arma la URL de la función y manda el token en el cuerpo', () async {
    http.Request? visto;
    final cliente = ClienteSubirDatos(
      'https://xxxx.supabase.co/',
      anonKey: 'anon',
      cliente: MockClient((req) async {
        visto = req;
        return http.Response(jsonEncode({'ok': true, 'resumenes': 1, 'registros': 2}), 200);
      }),
    );
    final r = await cliente.subir(token: token, resumenes: [{'fecha': '2026-09-16'}], registros: [{}, {}]);
    expect(r, isA<SubidaOk>());
    expect((r as SubidaOk).registros, 2);
    expect(visto!.url.toString(), 'https://xxxx.supabase.co/functions/v1/subir-datos');
    expect(visto!.headers['content-type'], startsWith('application/json'));
    expect(visto!.headers['apikey'], 'anon');
    final cuerpo = jsonDecode(visto!.body) as Map<String, dynamic>;
    expect(cuerpo['token'], token);
    expect(cuerpo['resumenes'], hasLength(1));
    expect(cuerpo['registros'], hasLength(2));
  });

  test('404 de la función = episodio cerrado', () async {
    final cliente = ClienteSubirDatos('http://s', cliente: MockClient((_) async => http.Response('Episodio inexistente o cerrado', 404)));
    expect(await cliente.subir(token: token), isA<EpisodioCerrado>());
  });

  test('otro 404 es una URL mal puesta: falla sin reintento', () async {
    final cliente = ClienteSubirDatos('http://s', cliente: MockClient((_) async => http.Response('{"code":"NOT_FOUND"}', 404)));
    final r = await cliente.subir(token: token);
    expect(r, isA<SubidaFallida>());
    expect((r as SubidaFallida).reintentable, isFalse);
  });

  test('5xx y sin red son reintentables', () async {
    final caido = ClienteSubirDatos('http://s', cliente: MockClient((_) async => http.Response('boom', 503)));
    expect(((await caido.subir(token: token)) as SubidaFallida).reintentable, isTrue);

    final sinRed = ClienteSubirDatos('http://s', cliente: MockClient((_) async => throw http.ClientException('sin red')));
    final r = await sinRed.subir(token: token) as SubidaFallida;
    expect(r.reintentable, isTrue);
    expect(r.motivo, 'sin red');
  });

  test('400 no se reintenta', () async {
    final cliente = ClienteSubirDatos('http://s', cliente: MockClient((_) async => http.Response('Falta el token del episodio', 400)));
    expect(((await cliente.subir(token: token)) as SubidaFallida).reintentable, isFalse);
  });
}
