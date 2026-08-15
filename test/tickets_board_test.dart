import 'package:flutter_test/flutter_test.dart';
import 'package:moly_ide/features/auth/data/models/auth_user_model.dart';
import 'package:moly_ide/features/tickets/data/models/ticket_model.dart';
import 'package:moly_ide/features/tickets/presentation/cubit/tickets_state.dart';
import 'package:moly_ide/features/tickets/presentation/ticket_catalog.dart';

TicketModel _ticket({
  required String code,
  required String status,
  String? area,
  String priority = 'media',
  String title = 'Título',
  String? description,
}) {
  return TicketModel(
    id: code.hashCode,
    projectId: 1,
    number: 1,
    code: code,
    title: title,
    description: description,
    type: 'feature',
    area: area,
    priority: priority,
    status: status,
    reporter: 'test',
    source: 'manual',
    createdAt: '',
    updatedAt: '',
  );
}

final _sprint = TicketsState(
  sprints: [
    SprintModel(id: 7, name: 'Sprint 7', status: 'activo'),
    SprintModel(id: 6, name: 'Sprint 6', status: 'cerrado'),
  ],
  selectedSprintId: 7,
  tickets: [
    _ticket(code: 'SGA-1', status: 'backlog', area: 'back', priority: 'alta'),
    _ticket(code: 'SGA-2', status: 'desarrollo', area: 'front'),
    _ticket(code: 'TIA-3', status: 'hecho', area: 'back'),
    _ticket(code: 'TIA-4', status: 'descartado', area: 'qa'),
    _ticket(
      code: 'INF-5',
      status: 'revision',
      area: 'infra',
      title: 'Rotar la clave del túnel',
    ),
  ],
);

void main() {
  _pruebasDeCuenta();
  group('Sprint seleccionado', () {
    test('resuelve el sprint y el activo', () {
      expect(_sprint.selectedSprint?.name, 'Sprint 7');
      expect(_sprint.activeSprint?.id, 7);
      expect(_sprint.sprints[1].isCerrado, isTrue);
    });

    test('el progreso ignora los descartados y no depende de los filtros', () {
      // 5 tickets, uno descartado -> 4 cuentan, 1 hecho = 25%.
      expect(_sprint.sprintTotal, 4);
      expect(_sprint.sprintCompletados, 1);
      expect(_sprint.sprintProgreso, 25);

      final filtrado = _sprint.copyWith(projectFilter: 'INF');
      expect(filtrado.visibleTickets.length, 1);
      expect(
        filtrado.sprintTotal,
        4,
        reason: 'el progreso es del sprint entero',
      );
      expect(filtrado.sprintProgreso, 25);
    });
  });

  group('Filtros', () {
    test('sin filtros se ven todos', () {
      expect(_sprint.visibleTickets.length, 5);
      expect(_sprint.hasFilters, isFalse);
      expect(_sprint.activeFilterCount, 0);
    });

    test('proyecto sale del prefijo del código', () {
      final soloSga = _sprint.copyWith(projectFilter: 'SGA');
      expect(soloSga.visibleTickets.map((t) => t.code), ['SGA-1', 'SGA-2']);
    });

    test('área y prioridad se acumulan', () {
      final backAlta = _sprint.copyWith(
        areaFilter: 'back',
        priorityFilter: 'alta',
      );
      expect(backAlta.visibleTickets.map((t) => t.code), ['SGA-1']);
      expect(backAlta.activeFilterCount, 2);
    });

    test('la búsqueda mira código y título, sin distinguir mayúsculas', () {
      expect(_sprint.copyWith(query: 'inf-5').visibleTickets.length, 1);
      expect(_sprint.copyWith(query: 'TÚNEL').visibleTickets.length, 1);
      expect(
        _sprint.copyWith(query: 'tunel').visibleTickets.length,
        0,
        reason: 'no se normalizan acentos: hay que escribirlos',
      );
      expect(
        _sprint.copyWith(query: '   ').activeFilterCount,
        0,
        reason: 'espacios en blanco no son un filtro',
      );
    });

    test('los clear* devuelven el filtro a null', () {
      final conFiltros = _sprint.copyWith(
        projectFilter: 'SGA',
        areaFilter: 'back',
        priorityFilter: 'alta',
        query: 'algo',
      );
      final limpio = conFiltros.copyWith(
        query: '',
        clearProjectFilter: true,
        clearAreaFilter: true,
        clearPriorityFilter: true,
      );
      expect(limpio.hasFilters, isFalse);
      expect(limpio.visibleTickets.length, 5);
    });
  });

  group('Columnas', () {
    test('cada estado lleva sus tickets', () {
      expect(_sprint.ticketsEnColumna('backlog').length, 1);
      expect(_sprint.ticketsEnColumna('desarrollo').length, 1);
      expect(_sprint.ticketsEnColumna('pruebas'), isEmpty);
      expect(_sprint.ticketsEnColumna('revision').length, 1);
      expect(_sprint.ticketsEnColumna('hecho').length, 1);
    });

    test('los descartados tienen columna propia y son alcanzables', () {
      expect(kBoardColumns.last, 'descartado');
      expect(_sprint.ticketsEnColumna('descartado').map((t) => t.code), [
        'TIA-4',
      ]);
      for (final columna in kBoardColumns) {
        expect(
          kStatusLabel[columna],
          isNotNull,
          reason: 'toda columna necesita etiqueta para la pestaña',
        );
      }
    });

    test('los contadores respetan el filtro activo', () {
      final soloBack = _sprint.copyWith(areaFilter: 'back');
      expect(soloBack.ticketsEnColumna('backlog').length, 1);
      expect(soloBack.ticketsEnColumna('desarrollo'), isEmpty);
    });
  });
}

/// Modelo de usuario: el identificador de la cuenta es el nombre de usuario, no
/// el correo. Si `fromJson` mirara la clave vieja, la sesión guardada quedaría
/// sin identificar y la pantalla de acceso no podría precargarla.
void _pruebasDeCuenta() {
  group('Cuenta', () {
    test('lee el nombre de usuario que manda el servidor', () {
      final u = AuthUserModel.fromJson({
        'id': 1,
        'username': 'gaguilar',
        'name': 'Gustavo Aguilar',
        'role': 'admin',
        'is_active': true,
      });
      expect(u.username, 'gaguilar');
      expect(u.toJson()['username'], 'gaguilar');
    });

    test('un servidor sin migrar no revienta el modelo', () {
      final u = AuthUserModel.fromJson({'id': 1, 'email': 'x@y.z'});
      expect(u.username, '', reason: 'sin usuario, pero sin excepción');
    });
  });
}
