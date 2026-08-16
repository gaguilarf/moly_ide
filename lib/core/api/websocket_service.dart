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
  /// Primera espera antes de reintentar; se dobla en cada fallo seguido hasta
  /// [_esperaMaxima]. Reintentar siempre a los 5 s tenía al movil llamando al
  /// Jetson doce veces por minuto mientras estuviera apagado.
  static const Duration _esperaBase = Duration(seconds: 5);
  // Dos minutos era demasiado: tras varios reinicios del servidor la espera
  // crecia hasta ahi y la app se quedaba sin recibir nada un buen rato,
  // pareciendo que Claude no respondia.
  static const Duration _esperaMaxima = Duration(seconds: 20);

  /// Cierre limpio (1000) y rechazo de credenciales (1008). En los dos casos
  /// insistir es inútil: el servidor ya dijo lo que tenía que decir y con el
  /// mismo token la respuesta va a ser la misma.
  static const int _cierreLimpio = 1000;
  static const int _cierrePorPolitica = 1008;

  final OrchestratorApiClient apiClient;
  WebSocketChannel? _channel;
  final _eventController = StreamController<LiveEvent>.broadcast();
  bool _isConnected = false;
  bool _disposed = false;
  int _fallosSeguidos = 0;
  Timer? _reconnectTimer;

  WebSocketService({required this.apiClient});

  Stream<LiveEvent> get eventsStream => _eventController.stream;
  bool get isConnected => _isConnected;

  Future<void> connect() async {
    if (_disposed || _isConnected) return;

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
        // Sin sesion no hay nada que reintentar: en la pantalla de login esto
        // reprogramaba el temporizador cada 5 s para siempre. Al iniciar
        // sesion se crea un ClaudeCubit nuevo, que vuelve a llamar a connect().
        debugPrint('WebSocket sin sesion: no hay token guardado.');
        _isConnected = false;
        _channel = null;
        return;
      }

      final wsUri = Uri.parse(
        '$baseWsUrl/api/v1/claude/ws?token=${Uri.encodeQueryComponent(token)}',
      );

      _channel = WebSocketChannel.connect(wsUri);
      _isConnected = true;
      _fallosSeguidos = 0;

      _channel!.stream.listen(
        (message) {
          // Tras dispose() el controlador esta cerrado: anadir aqui era el
          // «Cannot add event after closing».
          if (_disposed || _eventController.isClosed) return;
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
          final codigo = _channel?.closeCode;
          debugPrint('WebSocket cerrado (codigo $codigo).');
          _handleDisconnect(
            reintentar: codigo != _cierrePorPolitica && codigo != _cierreLimpio,
          );
        },
        cancelOnError: true,
      );
    } catch (e) {
      debugPrint('Fallo al conectar WebSocket: $e');
      _handleDisconnect();
    }
  }

  void _handleDisconnect({bool reintentar = true}) {
    _isConnected = false;
    _channel = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;

    // dispose() cierra el sink, y ese cierre dispara onDone: sin este freno se
    // armaba un temporizador nuevo DESPUES de haber cerrado todo.
    if (_disposed || !reintentar) return;

    _fallosSeguidos++;
    _reconnectTimer = Timer(_esperaSiguiente(), () => unawaited(connect()));
  }

  Duration _esperaSiguiente() {
    final exponente = (_fallosSeguidos - 1).clamp(0, 5);
    final espera = _esperaBase * (1 << exponente);
    return espera > _esperaMaxima ? _esperaMaxima : espera;
  }

  void send(String message) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(message);
    }
  }

  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _channel?.sink.close();
    _eventController.close();
  }
}
