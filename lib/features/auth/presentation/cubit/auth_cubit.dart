import 'dart:async';
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

  late final StreamSubscription<void> _sesionCaducada;

  AuthCubit({required this.apiClient, required this.secureStorage})
    : super(const AuthState()) {
    _sesionCaducada = apiClient.sesionCaducada.listen(
      (_) => _cerrarPorTokenRechazado(),
    );
  }

  /// El servidor rechazó el token (401): la sesión se cierra sola y se vuelve a
  /// la pantalla de acceso. Se conserva el baúl, así que volver a entrar es un
  /// toque.
  Future<void> _cerrarPorTokenRechazado() async {
    // Si ya no había sesión, no hay nada que cerrar: un 401 suelto mientras se
    // está en el acceso pisaría el error que esa pantalla ya está enseñando.
    if (state.status != AuthStatus.authenticated) return;

    await logout();
    emit(
      state.copyWith(errorMessage: 'Tu sesión ha caducado. Vuelve a entrar.'),
    );
  }

  @override
  Future<void> close() {
    _sesionCaducada.cancel();
    return super.close();
  }

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
          ),
        );
      }
    } catch (_) {
      emit(
        state.copyWith(status: AuthStatus.unauthenticated, clearSession: true),
      );
    }
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
          errorMessage: _porQueFalloElAcceso(e),
        ),
      );
    }
  }

  /// Distingue «no llego al servidor» de «la contraseña está mal».
  ///
  /// Antes las dos cosas decían «Credenciales inválidas o error de conexión»,
  /// así que quien entraba desde fuera de la LAN —con la dirección del servidor
  /// por defecto, que no le enruta— se pasaba el rato probando contraseñas
  /// buenas sin ninguna pista de que el problema era la dirección.
  String _porQueFalloElAcceso(Object e) {
    if (e is! DioException) return 'No se pudo entrar: $e';

    final codigo = e.response?.statusCode;
    if (codigo == 401 || codigo == 403) {
      return 'Usuario o contraseña incorrectos.';
    }
    if (codigo != null) {
      final detalle = e.response?.data;
      if (detalle is Map && detalle['detail'] is String) {
        return 'El servidor rechazó el acceso: ${detalle['detail']}';
      }
      return 'El servidor respondió HTTP $codigo.';
    }

    return 'No se pudo conectar con ${apiClient.currentBaseUrl}. '
        'Comprueba que Tailscale esté conectado.';
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
