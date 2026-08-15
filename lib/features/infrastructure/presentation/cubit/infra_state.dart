import 'package:moly_ide/features/infrastructure/data/models/infra_models.dart';

enum InfraStatus { initial, loading, success, failure }

class InfraState {
  final InfraStatus status;
  final String selectedNode;
  final ServerInfrastructureModel? serverStatus;
  final String? errorMessage;

  const InfraState({
    this.status = InfraStatus.initial,
    this.selectedNode = 'vps-brittany',
    this.serverStatus,
    this.errorMessage,
  });

  InfraState copyWith({
    InfraStatus? status,
    String? selectedNode,
    ServerInfrastructureModel? serverStatus,
    String? errorMessage,
  }) {
    return InfraState(
      status: status ?? this.status,
      selectedNode: selectedNode ?? this.selectedNode,
      serverStatus: serverStatus ?? this.serverStatus,
      errorMessage: errorMessage,
    );
  }
}
