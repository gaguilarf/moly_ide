import 'package:moly_ide/features/documentation/data/models/doc_models.dart';

enum DocsStatus { initial, loading, success, failure }

class DocsState {
  final DocsStatus status;
  final List<DocItemModel> documents;
  final String? selectedDocPath;
  final String? selectedDocContent;
  final String? errorMessage;

  const DocsState({
    this.status = DocsStatus.initial,
    this.documents = const [],
    this.selectedDocPath,
    this.selectedDocContent,
    this.errorMessage,
  });

  DocsState copyWith({
    DocsStatus? status,
    List<DocItemModel>? documents,
    String? selectedDocPath,
    String? selectedDocContent,
    String? errorMessage,
  }) {
    return DocsState(
      status: status ?? this.status,
      documents: documents ?? this.documents,
      selectedDocPath: selectedDocPath ?? this.selectedDocPath,
      selectedDocContent: selectedDocContent ?? this.selectedDocContent,
      errorMessage: errorMessage,
    );
  }
}
