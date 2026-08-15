import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/auth/presentation/cubit/auth_cubit.dart';
import 'package:moly_ide/features/auth/presentation/cubit/auth_state.dart';
import 'package:moly_ide/features/main_navigation/presentation/pages/main_navigation_page.dart';
import 'package:moly_ide/features/updates/presentation/widgets/update_dialog.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverUrlController = TextEditingController();
  bool _obscurePassword = true;
  bool _showAdvancedServer = false;
  bool _rememberCredentials = true;
  bool _initializedFromVault = false;

  @override
  void initState() {
    super.initState();
    _serverUrlController.text = context.read<AuthCubit>().state.currentServerUrl;
  }

  void _populateFromVault(AuthState state) {
    if (!_initializedFromVault) {
      if (state.savedEmail != null && state.savedEmail!.isNotEmpty) {
        _emailController.text = state.savedEmail!;
      }
      if (state.savedPassword != null && state.savedPassword!.isNotEmpty) {
        _passwordController.text = state.savedPassword!;
      }
      _rememberCredentials = state.rememberCredentials;
      _initializedFromVault = true;
    }
  }

  void _handleLogin() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ingresa tu correo y contraseña.', style: GoogleFonts.outfit()),
          backgroundColor: const Color(0xFFFF3366),
        ),
      );
      return;
    }

    if (_showAdvancedServer) {
      context.read<AuthCubit>().updateServerUrl(_serverUrlController.text.trim());
    }

    context.read<AuthCubit>().login(
          email: email,
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
          if (state.status == AuthStatus.authenticated) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const MainNavigationPage()),
            );
          }
          if (state.status == AuthStatus.failure && state.errorMessage != null) {
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
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
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
                        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 36),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Text(
                        'MOLY ORCHESTRATOR',
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
                        style: GoogleFonts.outfit(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    ),
                    const SizedBox(height: 32),

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
                                style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const Spacer(),
                              if (state.savedEmail != null)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF00FF66).withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.lock_rounded, size: 12, color: Color(0xFF00FF66)),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Baúl Cargado',
                                        style: GoogleFonts.firaCode(fontSize: 10, color: const Color(0xFF00FF66), fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Email Input
                          TextField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(color: Colors.white),
                            decoration: InputDecoration(
                              labelText: 'Correo electrónico',
                              hintText: 'admin@brittanygroup.edu.pe',
                              prefixIcon: const Icon(Icons.email_rounded, color: AppTheme.accentBlue, size: 20),
                              filled: true,
                              fillColor: AppTheme.surfaceLight,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
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
                              prefixIcon: const Icon(Icons.lock_rounded, color: AppTheme.primaryPurple, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                                  color: AppTheme.textSecondary,
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                              filled: true,
                              fillColor: AppTheme.surfaceLight,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
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
                                    setState(() => _rememberCredentials = val ?? true);
                                    context.read<AuthCubit>().toggleRememberCredentials(_rememberCredentials);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => setState(() => _rememberCredentials = !_rememberCredentials),
                                child: Text(
                                  'Guardar credenciales en el baúl seguro',
                                  style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.textSecondary),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // Advanced Server Toggle
                          GestureDetector(
                            onTap: () => setState(() => _showAdvancedServer = !_showAdvancedServer),
                            child: Row(
                              children: [
                                Icon(
                                  _showAdvancedServer ? Icons.arrow_drop_down_rounded : Icons.arrow_right_rounded,
                                  color: AppTheme.accentBlue,
                                ),
                                Text(
                                  'Servidor Jetson (LAN / Tailscale)',
                                  style: GoogleFonts.firaCode(fontSize: 11, color: AppTheme.accentBlue),
                                ),
                              ],
                            ),
                          ),

                          if (_showAdvancedServer) ...[
                            const SizedBox(height: 10),
                            TextField(
                              controller: _serverUrlController,
                              style: GoogleFonts.firaCode(fontSize: 12, color: Colors.white),
                              decoration: InputDecoration(
                                labelText: 'URL del Backend Jetson',
                                hintText: 'http://192.168.0.109:8000',
                                filled: true,
                                fillColor: AppTheme.surfaceLight,
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                ActionChip(
                                  label: Text('LAN', style: GoogleFonts.firaCode(fontSize: 10)),
                                  onPressed: () {
                                    _serverUrlController.text = 'http://192.168.0.109:8000';
                                  },
                                ),
                                const SizedBox(width: 6),
                                ActionChip(
                                  label: Text('Tailscale', style: GoogleFonts.firaCode(fontSize: 10)),
                                  onPressed: () {
                                    _serverUrlController.text = 'http://jetson-desktop.tail452840.ts.net:8000';
                                  },
                                ),
                              ],
                            ),
                          ],

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
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              child: isLoading
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                    )
                                  : Text(
                                      'ENTRAR AL PANEL',
                                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.white),
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
                        icon: const Icon(Icons.system_update_rounded, size: 16, color: AppTheme.accentBlue),
                        label: Text(
                          'Buscar Actualización de la App',
                          style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.accentBlue),
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
