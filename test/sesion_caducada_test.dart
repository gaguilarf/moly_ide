import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';
import 'package:moly_ide/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:moly_ide/features/auth/presentation/cubit/auth_state.dart';

/// Contesta a Dio sin salir a la red, con el codigo que se le pida.
class _AdaptadorFalso implements HttpClientAdapter {
  _AdaptadorFalso(this.codigo);

  final int codigo;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      jsonEncode(const <String, dynamic>{}),
      codigo,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

void _silenciarAlmacenSeguro() {
  const canal = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(canal, (_) async => null);
}

OrchestratorApiClient _clienteQueDevuelve(int codigo) {
  final cliente = OrchestratorApiClient(
    secureStorage: const FlutterSecureStorage(),
  );
  cliente.dio.httpClientAdapter = _AdaptadorFalso(codigo);
  return cliente;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(_silenciarAlmacenSeguro);

  group('El cliente avisa cuando el servidor rechaza el token', () {
    test('un 401 en una ruta cualquiera emite sesion caducada', () async {
      final cliente = _clienteQueDevuelve(401);
      final avisado = expectLater(cliente.sesionCaducada.first, completes);

      await cliente.dio
          .get('/tickets')
          .catchError(
            (_) => Response(requestOptions: RequestOptions(path: '/tickets')),
          );

      await avisado;
    });

    test('un 401 del propio login NO emite: son credenciales malas', () async {
      final cliente = _clienteQueDevuelve(401);
      var avisos = 0;
      cliente.sesionCaducada.listen((_) => avisos++);

      await cliente.dio
          .post('/auth/login')
          .catchError(
            (_) =>
                Response(requestOptions: RequestOptions(path: '/auth/login')),
          );
      await Future<void>.delayed(Duration.zero);

      expect(
        avisos,
        0,
        reason: 'avisar aqui cerraria una sesion que todavia no existe',
      );
    });

    test('un 500 no toca la sesion', () async {
      final cliente = _clienteQueDevuelve(500);
      var avisos = 0;
      cliente.sesionCaducada.listen((_) => avisos++);

      await cliente.dio
          .get('/tickets')
          .catchError(
            (_) => Response(requestOptions: RequestOptions(path: '/tickets')),
          );
      await Future<void>.delayed(Duration.zero);

      expect(avisos, 0);
    });
  });

  group('AuthCubit reacciona al aviso', () {
    test('con sesion abierta, un 401 la cierra y explica por que', () async {
      final cliente = _clienteQueDevuelve(401);
      final cubit = AuthCubit(
        apiClient: cliente,
        secureStorage: const FlutterSecureStorage(),
      );

      // Se simula la sesión ya abierta sin pasar por el login.
      cubit.emit(
        const AuthState(status: AuthStatus.authenticated, token: 'jwt'),
      );

      await cliente.dio
          .get('/tickets')
          .catchError(
            (_) => Response(requestOptions: RequestOptions(path: '/tickets')),
          );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.state.status, AuthStatus.unauthenticated);
      expect(cubit.state.token, isNull);
      expect(cubit.state.errorMessage, contains('caducado'));

      await cubit.close();
    });

    test('sin sesion, un 401 no pisa lo que haya en pantalla', () async {
      final cliente = _clienteQueDevuelve(401);
      final cubit = AuthCubit(
        apiClient: cliente,
        secureStorage: const FlutterSecureStorage(),
      );
      cubit.emit(
        const AuthState(
          status: AuthStatus.failure,
          errorMessage: 'Credenciales inválidas o error de conexión.',
        ),
      );

      await cliente.dio
          .get('/tickets')
          .catchError(
            (_) => Response(requestOptions: RequestOptions(path: '/tickets')),
          );
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(
        cubit.state.errorMessage,
        'Credenciales inválidas o error de conexión.',
        reason: 'el error del login manda mientras no haya sesion que cerrar',
      );

      await cubit.close();
    });
  });
}
