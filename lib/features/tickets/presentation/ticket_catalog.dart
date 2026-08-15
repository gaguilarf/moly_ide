import 'package:flutter/material.dart';

/// Vocabulario del tablero, en un solo sitio: estados, áreas, prioridades y sus
/// colores. Antes cada pantalla llevaba su propia copia de las listas y de
/// `_getStatusColor`, y bastaba tocar una para que el tablero y el detalle
/// pintaran el mismo ticket de dos colores distintos.

/// Columnas del tablero, en el orden del flujo. `descartado` va al final y
/// fuera del camino: en el panel ni siquiera tenía columna, pero en el móvil el
/// tablero es la única puerta al detalle de un ticket, y sin ella un ticket
/// descartado se vuelve inalcanzable.
const List<String> kBoardColumns = [
  'backlog',
  'desarrollo',
  'pruebas',
  'revision',
  'hecho',
  'descartado',
];

const Map<String, String> kStatusLabel = {
  'backlog': 'Backlog',
  'desarrollo': 'Desarrollo',
  'pruebas': 'Pruebas',
  'revision': 'Revisión',
  'hecho': 'Hecho',
  'descartado': 'Descartado',
};

const List<String> kTicketAreas = [
  'back',
  'front',
  'mobile',
  'infra',
  'qa',
  'pm',
  'datos',
  'diseno',
];

const Map<String, String> kAreaLabel = {
  'back': 'Back',
  'front': 'Front',
  'mobile': 'Mobile',
  'infra': 'Infra',
  'qa': 'QA',
  'pm': 'PM',
  'datos': 'Datos',
  'diseno': 'Diseño',
};

/// Transiciones permitidas, calcadas de las reglas del backend
/// (`TRANSICIONES` en backend/app/routers/tickets.py). La dura: a `hecho` solo
/// se llega desde `revision` y con nota de cierre. Ofrecer destinos que el
/// backend rechaza solo sirve para que el error salte después de escribir la
/// nota.
const Map<String, List<String>> kTicketTransitions = {
  'backlog': ['desarrollo', 'pruebas', 'revision', 'descartado'],
  'desarrollo': ['backlog', 'pruebas', 'revision', 'descartado'],
  'pruebas': ['backlog', 'desarrollo', 'revision', 'descartado'],
  'revision': ['backlog', 'desarrollo', 'pruebas', 'hecho', 'descartado'],
  'hecho': ['backlog', 'revision'],
  'descartado': ['backlog'],
};

const List<String> kTicketPriorities = ['critica', 'alta', 'media', 'baja'];

const Map<String, String> kPriorityLabel = {
  'critica': 'Crítica',
  'alta': 'Alta',
  'media': 'Media',
  'baja': 'Baja',
};

Color statusColor(String status) {
  switch (status.toLowerCase()) {
    case 'backlog':
      return const Color(0xFF9E9E9E);
    case 'desarrollo':
      return const Color(0xFF00E5FF);
    case 'pruebas':
      return const Color(0xFFFF9900);
    case 'revision':
      return const Color(0xFF9E00FF);
    case 'hecho':
      return const Color(0xFF00FF66);
    case 'descartado':
      return const Color(0xFFFF3366);
    default:
      return Colors.white;
  }
}

Color priorityColor(String priority) {
  switch (priority.toLowerCase()) {
    case 'critica':
      return const Color(0xFFFF3366);
    case 'alta':
      return const Color(0xFFFF9900);
    case 'media':
      return const Color(0xFF00E5FF);
    case 'baja':
    default:
      return const Color(0xFF00FF66);
  }
}

/// Color del área, para que el tablero se lea por color sin leer la etiqueta.
Color areaColor(String area) {
  switch (area.toLowerCase()) {
    case 'back':
      return const Color(0xFF38BDF8);
    case 'front':
      return const Color(0xFFA78BFA);
    case 'mobile':
      return const Color(0xFF2DD4BF);
    case 'infra':
      return const Color(0xFFFB923C);
    case 'qa':
      return const Color(0xFFA3E635);
    case 'pm':
      return const Color(0xFFE879F9);
    case 'datos':
      return const Color(0xFF22D3EE);
    case 'diseno':
      return const Color(0xFFFB7185);
    default:
      return const Color(0xFF9C97B7);
  }
}
