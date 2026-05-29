import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/connection/presentation/cubit/connection_cubit.dart';
import 'package:moly_ide/features/connection/presentation/cubit/connection_state.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/pages/ide_dashboard_page.dart';

class ConnectionPage extends StatefulWidget {
  const ConnectionPage({super.key});

  @override
  State<ConnectionPage> createState() => _ConnectionPageState();
}

class _ConnectionPageState extends State<ConnectionPage> {
  final _formKey = GlobalKey<FormState>();
  
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;

  bool _isPasswordVisible = false;

  @override
  void initState() {
    super.initState();
    _hostController = TextEditingController();
    _portController = TextEditingController(text: '22');
    _usernameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submitForm(BuildContext context) {
    if (_formKey.currentState?.validate() ?? false) {
      context.read<ConnectionCubit>().connect(
            host: _hostController.text.trim(),
            portStr: _portController.text.trim(),
            username: _usernameController.text.trim(),
            password: _passwordController.text,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocListener<ConnectionCubit, ConnectionState>(
        listener: (context, state) {
          if (state is ConnectionInitial) {
            _hostController.text = state.host;
            _portController.text = state.port;
            _usernameController.text = state.username;
            _passwordController.text = state.password;
          } else if (state is ConnectionSuccess) {
            // Navigate to IDE Dashboard
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => const IDEDashboardPage()),
            );
          } else if (state is ConnectionFailure) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFFFF3333),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: AppTheme.borderRadius,
                ),
                content: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.white),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Conexión fallida: ${state.errorMessage}',
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w500),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
        },
        child: Container(
          decoration: const BoxDecoration(
            gradient: AppTheme.backgroundGradient,
          ),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Glowing logo and title
                    Center(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryPurple.withOpacity(0.1),
                              borderRadius: AppTheme.borderRadius,
                              border: Border.all(
                                color: AppTheme.primaryPurple.withOpacity(0.3),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: AppTheme.primaryPurple.withOpacity(0.2),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.developer_mode_rounded,
                              size: 48,
                              color: AppTheme.accentBlue,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Moly IDE',
                            style: GoogleFonts.outfit(
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              foreground: Paint()
                                ..shader = AppTheme.purpleBlueGradient.createShader(
                                  const Rect.fromLTWH(0.0, 0.0, 200.0, 70.0),
                                ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Entorno de Desarrollo Remoto Android',
                            style: Theme.of(context).textTheme.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Connection card
                    BlocBuilder<ConnectionCubit, ConnectionState>(
                      builder: (context, state) {
                        final isLoading = state is ConnectionLoading;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // Connection Card
                            Container(
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: AppTheme.surface,
                                borderRadius: AppTheme.borderRadius,
                                border: Border.all(color: AppTheme.border, width: 1.2),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 15,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 4,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            color: AppTheme.accentBlue,
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'CONECTAR A VPS',
                                          style: GoogleFonts.outfit(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 20),

                                    // Host and Port Inputs
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(
                                          flex: 3,
                                          child: TextFormField(
                                            controller: _hostController,
                                            enabled: !isLoading,
                                            decoration: const InputDecoration(
                                              labelText: 'Host / IP',
                                              hintText: 'vps.ejemplo.com o 192.168.1.10',
                                              prefixIcon: Icon(Icons.dns, size: 20, color: AppTheme.textSecondary),
                                            ),
                                            validator: (value) {
                                              if (value == null || value.trim().isEmpty) {
                                                return 'Requerido';
                                              }
                                              return null;
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          flex: 1,
                                          child: TextFormField(
                                            controller: _portController,
                                            enabled: !isLoading,
                                            keyboardType: TextInputType.number,
                                            decoration: const InputDecoration(
                                              labelText: 'Puerto',
                                              hintText: '22',
                                            ),
                                            validator: (value) {
                                              if (value == null || value.trim().isEmpty) {
                                                return 'Requerido';
                                              }
                                              if (int.tryParse(value) == null) {
                                                return 'Inválido';
                                              }
                                              return null;
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // Username Input
                                    TextFormField(
                                      controller: _usernameController,
                                      enabled: !isLoading,
                                      decoration: const InputDecoration(
                                        labelText: 'Usuario',
                                        hintText: 'root, ubuntu, etc.',
                                        prefixIcon: Icon(Icons.person, size: 20, color: AppTheme.textSecondary),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'Por favor ingresa el usuario';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 16),

                                    // Password Input
                                    TextFormField(
                                      controller: _passwordController,
                                      enabled: !isLoading,
                                      obscureText: !_isPasswordVisible,
                                      decoration: InputDecoration(
                                        labelText: 'Contraseña (SSH)',
                                        hintText: '••••••••',
                                        prefixIcon: const Icon(Icons.lock, size: 20, color: AppTheme.textSecondary),
                                        suffixIcon: IconButton(
                                          icon: Icon(
                                            _isPasswordVisible ? Icons.visibility_off : Icons.visibility,
                                            size: 20,
                                            color: AppTheme.textSecondary,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _isPasswordVisible = !_isPasswordVisible;
                                            });
                                          },
                                        ),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.isEmpty) {
                                          return 'Por favor ingresa la contraseña';
                                        }
                                        return null;
                                      },
                                    ),
                                    const SizedBox(height: 32),

                                    // Connect Button with Gradient & Loader
                                    Container(
                                      decoration: BoxDecoration(
                                        gradient: !isLoading ? AppTheme.purpleBlueGradient : null,
                                        color: isLoading ? AppTheme.surfaceLight : null,
                                        borderRadius: AppTheme.borderRadius,
                                        boxShadow: !isLoading
                                            ? [
                                                BoxShadow(
                                                  color: AppTheme.primaryPurple.withOpacity(0.3),
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ]
                                            : null,
                                      ),
                                      child: ElevatedButton(
                                        onPressed: isLoading ? null : () => _submitForm(context),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.transparent,
                                          shadowColor: Colors.transparent,
                                          padding: const EdgeInsets.symmetric(vertical: 16),
                                        ),
                                        child: isLoading
                                            ? Row(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: const [
                                                  SizedBox(
                                                    width: 20,
                                                    height: 20,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: AppTheme.accentBlue,
                                                    ),
                                                  ),
                                                  SizedBox(width: 12),
                                                  Text(
                                                    'CONECTANDO...',
                                                    style: TextStyle(
                                                      color: AppTheme.accentBlue,
                                                      fontWeight: FontWeight.bold,
                                                      letterSpacing: 1.0,
                                                    ),
                                                  ),
                                                ],
                                              )
                                            : const Text(
                                                'CONECTAR AL SERVIDOR',
                                                style: TextStyle(
                                                  color: Colors.white,
                                                  fontWeight: FontWeight.bold,
                                                  letterSpacing: 1.0,
                                                ),
                                              ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // Saved Connections Card (if not empty)
                            if (state.savedConnections.isNotEmpty) ...[
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: AppTheme.surface,
                                  borderRadius: AppTheme.borderRadius,
                                  border: Border.all(color: AppTheme.border, width: 1.2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.3),
                                      blurRadius: 15,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          width: 4,
                                          height: 18,
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryPurple,
                                            borderRadius: BorderRadius.circular(2),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          'CONEXIONES GUARDADAS',
                                          style: GoogleFonts.outfit(
                                            fontSize: 14,
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.textPrimary,
                                            letterSpacing: 1.0,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: state.savedConnections.length,
                                      separatorBuilder: (context, index) => const Divider(
                                        color: AppTheme.divider,
                                        height: 24,
                                      ),
                                      itemBuilder: (context, index) {
                                        final conn = state.savedConnections[index];
                                        return ListTile(
                                          contentPadding: EdgeInsets.zero,
                                          leading: Container(
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: AppTheme.primaryPurple.withOpacity(0.1),
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(
                                              Icons.dns_rounded,
                                              color: AppTheme.accentBlue,
                                              size: 20,
                                            ),
                                          ),
                                          title: Text(
                                            '${conn.username}@${conn.host}',
                                            style: GoogleFonts.outfit(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                          subtitle: Padding(
                                            padding: const EdgeInsets.only(top: 4.0),
                                            child: Text(
                                              'Puerto: ${conn.port}',
                                              style: GoogleFonts.firaCode(
                                                color: AppTheme.textSecondary,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                          trailing: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Load credentials button
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.input_rounded,
                                                  color: AppTheme.accentBlue,
                                                  size: 20,
                                                ),
                                                tooltip: 'Cargar Servidor',
                                                onPressed: isLoading
                                                    ? null
                                                    : () {
                                                        _hostController.text = conn.host;
                                                        _portController.text = conn.port;
                                                        _usernameController.text = conn.username;
                                                        _passwordController.text = conn.password;
                                                        ScaffoldMessenger.of(context).showSnackBar(
                                                          SnackBar(
                                                            content: Text(
                                                              'Credenciales de ${conn.host} cargadas.',
                                                              style: GoogleFonts.outfit(),
                                                            ),
                                                            duration: const Duration(seconds: 1),
                                                          ),
                                                        );
                                                      },
                                              ),
                                              // Delete connection button
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  color: Color(0xFFFF5252),
                                                  size: 20,
                                                ),
                                                tooltip: 'Eliminar',
                                                onPressed: isLoading
                                                    ? null
                                                    : () {
                                                        context
                                                            .read<ConnectionCubit>()
                                                            .deleteConnection(conn);
                                                      },
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
