import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:moly_ide/core/di/injection.dart';
import 'package:moly_ide/core/ssh/ssh_service.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/connection/presentation/cubit/connection_cubit.dart';
import 'package:moly_ide/features/connection/presentation/pages/connection_page.dart';

void main() async {
  // Ensure Flutter engine bindings are fully initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize inyector (GetIt) and global singletons (SSHService, SecureStorage)
  await initDependencies();
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ConnectionCubit>(
      create: (context) => ConnectionCubit(
        sshService: locator<SSHService>(),
        secureStorage: locator<FlutterSecureStorage>(),
      ),
      child: MaterialApp(
        title: 'Moly IDE',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.darkTheme,
        home: const ConnectionPage(),
      ),
    );
  }
}
