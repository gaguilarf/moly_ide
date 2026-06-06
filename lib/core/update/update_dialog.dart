import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/core/update/update_service.dart';

class UpdateDialog extends StatefulWidget {
  final RemoteVersionInfo info;
  final int currentBuild;
  final UpdateService updateService;

  const UpdateDialog({
    super.key,
    required this.info,
    required this.currentBuild,
    required this.updateService,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<UpdateDialog> {
  static const _utilsChannel = MethodChannel('com.moly.moly_ide/utils');

  bool _downloading = false;
  double _progress = 0;
  String? _error;

  Future<void> _startDownload() async {
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });

    final path = await widget.updateService.downloadApk(
      onProgress: (received, total) {
        if (mounted) setState(() => _progress = received / total);
      },
    );

    if (!mounted) return;

    if (path != null) {
      Navigator.pop(context);
      await _utilsChannel.invokeMethod('installApk', {'path': path});
    } else {
      setState(() {
        _downloading = false;
        _error = 'No se pudo descargar la actualización. Verifica que el servidor esté en línea.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.system_update_rounded, color: AppTheme.accentBlue, size: 22),
          const SizedBox(width: 10),
          Text('Actualización Disponible',
              style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nueva versión ${widget.info.versionName} (build ${widget.info.buildNumber}) disponible.',
            style: GoogleFonts.outfit(fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            'Versión actual: build ${widget.currentBuild}',
            style: GoogleFonts.outfit(fontSize: 12, color: AppTheme.textSecondary),
          ),
          if (_downloading) ...[
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                color: AppTheme.accentBlue,
                backgroundColor: AppTheme.surfaceLight,
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              _progress > 0
                  ? 'Descargando... ${(_progress * 100).toStringAsFixed(0)}%'
                  : 'Conectando al servidor...',
              style: GoogleFonts.firaCode(fontSize: 11, color: AppTheme.textSecondary),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5252).withOpacity(0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFFF5252).withOpacity(0.3)),
              ),
              child: Text(
                _error!,
                style: GoogleFonts.outfit(fontSize: 12, color: const Color(0xFFFF5252)),
              ),
            ),
          ],
        ],
      ),
      actions: [
        if (!_downloading)
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Más Tarde',
                style: GoogleFonts.outfit(color: AppTheme.textSecondary)),
          ),
        if (!_downloading)
          ElevatedButton.icon(
            onPressed: _startDownload,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentBlue,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            icon: const Icon(Icons.download_rounded, size: 16),
            label: Text('Actualizar', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
          ),
      ],
    );
  }
}
