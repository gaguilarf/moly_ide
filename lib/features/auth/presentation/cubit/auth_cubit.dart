import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';
import 'package:moly_ide/features/auth/data/models/auth_user_model.dart';
import 'package:moly_ide/features/auth/presentation/cubit/auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final OrchestratorApiClient apiClient;
  final FlutterSecureStorage secureStorage;

  static const String userStorageKey = 'authenticated_user_profile';
  static const String vaultUsernameKey = 'vault_saved_username';
  static const String vaultPasswordKey = 'vault_saved_password';
  static const String vaultRememberKey = 'vault_remember_credentials';

  AuthCubit({required this.apiClient, required this.secureStorage})
    : super(const AuthState());

  /// Clave del baúl anterior, cuando se entraba con el correo. Se borra al
  /// arrancar: al cambiar de clave, el correo Y LA CONTRASEÑA de antes se
  /// quedaban en el almacén del dispositivo sin que nada volviera a leerlos ni
  /// a borrarlos nunca.
  static const String vaultClaveAntiguaCorreo = 'vault_saved_email';

  Future<void> checkAuth() async {
    emit(state.copyWith(status: AuthStatus.checking));
    try {
      await secureStorage.delete(key: vaultClaveAntiguaCorreo);
      final token = await secureStorage.read(
        key: OrchestratorApiClient.storageKeyAuthToken,
      );
      final userJson = await secureStorage.read(key: userStorageKey);
      final savedUsername = await secureStorage.read(key: vaultUsernameKey);
      final savedPassword = await secureStorage.read(key: vaultPasswordKey);
      final rememberStr = await secureStorage.read(key: vaultRememberKey);
      final remember = rememberStr != 'false';

      if (token != null && token.isNotEmpty && userJson != null) {
        final user = AuthUserModel.fromJson(jsonDecode(userJson));
        emit(
          state.copyWith(
            status: AuthStatus.authenticated,
            token: token,
            user: user,
            savedUsername: savedUsername,
            savedPassword: savedPassword,
            rememberCredentials: remember,
            currentServerUrl: apiClient.currentBaseUrl,
          ),
        );
      } else {
        emit(
          state.copyWith(
            status: AuthStatus.unauthenticated,
            // Si el almacen ya no tiene token, el estado tampoco debe tenerlo.
            clearSession: true,
            savedUsername: savedUsername,
            savedPassword: savedPassword,
            clearSavedCredentials:
                savedUsername == null && savedPassword == null,
            rememberCredentials: remember,
            currentServerUrl: apiClient.currentBaseUrl,
          ),
        );
      }
    } catch (_) {
      emit(
        state.copyWith(
          status: AuthStatus.unauthenticated,
          clearSession: true,
          currentServerUrl: apiClient.currentBaseUrl,
        ),
      );
    }
  }

  void updateServerUrl(String url) {
    apiClient.updateBaseUrl(url);
    emit(state.copyWith(currentServerUrl: url));
  }

  void toggleRememberCredentials(bool value) {
    emit(state.copyWith(rememberCredentials: value));
  }

  /// Pide la sesión mandando `username`, y si el servidor no conoce ese campo
  /// lo reintenta con `email`.
  ///
  /// Es el puente en el otro sentido del que hace el backend: así esta versión
  /// entra igual contra un Jetson ya migrado que contra uno que todavía no lo
  /// esté, y el orden en que se actualizan app y servidor deja de importar.
  Future<Response> _pedirSesion(String usuario, String password) async {
    try {
      return await apiClient.dio.post(
        '/auth/login',
        data: {'username': usuario, 'password': password},
      );
    } on DioException catch (e) {
      final noConoceElCampo =
          e.response?.statusCode == 422 || e.response?.statusCode == 400;
      if (!noConoceElCampo) rethrow;
      return await apiClient.dio.post(
        '/auth/login',
        data: {'email': usuario, 'password': password},
      );
    }
  }

  Future<void> login({
    required String username,
    required String password,
    bool remember = true,
  }) async {
    emit(state.copyWith(status: AuthStatus.loading, errorMessage: null));
    try {
      final resp = await _pedirSesion(username.trim(), password);

      final token = resp.data['access_token']?.toString() ?? '';
      final user = AuthUserModel.fromJson(resp.data['user']);

      // 1. Guardar token y perfil activo
      await apiClient.setAuthToken(token);
      await secureStorage.write(
        key: userStorageKey,
        value: jsonEncode(user.toJson()),
      );

      // 2. Guardar en el baúl si el usuario tiene activado recordar
      if (remember) {
        await secureStorage.write(
          key: vaultUsernameKey,
          value: username.trim(),
        );
        await secureStorage.write(key: vaultPasswordKey, value: password);
        await secureStorage.write(key: vaultRememberKey, value: 'true');
      } else {
        await secureStorage.delete(key: vaultUsernameKey);
        await secureStorage.delete(key: vaultPasswordKey);
        await secureStorage.write(key: vaultRememberKey, value: 'false');
      }

      emit(
        state.copyWith(
          status: AuthStatus.authenticated,
          token: token,
          user: user,
          savedUsername: remember ? username.trim() : null,
          savedPassword: remember ? password : null,
          // Sin esto, desmarcar «recordar» borraba el baul del almacen pero
          // dejaba el usuario y la contrasena anteriores en el estado.
          clearSavedCredentials: !remember,
          rememberCredentials: remember,
        ),
      );
    } catch (e) {
      emit(
        state.copyWith(
          status: AuthStatus.failure,
          errorMessage: 'Credenciales inválidas o error de conexión.',
        ),
      );
    }
  }

  Future<void> logout({bool keepVaultCredentials = true}) async {
    await secureStorage.delete(key: OrchestratorApiClient.storageKeyAuthToken);
    await secureStorage.delete(key: userStorageKey);

    if (!keepVaultCredentials) {
      await secureStorage.delete(key: vaultUsernameKey);
      await secureStorage.delete(key: vaultPasswordKey);
    }

    final savedUsername = await secureStorage.read(key: vaultUsernameKey);
    final savedPassword = await secureStorage.read(key: vaultPasswordKey);

    emit(
      state.copyWith(
        status: AuthStatus.unauthenticated,
        clearSession: true,
        clearSavedCredentials: !keepVaultCredentials,
        user: null,
        token: null,
        savedUsername: savedUsername,
        savedPassword: savedPassword,
      ),
    );
  }
}
