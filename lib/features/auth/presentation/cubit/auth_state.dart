import 'package:moly_ide/features/auth/data/models/auth_user_model.dart';

enum AuthStatus { initial, checking, authenticated, unauthenticated, loading, failure }

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
  }) {
    return AuthState(
      status: status ?? this.status,
      user: user ?? this.user,
      token: token ?? this.token,
      currentServerUrl: currentServerUrl ?? this.currentServerUrl,
      savedEmail: savedEmail ?? this.savedEmail,
      savedPassword: savedPassword ?? this.savedPassword,
      rememberCredentials: rememberCredentials ?? this.rememberCredentials,
      errorMessage: errorMessage,
    );
  }
}
