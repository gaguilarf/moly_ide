import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Texto en markdown con los estilos del tema oscuro.
///
/// Claude responde en markdown —negritas, encabezados, listas, bloques de
/// código—, y pintarlo como texto plano dejaba los asteriscos y las almohadillas
/// a la vista: en un chat eso se lee como ruido, no como formato. La
/// documentación viva guarda sus cuerpos igual.
class TextoMarkdown extends StatelessWidget {
  const TextoMarkdown(this.datos, {super.key, this.colorTexto});

  final String datos;
  final Color? colorTexto;

  @override
  Widget build(BuildContext context) {
    final color = colorTexto ?? Colors.white70;

    return MarkdownBody(
      data: datos,
      selectable: true,
      onTapLink: (texto, href, titulo) async {
        if (href == null) return;
        final destino = Uri.tryParse(href);
        if (destino == null) return;
        // Se comprueba antes de lanzar: sin esto, un enlace que el dispositivo
        // no sabe abrir revienta en vez de no hacer nada.
        if (await canLaunchUrl(destino)) {
          await launchUrl(destino, mode: LaunchMode.externalApplication);
        }
      },
      styleSheet: MarkdownStyleSheet(
        p: GoogleFonts.outfit(fontSize: 14, color: color, height: 1.45),
        strong: GoogleFonts.outfit(
          fontSize: 14,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        em: GoogleFonts.outfit(
          fontSize: 14,
          color: color,
          fontStyle: FontStyle.italic,
        ),
        a: GoogleFonts.outfit(
          fontSize: 14,
          color: AppTheme.accentBlue,
          decoration: TextDecoration.underline,
        ),
        h1: GoogleFonts.outfit(
          fontSize: 19,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        h2: GoogleFonts.outfit(
          fontSize: 17,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        h3: GoogleFonts.outfit(
          fontSize: 15,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
        listBullet: GoogleFonts.outfit(fontSize: 14, color: color),
        code: GoogleFonts.firaCode(
          fontSize: 12.5,
          color: const Color(0xFF8BE9FD),
          backgroundColor: Colors.transparent,
        ),
        codeblockPadding: const EdgeInsets.all(10),
        codeblockDecoration: BoxDecoration(
          color: const Color(0xFF0D0D12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border),
        ),
        blockquoteDecoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(6),
        ),
        blockquotePadding: const EdgeInsets.all(10),
        horizontalRuleDecoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        tableBorder: TableBorder.all(color: AppTheme.border),
        tableCellsPadding: const EdgeInsets.symmetric(
          horizontal: 8,
          vertical: 6,
        ),
      ),
    );
  }
}
