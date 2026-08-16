import 'package:flutter_test/flutter_test.dart';
import 'package:moly_ide/features/claude_agent/data/models/claude_models.dart';
import 'package:moly_ide/features/claude_agent/presentation/cubit/claude_state.dart';

ClaudeTaskModel _tarea({
  required String id,
  required String status,
  String prompt = 'haz algo',
  String? logs,
  String? pregunta,
}) {
  return ClaudeTaskModel(
    id: id,
    title: 'Tarea $id',
    prompt: prompt,
    status: status,
    executionLogs: logs,
    pendingQuestion: pregunta,
    createdAt: '',
  );
}

void main() {
  group('Cada conversación enseña lo suyo', () {
    final estado = ClaudeState(
      tasks: [
        _tarea(id: 'a', status: 'ejecutando'),
        _tarea(id: 'b', status: 'ejecutando'),
      ],
      chunksPorTarea: const {
        'a': ['hola ', 'desde A'],
        'b': ['esto es B'],
      },
      conversacionAbierta: 'a',
    );

    test('los trozos no se mezclan entre tareas', () {
      expect(estado.salidaDe(estado.tasks[0]), 'hola desde A');
      expect(estado.salidaDe(estado.tasks[1]), 'esto es B');
    });

    test('la conversación abierta es la que se resuelve', () {
      expect(estado.conversacion?.id, 'a');
      expect(estado.copyWith(conversacionAbierta: 'b').conversacion?.id, 'b');
    });

    test('sin nada en vivo se cae a lo que quedó guardado', () {
      final vieja = _tarea(id: 'z', status: 'hecho', logs: 'salida guardada');
      final soloHistorial = ClaudeState(tasks: [vieja]);
      expect(soloHistorial.salidaDe(vieja), 'salida guardada');
    });

    test('lo que llega en vivo manda sobre lo guardado', () {
      final t = _tarea(id: 'a', status: 'ejecutando', logs: 'viejo');
      expect(
        ClaudeState(
          tasks: [t],
          chunksPorTarea: const {
            'a': ['nuevo'],
          },
        ).salidaDe(t),
        'nuevo',
      );
    });
  });

  group('El flotante lista solo lo que sigue en marcha', () {
    final estado = ClaudeState(
      tasks: [
        _tarea(id: '1', status: 'ejecutando'),
        _tarea(id: '2', status: 'bloqueado_esperando_humano'),
        _tarea(id: '3', status: 'hecho'),
        _tarea(id: '4', status: 'fallido'),
        _tarea(id: '5', status: 'pendiente'),
      ],
    );

    test('ejecutando y esperando respuesta, nada mas', () {
      expect(estado.tareasEnCurso.map((t) => t.id), ['1', '2']);
    });
  });

  group('La pregunta del freno duro no se cruza de conversacion', () {
    test('la pregunta en vivo es de la tarea activa', () {
      final bloqueada = _tarea(id: 'a', status: 'bloqueado_esperando_humano');
      final otra = _tarea(id: 'b', status: 'bloqueado_esperando_humano');
      final estado = ClaudeState(
        tasks: [bloqueada, otra],
        activeTask: bloqueada,
        pendingQuestion: '¿Sigo?',
      );

      expect(estado.preguntaDe(bloqueada), '¿Sigo?');
      expect(
        estado.preguntaDe(otra),
        isNull,
        reason: 'la de otra tarea no lleva la pregunta en vivo',
      );
    });

    test('una tarea que no espera a nadie no pregunta nada', () {
      final corriendo = _tarea(id: 'a', status: 'ejecutando');
      final estado = ClaudeState(
        tasks: [corriendo],
        activeTask: corriendo,
        pendingQuestion: '¿Sigo?',
      );
      expect(estado.preguntaDe(corriendo), isNull);
    });
  });

  group('Borrar conversaciones', () {
    final estado = ClaudeState(
      tasks: [
        _tarea(id: 'viva', status: 'ejecutando'),
        _tarea(id: 'hecha', status: 'completado'),
        _tarea(id: 'rota', status: 'fallido'),
      ],
      chunksPorTarea: const {
        'viva': ['a'],
        'hecha': ['b'],
      },
      conversacionAbierta: 'hecha',
    );

    test('las terminadas son las que no estan en curso', () {
      final terminadas = estado.tasks
          .where((t) => !kEstadosEnCurso.contains(t.status))
          .map((t) => t.id);
      expect(terminadas, ['hecha', 'rota']);
    });

    test('al borrar la abierta se deja de mirarla', () {
      final tras = estado.copyWith(clearConversacion: true);
      expect(tras.conversacionAbierta, isNull);
      expect(tras.conversacion, isNull);
    });

    test('la salida de la borrada se olvida y la otra se queda', () {
      final mapa = Map<String, List<String>>.from(estado.chunksPorTarea)
        ..removeWhere((id, _) => ['hecha'].contains(id));
      final tras = estado.copyWith(chunksPorTarea: mapa);
      expect(tras.chunksPorTarea.containsKey('hecha'), isFalse);
      expect(tras.chunksPorTarea['viva'], ['a']);
    });
  });
}
