import 'package:moly_ide/features/connection/data/models/vps_connection.dart';

abstract class ConnectionState {
  final List<VPSConnection> savedConnections;
  const ConnectionState({this.savedConnections = const []});
}

class ConnectionInitial extends ConnectionState {
  final String host;
  final String port;
  final String username;
  final String password;

  const ConnectionInitial({
    super.savedConnections = const [],
    this.host = '',
    this.port = '22',
    this.username = '',
    this.password = '',
  });
}

class ConnectionLoading extends ConnectionState {
  const ConnectionLoading({super.savedConnections = const []});
}

class ConnectionSuccess extends ConnectionState {
  final String host;
  final String username;

  const ConnectionSuccess({
    super.savedConnections = const [],
    required this.host,
    required this.username,
  });
}

class ConnectionFailure extends ConnectionState {
  final String errorMessage;

  const ConnectionFailure({
    super.savedConnections = const [],
    required this.errorMessage,
  });
}
