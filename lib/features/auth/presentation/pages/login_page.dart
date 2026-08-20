import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:moly_ide/features/auth/presentation/cubit/auth_state.dart';
import 'package:moly_ide/features/updates/presentation/widgets/update_dialog.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberCredentials = true;
  bool _initializedFromVault = false;

  void _populateFromVault(AuthState state) {
    if (!_initializedFromVault) {
      if (state.savedUsername != null && state.savedUsername!.isNotEmpty) {
        _usernameController.text = state.savedUsername!;
      }
      if (state.savedPassword != null && state.savedPassword!.isNotEmpty) {
        _passwordController.text = state.savedPassword!;
      }
      _rememberCredentials = state.rememberCredentials;
      _initializedFromVault = true;
    }
  }

  void _handleLogin() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ingresa tu usuario y contraseña.',
            style: GoogleFonts.outfit(),
          ),
          backgroundColor: const Color(0xFFFF3366),
        ),
      );
      return;
    }

    context.read<AuthCubit>().login(
      username: username,
      password: password,
      remember: _rememberCredentials,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: BlocConsumer<AuthCubit, AuthState>(
        listener: (context, state) {
          _populateFromVault(state);
          // Al entrar NO se empuja nada: AuthGate, que es la ruta raíz, ya
          // cambia esta pantalla por MainNavigationPage cuando el estado pasa a
          // autenticado. El `pushReplacement` que había aquí reemplazaba esa
          // ruta raíz, destruyendo AuthGate — y con él, lo único que sabía
          // volver al acceso. Por eso cerrar sesión no podía funcionar.
          if (state.status == AuthStatus.failure &&
              state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!, style: GoogleFonts.outfit()),
                backgroundColor: const Color(0xFFFF3366),
              ),
            );
          }
        },
        builder: (context, state) {
          _populateFromVault(state);
          final isLoading = state.status == AuthStatus.loading;

          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24.0,
                  vertical: 16.0,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Brand Icon & Title
                    Center(
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppTheme.purpleBlueGradient,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.primaryPurple.withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        'RAGNAR GROUP',
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          foreground: Paint()
                            ..shader = AppTheme.purpleBlueGradient.createShader(
                              const Rect.fromLTWH(0.0, 0.0, 200.0, 30.0),
                            ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: Text(
                        'Control Móvil & Agentes Claude en Jetson',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Aviso de sesión caducada. Va pintado desde el estado y no
                    // por el listener de arriba: cuando el token se rechaza,
                    // esta pantalla todavía no está montada en el momento del
                    // emit, así que un SnackBar no llegaría a verse nunca.
                    if (state.status == AuthStatus.unauthenticated &&
                        state.errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(
                            0xFFFFB74D,
                          ).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFFFB74D)),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.lock_clock_rounded,
                              size: 18,
                              color: Color(0xFFFFB74D),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                state.errorMessage!,
                                style: GoogleFonts.outfit(
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // Login Card
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppTheme.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.3),
                            blurRadius: 16,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Iniciar Sesión',
                                style: GoogleFonts.outfit(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const Spacer(),
                              if (state.savedUsername != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF00FF66,
                                    ).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.lock_rounded,
                                        size: 12,
                                        color: Color(0xFF00FF66),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Baúl Cargado',
                                        style: GoogleFonts.firaCode(
                                          fontSize: 10,
                                          color: const Color(0xFF00FF66),
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Usuario
                          TextField(
                            controller: _usernameController,
                            keyboardType: TextInputType.text,
                            autocorrect: false,
                            textCapitalization: TextCapitalization.none,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Usuario',
                              hintText: 'gaguilar',
                              prefixIcon: const Icon(
                                Icons.person_rounded,
                                color: AppTheme.accentBlue,
                                size: 20,
                              ),
                              filled: true,
                              fillColor: AppTheme.surfaceLight,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Password Input
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Contraseña',
                              prefixIcon: const Icon(
                                Icons.lock_rounded,
                                color: AppTheme.primaryPurple,
                                size: 20,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  color: AppTheme.textSecondary,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                              filled: true,
                              fillColor: AppTheme.surfaceLight,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onSubmitted: (_) => _handleLogin(),
                          ),
                          const SizedBox(height: 10),

                          // Remember credentials switch
                          Row(
                            children: [
                              SizedBox(
                                height: 24,
                                width: 24,
                                child: Checkbox(
                                  value: _rememberCredentials,
                                  activeColor: AppTheme.primaryPurple,
                                  onChanged: (val) {
                                    setState(
                                      () => _rememberCredentials = val ?? true,
                                    );
                                    context
                                        .read<AuthCubit>()
                                        .toggleRememberCredentials(
                                          _rememberCredentials,
                                        );
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(
                                  () => _rememberCredentials =
                                      !_rememberCredentials,
                                ),
                                child: Text(
                                  'Guardar credenciales en el baúl seguro',
                                  style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),

                          // Login Button
                          Container(
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: AppTheme.purpleBlueGradient,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: ElevatedButton(
                              onPressed: isLoading ? null : _handleLogin,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.transparent,
                                shadowColor: Colors.transparent,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        color: Colors.white,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      'ENTRAR AL PANEL',
                                      style: GoogleFonts.outfit(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.white,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Quick Update Button
                    Center(
                      child: TextButton.icon(
                        onPressed: () => UpdateDialog.show(context),
                        icon: const Icon(
                          Icons.system_update_rounded,
                          size: 16,
                          color: AppTheme.accentBlue,
                        ),
                        label: Text(
                          'Buscar Actualización de la App',
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            color: AppTheme.accentBlue,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
