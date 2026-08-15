import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class OrchestratorApiClient {
  final FlutterSecureStorage secureStorage;
  late final Dio dio;

  // Defaults: LAN IP o Tailscale
  static const String defaultBaseUrl = 'http://192.168.0.109:8000';
  static const String defaultTailscaleUrl = 'http://jetson-desktop.tail452840.ts.net:8000';
  static const String storageKeyBaseUrl = 'jetson_orchestrator_base_url';
  static const String storageKeyAuthToken = 'jetson_orchestrator_token';

  String currentBaseUrl = defaultBaseUrl;

  OrchestratorApiClient({required this.secureStorage}) {
    dio = Dio(
      BaseOptions(
        baseUrl: '$defaultBaseUrl/api/v1',
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
          return handler.next(e);
        },
      ),
    );
  }

  Future<void> init() async {
    final savedUrl = await secureStorage.read(key: storageKeyBaseUrl);
    if (savedUrl != null && savedUrl.isNotEmpty) {
      updateBaseUrl(savedUrl);
    }
  }

  void updateBaseUrl(String newUrl) {
    final clean = newUrl.endsWith('/') ? newUrl.substring(0, newUrl.length - 1) : newUrl;
    currentBaseUrl = clean;
    dio.options.baseUrl = '$clean/api/v1';
    secureStorage.write(key: storageKeyBaseUrl, value: clean);
  }

  Future<void> setAuthToken(String token) async {
    await secureStorage.write(key: storageKeyAuthToken, value: token);
  }
}
