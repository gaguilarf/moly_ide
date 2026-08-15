import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:moly_ide/features/updates/presentation/cubit/update_state.dart';

class UpdateCubit extends Cubit<UpdateState> {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 30),
  ));

  UpdateCubit() : super(const UpdateState()) {
    _initAndCheckUpdates();
  }

  Future<void> _initAndCheckUpdates() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final currentVer = '${info.version}+${info.buildNumber}';
      emit(state.copyWith(currentVersion: currentVer));
      await checkForUpdates();
    } catch (_) {
      await checkForUpdates();
    }
  }

  String _getVersionUrl(String apkUrl) {
    if (apkUrl.endsWith('.apk')) {
      final lastSlash = apkUrl.lastIndexOf('/');
      if (lastSlash != -1) {
        return '${apkUrl.substring(0, lastSlash)}/version.json';
      }
    }
    return '$apkUrl/version.json';
  }

  Future<void> setUpdateUrl(String url) async {
    emit(state.copyWith(updateUrl: url.trim()));
    await checkForUpdates(urlOverride: url.trim());
  }

  Future<void> checkForUpdates({String? urlOverride}) async {
    final apkUrl = urlOverride?.trim() ?? state.updateUrl;
    final versionUrl = _getVersionUrl(apkUrl);

    emit(state.copyWith(
      isCheckingVersion: true,
      errorMessage: null,
      statusMessage: 'Comprobando última versión en el servidor...',
    ));

    try {
      final resp = await _dio.get(versionUrl);
      if (resp.statusCode == 200 && resp.data != null) {
        final data = resp.data is Map ? resp.data : {};
        final serverVersion = data['version']?.toString().trim() ?? '';
        final notes = data['release_notes']?.toString();

        final current = state.currentVersion.trim();
        final isSame = serverVersion.isNotEmpty && (current == serverVersion);

        emit(state.copyWith(
          isCheckingVersion: false,
          latestVersion: serverVersion.isNotEmpty ? serverVersion : null,
          releaseNotes: notes,
          isUpToDate: isSame,
          statusMessage: isSame
              ? 'Ya tienes instalada la versión más reciente ($current).'
              : (serverVersion.isNotEmpty
                  ? 'Nueva versión disponible: $serverVersion (actual: $current).'
                  : 'Listo para descargar.'),
        ));
        return;
      }
    } catch (_) {}

    // Si no responde version.json, permitir descarga manual
    emit(state.copyWith(
      isCheckingVersion: false,
      isUpToDate: false,
      statusMessage: 'No se pudo verificar version.json. Puedes descargar manualmente.',
    ));
  }

  Future<void> downloadAndInstall({String? urlOverride}) async {
    final targetUrl = urlOverride?.trim() ?? state.updateUrl;
    emit(state.copyWith(
      status: UpdateStatus.downloading,
      progress: 0.0,
      bytesReceived: 0,
      totalBytes: 0,
      statusMessage: 'Limpiando versiones anteriores...',
      errorMessage: null,
    ));

    try {
      // 1. Obtener directorio de almacenamiento seguro
      Directory? storageDir = await getExternalStorageDirectory();
      storageDir ??= await getApplicationDocumentsDirectory();

      final apkDir = Directory('${storageDir.path}/updates');
      if (!apkDir.existsSync()) {
        apkDir.createSync(recursive: true);
      }

      // 2. Limpieza de versiones previas: borrar archivo existente
      final targetFilePath = '${apkDir.path}/moly_release.apk';
      final targetFile = File(targetFilePath);

      if (targetFile.existsSync()) {
        try {
          targetFile.deleteSync();
        } catch (_) {}
      }

      // Limpiar cualquier otro .apk antiguo en la carpeta
      try {
        final existingFiles = apkDir.listSync();
        for (var entity in existingFiles) {
          if (entity is File && entity.path.endsWith('.apk')) {
            try {
              entity.deleteSync();
            } catch (_) {}
          }
        }
      } catch (_) {}

      emit(state.copyWith(
        statusMessage: 'Descargando nueva versión desde el servidor...',
      ));

      // 3. Descarga asíncrona con progreso
      await _dio.download(
        targetUrl,
        targetFilePath,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            final receivedMb = (received / (1024 * 1024)).toStringAsFixed(1);
            final totalMb = (total / (1024 * 1024)).toStringAsFixed(1);
            emit(state.copyWith(
              progress: progress,
              bytesReceived: received,
              totalBytes: total,
              statusMessage: 'Descargando: $receivedMb MB / $totalMb MB (${(progress * 100).toInt()}%)',
            ));
          }
        },
      );

      emit(state.copyWith(
        status: UpdateStatus.success,
        progress: 1.0,
        downloadedFilePath: targetFilePath,
        statusMessage: 'Descarga completada. Abriendo instalador...',
      ));

      // 4. Abrir instalador de paquetes de Android
      final result = await OpenFilex.open(
        targetFilePath,
        type: 'application/vnd.android.package-archive',
      );

      if (result.type != ResultType.done) {
        emit(state.copyWith(
          statusMessage: 'APK listo en $targetFilePath. Abre el archivo para instalar.',
        ));
      }
    } catch (e) {
      emit(state.copyWith(
        status: UpdateStatus.error,
        errorMessage: 'Error al descargar la actualización: $e',
        statusMessage: 'Falló la descarga. Verifica tu conexión.',
      ));
    }
  }

  Future<void> openExistingApk() async {
    if (state.downloadedFilePath != null) {
      await OpenFilex.open(
        state.downloadedFilePath!,
        type: 'application/vnd.android.package-archive',
      );
    }
  }
}
