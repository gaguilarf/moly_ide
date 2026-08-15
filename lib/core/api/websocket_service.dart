import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';

class LiveEvent {
  final String event;
  final Map<String, dynamic> data;
  final String timestamp;

  LiveEvent({required this.event, required this.data, required this.timestamp});

  factory LiveEvent.fromJson(Map<String, dynamic> json) {
    return LiveEvent(
      event: json['event'] ?? 'unknown',
      data: json['data'] is Map<String, dynamic> ? json['data'] : {},
      timestamp: json['timestamp'] ?? '',
    );
  }
}

class WebSocketService {
  final OrchestratorApiClient apiClient;
  WebSocketChannel? _channel;
  final _eventController = StreamController<LiveEvent>.broadcast();
  bool _isConnected = false;
  Timer? _reconnectTimer;

  WebSocketService({required this.apiClient});

  Stream<LiveEvent> get eventsStream => _eventController.stream;
  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_isConnected) return;

    try {
      final baseWsUrl = apiClient.currentBaseUrl
          .replaceFirst('http://', 'ws://')
          .replaceFirst('https://', 'wss://');

      // El token va en la consulta y no en una cabecera: al abrir un WebSocket
      // no se pueden poner cabeceras en todas las plataformas. El backend lo
      // acepta por las dos vias y cierra la conexion si no vale.
      final token = await apiClient.secureStorage.read(
        key: OrchestratorApiClient.storageKeyAuthToken,
      );
      if (token == null || token.isEmpty) {
        debugPrint('WebSocket sin sesion: no hay token guardado.');
        _handleDisconnect();
        return;
      }

      final wsUri = Uri.parse(
        '$baseWsUrl/api/v1/claude/ws?token=${Uri.encodeQueryComponent(token)}',
      );

      _channel = WebSocketChannel.connect(wsUri);
      _isConnected = true;

      _channel!.stream.listen(
        (message) {
          try {
            final parsed = jsonDecode(message.toString());
            if (parsed is Map<String, dynamic>) {
              _eventController.add(LiveEvent.fromJson(parsed));
            }
          } catch (e) {
            debugPrint('Error parseando WebSocket event: $e');
          }
        },
        onError: (error) {
          debugPrint('WebSocket error: $error');
          _handleDisconnect();
        },
        onDone: () {
          debugPrint('WebSocket cerrado.');
          _handleDisconnect();
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('Fallo al conectar WebSocket: $e');
      _handleDisconnect();
    }
  }

  void _handleDisconnect() {
    _isConnected = false;
    _channel = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 5), () {
      unawaited(connect());
    });
  }

  void send(String message) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(message);
    }
  }

  void dispose() {
    _reconnectTimer?.cancel();
    _channel?.sink.close();
    _eventController.close();
  }
}
