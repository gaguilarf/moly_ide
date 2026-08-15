import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';
import 'package:moly_ide/core/di/injection.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:moly_ide/features/auth/presentation/cubit/auth_state.dart';
import 'package:moly_ide/features/auth/presentation/pages/login_page.dart';
import 'package:moly_ide/features/main_navigation/presentation/pages/main_navigation_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initDependencies();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<AuthCubit>(
      create: (context) => AuthCubit(
        apiClient: locator<OrchestratorApiClient>(),
        secureStorage: locator<FlutterSecureStorage>(),
      )..checkAuth(),
      child: MaterialApp(
        title: 'Moly Control Center',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const AuthGate(),
      ),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        if (state.status == AuthStatus.checking) {
          return const Scaffold(
            backgroundColor: AppTheme.background,
            body: Center(
              child: CircularProgressIndicator(color: AppTheme.accentBlue),
            ),
          );
        }

        if (state.status == AuthStatus.authenticated) {
          return const MainNavigationPage();
        }

        return const LoginPage();
      },
    );
  }
}
