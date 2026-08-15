import 'package:get_it/get_it.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';
import 'package:moly_ide/core/api/websocket_service.dart';

final locator = GetIt.instance;

Future<void> initDependencies() async {
  // Secure Storage
  locator.registerLazySingleton<FlutterSecureStorage>(
    () => const FlutterSecureStorage(
      aOptions: AndroidOptions(
        encryptedSharedPreferences: true,
      ),
    ),
  );

  // Jetson Orchestrator API Client & WebSocket
  locator.registerLazySingleton<OrchestratorApiClient>(
    () => OrchestratorApiClient(secureStorage: locator<FlutterSecureStorage>()),
  );

  locator.registerLazySingleton<WebSocketService>(
    () => WebSocketService(apiClient: locator<OrchestratorApiClient>()),
  );

  await locator<OrchestratorApiClient>().init();
}
