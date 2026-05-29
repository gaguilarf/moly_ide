import 'dart:convert';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:moly_ide/core/ssh/ssh_service.dart';
import 'package:moly_ide/features/connection/data/models/vps_connection.dart';
import 'package:moly_ide/features/connection/presentation/cubit/connection_state.dart';

class ConnectionCubit extends Cubit<ConnectionState> {
  final SSHService _sshService;
  final FlutterSecureStorage _secureStorage;

  ConnectionCubit({
    required SSHService sshService,
    required FlutterSecureStorage secureStorage,
  })  : _sshService = sshService,
        _secureStorage = secureStorage,
        super(const ConnectionInitial()) {
    _loadCachedCredentials();
  }

  // Load secure storage credentials on start
  Future<void> _loadCachedCredentials() async {
    try {
      final List<VPSConnection> saved = await _loadSavedConnections();
      
      // Prefill with the first saved connection if available
      final firstConn = saved.isNotEmpty ? saved.first : null;

      emit(ConnectionInitial(
        savedConnections: saved,
        host: firstConn?.host ?? '',
        port: firstConn?.port ?? '22',
        username: firstConn?.username ?? '',
        password: firstConn?.password ?? '',
      ));
    } catch (_) {
      emit(const ConnectionInitial());
    }
  }

  // Load saved connections from JSON string
  Future<List<VPSConnection>> _loadSavedConnections() async {
    try {
      final jsonStr = await _secureStorage.read(key: 'saved_vps_connections');
      if (jsonStr != null && jsonStr.isNotEmpty) {
        final List decoded = json.decode(jsonStr);
        return decoded.map((item) => VPSConnection.fromJson(item)).toList();
      }
      
      // Migration from old single connection keys
      final host = await _secureStorage.read(key: 'vps_host') ?? '';
      final port = await _secureStorage.read(key: 'vps_port') ?? '22';
      final username = await _secureStorage.read(key: 'vps_username') ?? '';
      final password = await _secureStorage.read(key: 'vps_password') ?? '';
      
      if (host.isNotEmpty && username.isNotEmpty) {
        final migrated = VPSConnection(
          host: host,
          port: port,
          username: username,
          password: password,
        );
        final list = [migrated];
        await _secureStorage.write(
          key: 'saved_vps_connections',
          value: json.encode(list.map((c) => c.toJson()).toList()),
        );
        return list;
      }
    } catch (_) {}
    return [];
  }

  // Save successful connection to list
  Future<void> _saveConnection(VPSConnection connection) async {
    try {
      final list = await _loadSavedConnections();
      // Avoid duplicates
      list.removeWhere((c) =>
          c.host == connection.host &&
          c.username == connection.username &&
          c.port == connection.port);
      list.insert(0, connection);
      await _secureStorage.write(
        key: 'saved_vps_connections',
        value: json.encode(list.map((c) => c.toJson()).toList()),
      );
    } catch (_) {}
  }

  // Delete a saved connection from list
  Future<void> deleteConnection(VPSConnection connection) async {
    try {
      final list = await _loadSavedConnections();
      list.removeWhere((c) =>
          c.host == connection.host &&
          c.username == connection.username &&
          c.port == connection.port);
      await _secureStorage.write(
        key: 'saved_vps_connections',
        value: json.encode(list.map((c) => c.toJson()).toList()),
      );
      
      // Preserve current text inputs in the UI if in initial state
      String currentHost = '';
      String currentPort = '22';
      String currentUsername = '';
      String currentPassword = '';
      
      if (state is ConnectionInitial) {
        final init = state as ConnectionInitial;
        currentHost = init.host;
        currentPort = init.port;
        currentUsername = init.username;
        currentPassword = init.password;
      }
      
      emit(ConnectionInitial(
        savedConnections: list,
        host: currentHost,
        port: currentPort,
        username: currentUsername,
        password: currentPassword,
      ));
    } catch (_) {}
  }

  // Connect to VPS
  Future<void> connect({
    required String host,
    required String portStr,
    required String username,
    required String password,
  }) async {
    final port = int.tryParse(portStr) ?? 22;
    final savedList = state.savedConnections;
    
    emit(ConnectionLoading(savedConnections: savedList));

    try {
      await _sshService.connect(
        host: host,
        port: port,
        username: username,
        password: password.isNotEmpty ? password : null,
      );
      
      // Save successfully connected server
      final newConn = VPSConnection(
        host: host,
        port: portStr,
        username: username,
        password: password,
      );
      await _saveConnection(newConn);
      final updatedList = await _loadSavedConnections();
      
      emit(ConnectionSuccess(
        savedConnections: updatedList,
        host: host,
        username: username,
      ));
    } catch (e) {
      emit(ConnectionFailure(
        savedConnections: savedList,
        errorMessage: e.toString(),
      ));
    }
  }

  // Disconnect
  void disconnect() {
    _sshService.disconnect();
    _loadCachedCredentials();
  }
}
