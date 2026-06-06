import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum SSHConnectionState { disconnected, connecting, connected }

class SSHService {
  final FlutterSecureStorage secureStorage;
  
  SSHClient? _client;
  SftpClient? _sftpClient;
  
  SSHConnectionState _state = SSHConnectionState.disconnected;
  SSHConnectionState get state => _state;

  String? _host;
  String? _username;
  int? _port;

  String? get host => _host;
  String? get username => _username;
  int? get port => _port;

  final _stateController = StreamController<SSHConnectionState>.broadcast();
  Stream<SSHConnectionState> get stateStream => _stateController.stream;

  SSHSession? activeTerminalSession;

  SSHService({required this.secureStorage});

  // Connect to VPS
  Future<void> connect({
    required String host,
    required int port,
    required String username,
    String? password,
    String? privateKey,
  }) async {
    _state = SSHConnectionState.connecting;
    _stateController.add(_state);

    try {
      // Connect TCP Socket
      final socket = await SSHSocket.connect(host, port, timeout: const Duration(seconds: 15));
      
      // Initialize Client
      _client = SSHClient(
        socket,
        username: username,
        onPasswordRequest: () {
          if (password != null) {
            return password;
          }
          throw Exception('Password is required but not provided');
        },
      );

      // Await connection success
      await _client!.authenticated;
      
      // Initialize SFTP
      _sftpClient = await _client!.sftp();

      _host = host;
      _username = username;
      _port = port;
      _state = SSHConnectionState.connected;
      _stateController.add(_state);

      // Save credentials securely (Optional, host and username)
      await secureStorage.write(key: 'vps_host', value: host);
      await secureStorage.write(key: 'vps_port', value: port.toString());
      await secureStorage.write(key: 'vps_username', value: username);
      if (password != null) {
        await secureStorage.write(key: 'vps_password', value: password);
      }
    } catch (e) {
      disconnect();
      rethrow;
    }
  }

  // Disconnect
  void disconnect() {
    activeTerminalSession = null;
    _sftpClient = null;
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
    _host = null;
    _username = null;
    _port = null;
    
    _state = SSHConnectionState.disconnected;
    _stateController.add(_state);
  }

  // Get active SSHClient
  SSHClient get client {
    if (_client == null || _state != SSHConnectionState.connected) {
      throw Exception('SSH client is not connected');
    }
    return _client!;
  }

  // Get active SFTPClient
  SftpClient get sftp {
    if (_sftpClient == null || _state != SSHConnectionState.connected) {
      throw Exception('SFTP client is not connected');
    }
    return _sftpClient!;
  }

  // Launch interactive SSH shell for Terminal View
  Future<SSHSession> createShellSession({
    required int terminalWidth,
    required int terminalHeight,
  }) async {
    return await client.shell(
      pty: SSHPtyConfig(
        width: terminalWidth,
        height: terminalHeight,
      ),
    );
  }

  // SFTP Operations: List Directory
  Future<List<SftpName>> listDirectory(String path) async {
    return await sftp.listdir(path);
  }

  // SFTP Operations: Read File Content as String
  Future<String> readFile(String path) async {
    final remoteFile = await sftp.open(path);
    
    final byteStream = remoteFile.read();
    final bytesList = <int>[];
    
    await for (final chunk in byteStream) {
      bytesList.addAll(chunk);
    }
    
    await remoteFile.close();
    
    // Decode as UTF-8
    try {
      return utf8.decode(bytesList);
    } catch (e) {
      // Fallback to Latin1 or return raw error if binary file
      return utf8.decode(bytesList, allowMalformed: true);
    }
  }

  // SFTP Operations: Write File Content (Save)
  Future<void> writeFile(String path, String content) async {
    final remoteFile = await sftp.open(
      path,
      mode: SftpFileOpenMode.write | SftpFileOpenMode.create | SftpFileOpenMode.truncate,
    );

    final Uint8List encodedBytes = Uint8List.fromList(utf8.encode(content));
    await remoteFile.write(Stream.value(encodedBytes));
    await remoteFile.close();
  }

  // SFTP Operations: Create Directory
  Future<void> createDirectory(String path) async {
    await sftp.mkdir(path);
  }

  // SFTP Operations: Delete File or Directory
  Future<void> deleteFile(String path) async {
    await sftp.remove(path);
  }

  Future<void> deleteDirectory(String path) async {
    await sftp.rmdir(path);
  }

  // SFTP Operations: Rename/Move
  Future<void> rename(String oldPath, String newPath) async {
    await sftp.rename(oldPath, newPath);
  }

  // SFTP Operations: Get User Home Directory
  Future<String> getHomeDirectory() async {
    // SFTP absolute path resolver
    return await sftp.absolute('.');
  }

  // Execute a shell command and return stdout as a string
  Future<String> executeCommand(String command) async {
    final result = await client.run(command).timeout(const Duration(seconds: 15));
    return utf8.decode(result, allowMalformed: true);
  }

  // SFTP Operations: Upload binary file (e.g. images from device)
  Future<void> uploadFileBinary(String remotePath, Uint8List bytes) async {
    final remoteFile = await sftp.open(
      remotePath,
      mode: SftpFileOpenMode.write | SftpFileOpenMode.create | SftpFileOpenMode.truncate,
    );
    await remoteFile.write(Stream.value(bytes));
    await remoteFile.close();
  }

  // SFTP Operations: Download binary file with optional progress callback
  Future<Uint8List> downloadFileBinary(
    String path, {
    void Function(int received, int total)? onProgress,
  }) async {
    final attrs = await sftp.stat(path);
    final total = attrs.size ?? 0;

    final remoteFile = await sftp.open(path);
    final byteStream = remoteFile.read();
    final builder = BytesBuilder(copy: false);
    int received = 0;

    await for (final chunk in byteStream) {
      builder.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress?.call(received, total);
    }

    await remoteFile.close();
    return builder.takeBytes();
  }
}
