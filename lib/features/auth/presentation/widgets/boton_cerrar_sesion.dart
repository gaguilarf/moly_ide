import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/auth/presentation/cubit/auth_cubit.dart';

/// Última acción de la barra superior, a la derecha del botón de recargar.
///
/// Va en las seis pestañas que tienen barra en vez de solo en una: todas
/// enseñan los mismos botones, y tener la salida en una sola obligaría a buscar
/// en cuál. Se pide confirmación porque en un móvil el botón está a un roce del
/// de recargar.
class BotonCerrarSesion extends StatelessWidget {
  const BotonCerrarSesion({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.logout_rounded, color: AppTheme.accentBlue),
      tooltip: 'Cerrar sesión',
      onPressed: () => _confirmar(context),
    );
  }

  void _confirmar(BuildContext context) {
    // Se toma antes de abrir el diálogo: el `context` del diálogo cuelga del
    // Navigator, no del árbol donde vive el AuthCubit.
    final authCubit = context.read<AuthCubit>();

    showDialog<void>(
      context: context,
      builder: (dialContext) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: Text(
          'Cerrar sesión',
          style: GoogleFonts.outfit(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        content: Text(
          'Volverás a la pantalla de acceso. Tus credenciales guardadas se '
          'conservan, así que entrar de nuevo es un toque.',
          style: GoogleFonts.outfit(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialContext);
              authCubit.logout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252),
            ),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }
}
