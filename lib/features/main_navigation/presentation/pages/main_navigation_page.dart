import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/di/injection.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';
import 'package:moly_ide/core/api/websocket_service.dart';
import 'package:moly_ide/features/tickets/presentation/cubit/tickets_cubit.dart';
import 'package:moly_ide/features/tickets/presentation/pages/tickets_page.dart';
import 'package:moly_ide/features/claude_agent/presentation/cubit/claude_cubit.dart';
import 'package:moly_ide/features/claude_agent/presentation/pages/claude_agent_page.dart';
import 'package:moly_ide/features/infrastructure/presentation/cubit/infra_cubit.dart';
import 'package:moly_ide/features/infrastructure/presentation/pages/infrastructure_page.dart';
import 'package:moly_ide/features/backups/presentation/cubit/backups_cubit.dart';
import 'package:moly_ide/features/backups/presentation/pages/backups_page.dart';
import 'package:moly_ide/features/documentation/presentation/cubit/docs_cubit.dart';
import 'package:moly_ide/features/documentation/presentation/pages/docs_page.dart';
import 'package:moly_ide/features/explorer_readonly/presentation/cubit/readonly_explorer_cubit.dart';
import 'package:moly_ide/features/explorer_readonly/presentation/pages/readonly_explorer_page.dart';
import 'package:moly_ide/core/ssh/ssh_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:moly_ide/features/connection/presentation/cubit/connection_cubit.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/pages/ide_gate.dart';

class MainNavigationPage extends StatefulWidget {
  const MainNavigationPage({super.key});

  @override
  State<MainNavigationPage> createState() => _MainNavigationPageState();
}

class _MainNavigationPageState extends State<MainNavigationPage> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    TicketsPage(),
    ClaudeAgentPage(),
    InfrastructurePage(),
    BackupsPage(),
    DocsPage(),
    ReadonlyExplorerPage(),
    IdeGate(),
  ];

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<TicketsCubit>(
          create: (context) =>
              TicketsCubit(apiClient: locator<OrchestratorApiClient>()),
        ),
        BlocProvider<ClaudeCubit>(
          create: (context) => ClaudeCubit(
            apiClient: locator<OrchestratorApiClient>(),
            wsService: locator<WebSocketService>(),
          ),
        ),
        BlocProvider<InfraCubit>(
          create: (context) =>
              InfraCubit(apiClient: locator<OrchestratorApiClient>()),
        ),
        BlocProvider<BackupsCubit>(
          create: (context) =>
              BackupsCubit(apiClient: locator<OrchestratorApiClient>()),
        ),
        BlocProvider<DocsCubit>(
          create: (context) =>
              DocsCubit(apiClient: locator<OrchestratorApiClient>()),
        ),
        BlocProvider<ReadonlyExplorerCubit>(
          create: (context) => ReadonlyExplorerCubit(
            apiClient: locator<OrchestratorApiClient>(),
          ),
        ),
        // La sesión SSH es de la pestaña IDE, pero se provee aquí porque tiene
        // que sobrevivir a cambiar de pestaña: si naciera dentro de IdeGate,
        // salir a Tickets y volver reconstruiría el cubit y pediría el servidor
        // otra vez con la conexión todavía abierta.
        BlocProvider<ConnectionCubit>(
          create: (context) => ConnectionCubit(
            sshService: locator<SSHService>(),
            secureStorage: locator<FlutterSecureStorage>(),
          ),
        ),
      ],
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: IndexedStack(index: _currentIndex, children: _pages),
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: AppTheme.surface,
            border: Border(top: BorderSide(color: AppTheme.border, width: 1.0)),
          ),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) => setState(() => _currentIndex = index),
            backgroundColor: Colors.transparent,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: AppTheme.accentBlue,
            unselectedItemColor: AppTheme.textSecondary,
            selectedLabelStyle: GoogleFonts.outfit(
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
            unselectedLabelStyle: GoogleFonts.outfit(fontSize: 10),
            elevation: 0,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.view_kanban_rounded),
                label: 'Tickets',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.auto_awesome_rounded),
                label: 'Claude',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.router_rounded),
                label: 'Puertos',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.backup_rounded),
                label: 'Backups',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.menu_book_rounded),
                label: 'Docs',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.folder_copy_rounded),
                label: 'Explorador',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.terminal_rounded),
                label: 'IDE',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
