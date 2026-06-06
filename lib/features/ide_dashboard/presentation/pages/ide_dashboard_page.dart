import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:moly_ide/core/di/injection.dart';
import 'package:moly_ide/core/ssh/ssh_service.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/connection/presentation/cubit/connection_cubit.dart';
import 'package:moly_ide/features/connection/presentation/pages/connection_page.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/cubit/ide_cubit.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/cubit/ide_state.dart';
import 'package:moly_ide/features/explorer/presentation/widgets/file_explorer_widget.dart';
import 'package:moly_ide/features/editor/presentation/widgets/code_editor_widget.dart';
import 'package:moly_ide/features/terminal/presentation/widgets/terminal_widget.dart';
import 'package:moly_ide/features/terminal/presentation/widgets/floating_dpad_widget.dart';

class IDEDashboardPage extends StatelessWidget {
  const IDEDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider<IDECubit>(
      create: (context) => IDECubit(sshService: locator<SSHService>()),
      child: const IDEDashboardView(),
    );
  }
}

class IDEDashboardView extends StatefulWidget {
  const IDEDashboardView({super.key});

  @override
  State<IDEDashboardView> createState() => _IDEDashboardViewState();
}

class _IDEDashboardViewState extends State<IDEDashboardView> {
  String _appVersion = '';
  double _dpadLeft = 12.0;
  double _dpadBottom = 12.0;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _appVersion = '${info.version}+${info.buildNumber}');
    });
  }

  void _handleDisconnect(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialContext) => AlertDialog(
        title: Text('Desconectar VPS',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: const Text(
            '¿Estás seguro de que deseas cerrar la sesión SSH y desconectarte del servidor VPS?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialContext);
              context.read<ConnectionCubit>().disconnect();
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                    builder: (context) => const ConnectionPage()),
              );
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5252)),
            child: const Text('Desconectar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sshService = locator<SSHService>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: BlocListener<IDECubit, IDEState>(
        listenWhen: (previous, current) => current.errorMessage != null,
        listener: (context, state) {
          if (state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                backgroundColor: const Color(0xFFFF5252),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                    borderRadius: AppTheme.borderRadius),
                content: Text(
                  state.errorMessage!,
                  style: GoogleFonts.outfit(color: Colors.white),
                ),
              ),
            );
            context.read<IDECubit>().clearError();
          }
        },
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(context, sshService),
              Expanded(
                child: BlocBuilder<IDECubit, IDEState>(
                  builder: (context, state) {
                    final double screenWidth =
                        MediaQuery.of(context).size.width;
                    final double editorWidth =
                        (screenWidth * 0.85).clamp(280.0, 600.0);

                    return Stack(
                      children: [
                        const Positioned.fill(child: TerminalWidget()),

                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          left: state.isExplorerOpen ? 0.0 : -260.0,
                          top: 0,
                          bottom: 0,
                          width: 260.0,
                          child: const FileExplorerWidget(),
                        ),

                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          right: state.isEditorOpen ? 0.0 : -editorWidth,
                          top: 0,
                          bottom: 0,
                          width: editorWidth,
                          child: const CodeEditorWidget(),
                        ),

                        if (!state.isExplorerOpen)
                          Positioned(
                            left: 0,
                            top: 120.0,
                            child: InkWell(
                              onTap: () =>
                                  context.read<IDECubit>().toggleExplorer(),
                              borderRadius: BorderRadius.only(
                                topRight: AppTheme.radius,
                                bottomRight: AppTheme.radius,
                              ),
                              child: Container(
                                width: 20,
                                height: 60,
                                decoration: BoxDecoration(
                                  gradient: AppTheme.purpleBlueGradient,
                                  borderRadius: BorderRadius.only(
                                    topRight: AppTheme.radius,
                                    bottomRight: AppTheme.radius,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryPurple
                                          .withOpacity(0.4),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.chevron_right,
                                    color: Colors.white, size: 16),
                              ),
                            ),
                          ),

                        if (!state.isEditorOpen && state.openTabs.isNotEmpty)
                          Positioned(
                            right: 0,
                            top: 120.0,
                            child: InkWell(
                              onTap: () =>
                                  context.read<IDECubit>().toggleEditor(),
                              borderRadius: BorderRadius.only(
                                topLeft: AppTheme.radius,
                                bottomLeft: AppTheme.radius,
                              ),
                              child: Container(
                                width: 20,
                                height: 60,
                                decoration: BoxDecoration(
                                  gradient: AppTheme.purpleBlueGradient,
                                  borderRadius: BorderRadius.only(
                                    topLeft: AppTheme.radius,
                                    bottomLeft: AppTheme.radius,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryPurple
                                          .withOpacity(0.4),
                                      blurRadius: 8,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: const Icon(Icons.chevron_left,
                                    color: Colors.white, size: 16),
                              ),
                            ),
                          ),

                        Positioned(
                          left: _dpadLeft,
                          bottom: _dpadBottom,
                          child: FloatingDpadWidget(
                            key: const ValueKey('dpad'),
                            onDragUpdate: (delta) {
                              final size = MediaQuery.of(context).size;
                              setState(() {
                                _dpadLeft = (_dpadLeft + delta.dx).clamp(0.0, size.width - 44.0);
                                _dpadBottom = (_dpadBottom - delta.dy).clamp(0.0, size.height - 100.0);
                              });
                            },
                          ),
                        ),

                        if (state.loadingFileMessage != null)
                          Container(
                            color: Colors.black.withOpacity(0.5),
                            child: Center(
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24.0, vertical: 20.0),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.0,
                                          color: AppTheme.accentBlue,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        state.loadingFileMessage!,
                                        style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                        if (state.savingFileMessage != null)
                          Container(
                            color: Colors.black.withOpacity(0.5),
                            child: Center(
                              child: Card(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24.0, vertical: 20.0),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.0,
                                          color: AppTheme.primaryPurple,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Text(
                                        state.savingFileMessage!,
                                        style: GoogleFonts.outfit(
                                            fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, SSHService sshService) {
    final double width = MediaQuery.of(context).size.width;
    final isMobile = width < 600;

    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.developer_mode_rounded,
              color: AppTheme.accentBlue, size: 24),
          if (!isMobile) ...[
            const SizedBox(width: 8),
            Text(
              'Moly IDE',
              style: GoogleFonts.outfit(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                foreground: Paint()
                  ..shader = AppTheme.purpleBlueGradient.createShader(
                    const Rect.fromLTWH(0.0, 0.0, 100.0, 30.0),
                  ),
              ),
            ),
            const SizedBox(width: 6),
            if (_appVersion.isNotEmpty)
              Text(
                'v$_appVersion',
                style: GoogleFonts.firaCode(
                  fontSize: 10,
                  color: AppTheme.textSecondary.withOpacity(0.5),
                ),
              ),
          ],
          const SizedBox(width: 16),

          Container(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 8.0 : 10.0,
              vertical: isMobile ? 8.0 : 6.0,
            ),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: AppTheme.borderRadius,
              border: Border.all(color: AppTheme.border, width: 1.0),
            ),
            child: isMobile
                ? Tooltip(
                    message: '${sshService.username}@${sshService.host}',
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF00FF66),
                        shape: BoxShape.circle,
                      ),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF00FF66),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${sshService.username}@${sshService.host}',
                        style: GoogleFonts.firaCode(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
          ),

          const Spacer(),

          BlocBuilder<IDECubit, IDEState>(
            builder: (context, state) {
              final activeTab = state.activeTab;
              final canSave = activeTab != null && activeTab.isModified;

              return Row(
                children: [
                  if (width < 500)
                    IconButton(
                      icon: Icon(
                        Icons.save_rounded,
                        color: canSave
                            ? AppTheme.primaryPurple
                            : AppTheme.textSecondary.withOpacity(0.4),
                      ),
                      tooltip: 'Guardar Archivo',
                      onPressed: canSave
                          ? () => context.read<IDECubit>().saveActiveFile()
                          : null,
                    )
                  else
                    ElevatedButton.icon(
                      onPressed: canSave
                          ? () => context.read<IDECubit>().saveActiveFile()
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryPurple,
                        disabledBackgroundColor: AppTheme.surfaceLight,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 10),
                      ),
                      icon: const Icon(Icons.save_rounded, size: 16),
                      label: Text(
                        'GUARDAR',
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: canSave
                              ? Colors.white
                              : AppTheme.textSecondary.withOpacity(0.5),
                        ),
                      ),
                    ),

                  const SizedBox(width: 8),

                  if (width < 500)
                    IconButton(
                      icon: const Icon(Icons.power_settings_new_rounded,
                          color: Color(0xFFFF5252)),
                      tooltip: 'Desconectar',
                      onPressed: () => _handleDisconnect(context),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => _handleDisconnect(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        side: const BorderSide(
                            color: Color(0xFFFF5252), width: 1.0),
                        foregroundColor: const Color(0xFFFF5252),
                      ),
                      icon: const Icon(Icons.power_settings_new_rounded,
                          size: 16),
                      label: Text(
                        'SALIR',
                        style: GoogleFonts.outfit(
                            fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

