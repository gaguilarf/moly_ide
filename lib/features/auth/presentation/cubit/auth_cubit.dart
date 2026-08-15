import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';
import 'package:moly_ide/features/auth/data/models/auth_user_model.dart';
import 'package:moly_ide/features/auth/presentation/cubit/auth_state.dart';

class AuthCubit extends Cubit<AuthState> {
  final OrchestratorApiClient apiClient;
  final FlutterSecureStorage secureStorage;

  static const String userStorageKey = 'authenticated_user_profile';
  static const String vaultEmailKey = 'vault_saved_email';
  static const String vaultPasswordKey = 'vault_saved_password';
  static const String vaultRememberKey = 'vault_remember_credentials';

  AuthCubit({
    required this.apiClient,
    required this.secureStorage,
  }) : super(const AuthState());

  Future<void> checkAuth() async {
    emit(state.copyWith(status: AuthStatus.checking));
    try {
      final token = await secureStorage.read(key: OrchestratorApiClient.storageKeyAuthToken);
      final userJson = await secureStorage.read(key: userStorageKey);
      final savedEmail = await secureStorage.read(key: vaultEmailKey);
      final savedPassword = await secureStorage.read(key: vaultPasswordKey);
      final rememberStr = await secureStorage.read(key: vaultRememberKey);
      final remember = rememberStr != 'false';

      if (token != null && token.isNotEmpty && userJson != null) {
        final user = AuthUserModel.fromJson(jsonDecode(userJson));
        emit(state.copyWith(
          status: AuthStatus.authenticated,
          token: token,
          user: user,
          savedEmail: savedEmail,
          savedPassword: savedPassword,
          rememberCredentials: remember,
          currentServerUrl: apiClient.currentBaseUrl,
        ));
      } else {
        emit(state.copyWith(
          status: AuthStatus.unauthenticated,
          savedEmail: savedEmail,
          savedPassword: savedPassword,
          rememberCredentials: remember,
          currentServerUrl: apiClient.currentBaseUrl,
        ));
      }
    } catch (_) {
      emit(state.copyWith(
        status: AuthStatus.unauthenticated,
        currentServerUrl: apiClient.currentBaseUrl,
      ));
    }
  }

  void updateServerUrl(String url) {
    apiClient.updateBaseUrl(url);
    emit(state.copyWith(currentServerUrl: url));
  }

  void toggleRememberCredentials(bool value) {
    emit(state.copyWith(rememberCredentials: value));
  }

  Future<void> login({
    required String email,
    required String password,
    bool remember = true,
  }) async {
    emit(state.copyWith(status: AuthStatus.loading, errorMessage: null));
    try {
      final resp = await apiClient.dio.post('/auth/login', data: {
        'email': email.trim(),
        'password': password,
      });

      final token = resp.data['access_token']?.toString() ?? '';
      final user = AuthUserModel.fromJson(resp.data['user']);

      // 1. Guardar token y perfil activo
      await apiClient.setAuthToken(token);
      await secureStorage.write(key: userStorageKey, value: jsonEncode(user.toJson()));

      // 2. Guardar en el baúl si el usuario tiene activado recordar
      if (remember) {
        await secureStorage.write(key: vaultEmailKey, value: email.trim());
        await secureStorage.write(key: vaultPasswordKey, value: password);
        await secureStorage.write(key: vaultRememberKey, value: 'true');
      } else {
        await secureStorage.delete(key: vaultEmailKey);
        await secureStorage.delete(key: vaultPasswordKey);
        await secureStorage.write(key: vaultRememberKey, value: 'false');
      }

      emit(state.copyWith(
        status: AuthStatus.authenticated,
        token: token,
        user: user,
        savedEmail: remember ? email.trim() : null,
        savedPassword: remember ? password : null,
        rememberCredentials: remember,
      ));
    } catch (e) {
      emit(state.copyWith(
        status: AuthStatus.failure,
        errorMessage: 'Credenciales inválidas o error de conexión.',
      ));
    }
  }

  Future<void> logout({bool keepVaultCredentials = true}) async {
    await secureStorage.delete(key: OrchestratorApiClient.storageKeyAuthToken);
    await secureStorage.delete(key: userStorageKey);

    if (!keepVaultCredentials) {
      await secureStorage.delete(key: vaultEmailKey);
      await secureStorage.delete(key: vaultPasswordKey);
    }

    final savedEmail = await secureStorage.read(key: vaultEmailKey);
    final savedPassword = await secureStorage.read(key: vaultPasswordKey);

    emit(state.copyWith(
      status: AuthStatus.unauthenticated,
      user: null,
      token: null,
      savedEmail: savedEmail,
      savedPassword: savedPassword,
    ));
  }
}
