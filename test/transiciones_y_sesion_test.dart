import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moly_ide/core/api/orchestrator_api_client.dart';
import 'package:moly_ide/features/auth/data/models/auth_user_model.dart';
import 'package:moly_ide/features/auth/presentation/cubit/auth_state.dart';
import 'package:moly_ide/features/claude_agent/data/models/claude_models.dart';
import 'package:moly_ide/features/claude_agent/presentation/cubit/claude_state.dart';
import 'package:moly_ide/features/tickets/presentation/cubit/tickets_cubit.dart';

/// Responde a Dio sin salir a la red. Devuelve el par (código, cuerpo) que
/// decida [responder] según la ruta pedida.
class _AdaptadorFalso implements HttpClientAdapter {
  _AdaptadorFalso(this.responder);

  final (int, Object) Function(RequestOptions options) responder;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final (codigo, cuerpo) = responder(options);
    return ResponseBody.fromString(
      jsonEncode(cuerpo),
      codigo,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

/// El cliente lee el token del almacen seguro en cada peticion, y en un test no
/// hay canal de plataforma que lo atienda: se contesta null (sin sesion).
void _silenciarAlmacenSeguro() {
  const canal = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(canal, (_) async => null);
}

TicketsCubit _cubitQueResponde(
  (int, Object) Function(RequestOptions) responder,
) {
  final cliente = OrchestratorApiClient(
    secureStorage: const FlutterSecureStorage(),
  );
  cliente.dio.httpClientAdapter = _AdaptadorFalso(responder);
  return TicketsCubit(apiClient: cliente);
}

/// Respuestas del tablero para la recarga que sigue a una transición aceptada.
(int, Object) _tableroVacio(RequestOptions o) => (200, const []);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(_silenciarAlmacenSeguro);

  group('transitionTicket devuelve el rechazo en vez de emitirlo', () {
    test('aceptada: devuelve null y no deja error en el estado', () async {
      final cubit = _cubitQueResponde((o) {
        if (o.path.endsWith('/transition')) {
          return (200, const {'status': 'revision'});
        }
        return _tableroVacio(o);
      });

      final error = await cubit.transitionTicket(
        code: 'INF-53',
        toStatus: 'revision',
        note: 'lista para revisar',
      );

      expect(error, isNull);
      expect(cubit.state.errorMessage, isNull);
    });

    test(
      '409: devuelve el detail del servidor, y el estado sigue limpio',
      () async {
        final cubit = _cubitQueResponde(
          (o) =>
              (409, const {'detail': 'No se puede pasar de backlog a hecho.'}),
        );

        final error = await cubit.transitionTicket(
          code: 'INF-53',
          toStatus: 'hecho',
        );

        expect(error, 'No se puede pasar de backlog a hecho.');
        // Lo que arregla INF-53: si esto se emitiera, el aviso saldría por el
        // tablero de detrás y el diálogo se cerraría como si hubiera funcionado.
        expect(
          cubit.state.errorMessage,
          isNull,
          reason: 'el rechazo se devuelve a quien llama, no se emite',
        );
      },
    );

    test(
      '422: la nota de cierre que exige el servidor llega tal cual',
      () async {
        final cubit = _cubitQueResponde(
          (o) => (422, const {'detail': 'Cerrar un ticket exige una nota.'}),
        );

        expect(
          await cubit.transitionTicket(code: 'INF-53', toStatus: 'hecho'),
          'Cerrar un ticket exige una nota.',
        );
      },
    );

    test('sin respuesta del Jetson se explica en cristiano', () async {
      final cliente = OrchestratorApiClient(
        secureStorage: const FlutterSecureStorage(),
      );
      cliente.dio.httpClientAdapter = _AdaptadorFalso(
        (_) => throw const SocketExceptionFalsa(),
      );
      final cubit = TicketsCubit(apiClient: cliente);

      final error = await cubit.transitionTicket(
        code: 'INF-53',
        toStatus: 'pruebas',
      );

      expect(error, isNotNull);
      expect(error, contains('Jetson'));
    });
  });

  group('AuthState.copyWith puede volver a null', () {
    final conSesion = AuthState(
      status: AuthStatus.authenticated,
      user: AuthUserModel(
        id: 1,
        email: 'gus@ejemplo.dev',
        name: 'Gus',
        role: 'developer',
        isActive: true,
      ),
      token: 'jwt-de-verdad',
      savedEmail: 'gus@ejemplo.dev',
      savedPassword: 'secreta',
    );

    test('cerrar sesión borra el JWT y el perfil', () {
      final fuera = conSesion.copyWith(
        status: AuthStatus.unauthenticated,
        clearSession: true,
      );
      expect(fuera.token, isNull);
      expect(fuera.user, isNull);
      expect(
        fuera.savedEmail,
        'gus@ejemplo.dev',
        reason: 'el baúl se conserva salvo que se pida vaciarlo',
      );
    });

    test('vaciar el baúl borra también la contraseña guardada', () {
      final fuera = conSesion.copyWith(
        status: AuthStatus.unauthenticated,
        clearSession: true,
        clearSavedCredentials: true,
      );
      expect(fuera.savedPassword, isNull);
      expect(fuera.savedEmail, isNull);
    });

    test('sin los clear*, pasar null conserva el valor anterior', () {
      final igual = conSesion.copyWith(user: null, token: null);
      expect(
        igual.token,
        'jwt-de-verdad',
        reason: 'este era el fallo del hallazgo 6',
      );
    });
  });

  group('ClaudeState.copyWith limpia la tarea activa', () {
    final conTarea = ClaudeState(
      activeTask: ClaudeTaskModel(
        id: 't1',
        title: 'Resolución INF-53',
        prompt: '...',
        status: 'ejecutando',
        createdAt: '',
      ),
      pendingQuestion: '¿Sigo?',
    );

    test('al terminar la tarea, el estado se queda sin tarea ni pregunta', () {
      final limpio = conTarea.copyWith(
        clearActiveTask: true,
        clearQuestion: true,
      );
      expect(limpio.activeTask, isNull);
      expect(limpio.pendingQuestion, isNull);
    });

    test('sin clearActiveTask la tarea muerta seguía pegada', () {
      expect(conTarea.copyWith(activeTask: null).activeTask, isNotNull);
    });
  });
}

/// Excepción de red cualquiera: solo sirve para que Dio la envuelva en un
/// DioException sin `response`, que es el caso «no se llegó al Jetson».
class SocketExceptionFalsa implements Exception {
  const SocketExceptionFalsa();
}
