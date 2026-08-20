import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OrchestratorApiClient {
  final FlutterSecureStorage secureStorage;
  late final Dio dio;

  final _sesionCaducada = StreamController<void>.broadcast();

  /// Avisa cuando el servidor rechaza el token (401). Lo escucha AuthCubit para
  /// cerrar la sesión: sin esto la app se seguía creyendo autenticada con un
  /// JWT muerto, y cada pantalla enseñaba su propio error sin decir que lo que
  /// pasaba era que había que volver a entrar.
  Stream<void> get sesionCaducada => _sesionCaducada.stream;

  // Única vía de acceso: por Tailscale a través de Caddy (TLS de Let's
  // Encrypt, mismo certificado que usa vault), que reenvía al backend real
  // del Jetson. No hay variante LAN: el equipo no siempre está en la misma
  // red, y mantener dos direcciones era lo que llevaba a escribir la
  // equivocada a mano en el formulario.
  static const String defaultBaseUrl =
      'https://jetson-desktop.tail452840.ts.net:8443';
  static const String storageKeyAuthToken = 'jetson_orchestrator_token';

  /// En web la app se sirve desde el propio backend, así que el servidor es el
  /// origen de la página: no hay que escribir ninguna dirección ni pelearse con
  /// CORS. En móvil no hay página, así que se usa la dirección fija de arriba.
  static String get baseUrlPorDefecto =>
      kIsWeb ? Uri.base.origin : defaultBaseUrl;

  final String currentBaseUrl = baseUrlPorDefecto;

  OrchestratorApiClient({required this.secureStorage}) {
    dio = Dio(
      BaseOptions(
        baseUrl: '$baseUrlPorDefecto/api/v1',
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await secureStorage.read(key: storageKeyAuthToken);
          if (token != null && token.isNotEmpty) {
            options.headers['Authorization'] = 'Bearer $token';
          }
          return handler.next(options);
        },
        onError: (DioException e, handler) {
          // El 401 del propio login no es una sesión caducada: significa que
          // las credenciales están mal. Avisar ahí cerraría una sesión que
          // todavía no existe y borraría el error de la pantalla de acceso.
          final esLogin = e.requestOptions.path.contains('/auth/login');
          if (e.response?.statusCode == 401 &&
              !esLogin &&
              !_sesionCaducada.isClosed) {
            _sesionCaducada.add(null);
          }
          return handler.next(e);
        },
      ),
    );
  }

  Future<void> setAuthToken(String token) async {
    await secureStorage.write(key: storageKeyAuthToken, value: token);
  }
}
