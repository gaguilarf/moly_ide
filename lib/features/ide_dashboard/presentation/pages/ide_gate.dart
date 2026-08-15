// Flutter tiene su propio `ConnectionState` (el de los snapshots de Future y
// Stream). Se esconde el de material para poder llamar al nuestro por su
// nombre sin que el analizador no sepa a cuál nos referimos.
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moly_ide/features/connection/presentation/cubit/connection_cubit.dart';
import 'package:moly_ide/features/connection/presentation/cubit/connection_state.dart';
import 'package:moly_ide/features/connection/presentation/pages/connection_page.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/pages/ide_dashboard_page.dart';

/// Pestaña «IDE»: enseña el formulario de conexión o el escritorio, según haya
/// sesión SSH abierta.
///
/// Antes esto lo hacía la navegación por rutas: `ConnectionPage` era el `home`
/// de la app y empujaba el escritorio al conectar. Cuando `AuthGate` pasó a ser
/// el `home`, las dos pantallas se quedaron sin nadie que las abriera —y con
/// ellas el terminal, el editor y el explorador SSH, que no viven en ningún
/// otro sitio—. Aquí el estado del cubit decide cuál se ve, así que ninguna de
/// las dos necesita empujar ni reemplazar rutas.
class IdeGate extends StatelessWidget {
  const IdeGate({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectionCubit, ConnectionState>(
      builder: (context, state) {
        if (state is! ConnectionSuccess) return const ConnectionPage();

        // La key lleva el servidor: al reconectar contra otro host se levanta
        // un IDECubit nuevo. Sin ella se reaprovecharía el de la conexión
        // anterior, con su directorio y sus pestañas abiertas del servidor
        // viejo.
        return IDEDashboardPage(
          key: ValueKey('${state.username}@${state.host}'),
        );
      },
    );
  }
}
