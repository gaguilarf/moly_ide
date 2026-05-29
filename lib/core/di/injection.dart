import 'package:get_it/get_it.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:moly_ide/core/ssh/ssh_service.dart';

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

  // SSH & SFTP Central Service
  locator.registerLazySingleton<SSHService>(
    () => SSHService(secureStorage: locator<FlutterSecureStorage>()),
  );
}
