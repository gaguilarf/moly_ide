import 'package:moly_ide/features/auth/data/models/auth_user_model.dart';

enum AuthStatus {
  initial,
  checking,
  authenticated,
  unauthenticated,
  loading,
  failure,
}

class AuthState {
  final AuthStatus status;
  final AuthUserModel? user;
  final String? token;
  final String currentServerUrl;
  final String? savedEmail;
  final String? savedPassword;
  final bool rememberCredentials;
  final String? errorMessage;

  const AuthState({
    this.status = AuthStatus.initial,
    this.user,
    this.token,
    this.currentServerUrl = 'http://192.168.0.109:8000',
    this.savedEmail,
    this.savedPassword,
    this.rememberCredentials = true,
    this.errorMessage,
  });

  AuthState copyWith({
    AuthStatus? status,
    AuthUserModel? user,
    String? token,
    String? currentServerUrl,
    String? savedEmail,
    String? savedPassword,
    bool? rememberCredentials,
    String? errorMessage,
    bool clearSession = false,
    bool clearSavedCredentials = false,
  }) {
    return AuthState(
      status: status ?? this.status,
      // Con `??` no había forma de volver a null: al cerrar sesión el JWT y el
      // perfil seguían en el estado, y `clearSavedCredentials: false` dejaba
      // ahí la contraseña aunque se hubiera pedido vaciar el baúl.
      user: clearSession ? null : (user ?? this.user),
      token: clearSession ? null : (token ?? this.token),
      currentServerUrl: currentServerUrl ?? this.currentServerUrl,
      savedEmail: clearSavedCredentials
          ? null
          : (savedEmail ?? this.savedEmail),
      savedPassword: clearSavedCredentials
          ? null
          : (savedPassword ?? this.savedPassword),
      rememberCredentials: rememberCredentials ?? this.rememberCredentials,
      errorMessage: errorMessage,
    );
  }
}
