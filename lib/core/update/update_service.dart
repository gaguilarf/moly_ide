import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

class RemoteVersionInfo {
  final int buildNumber;
  final String versionName;

  RemoteVersionInfo({required this.buildNumber, required this.versionName});

  factory RemoteVersionInfo.fromJson(Map<String, dynamic> json) {
    return RemoteVersionInfo(
      buildNumber: json['build'] as int? ?? 0,
      versionName: json['version'] as String? ?? '0.0.0',
    );
  }
}

class UpdateService {
  static const String updateHost = '62.169.29.115';
  static const int port = 9090;

  Future<RemoteVersionInfo?> checkRemoteVersion() async {
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);
      final request = await client.get(updateHost, port, '/version');
      final response = await request.close();
      if (response.statusCode == 200) {
        final body = await response.transform(const Utf8Decoder()).join();
        final json = jsonDecode(body) as Map<String, dynamic>;
        client.close();
        return RemoteVersionInfo.fromJson(json);
      }
      client.close();
    } catch (_) {}
    return null;
  }

  Future<String?> downloadApk({
    void Function(int received, int total)? onProgress,
  }) async {
    try {
      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final savePath = '${dir.path}/moly_update.apk';

      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 15);
      final request = await client.get(updateHost, port, '/app.apk');
      final response = await request.close();

      if (response.statusCode == 200) {
        final total = response.contentLength;
        int received = 0;
        final file = File(savePath);
        final sink = file.openWrite();

        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          if (total > 0) onProgress?.call(received, total);
        }
        await sink.close();
        client.close();
        return savePath;
      }
      client.close();
    } catch (_) {}
    return null;
  }
}
