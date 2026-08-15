import 'package:moly_ide/features/explorer_readonly/data/models/file_models.dart';

enum ReadonlyExplorerStatus { initial, loading, success, failure }

class ReadonlyExplorerState {
  final ReadonlyExplorerStatus status;
  final String currentPath;
  final List<RemoteFileItem> files;
  final String? openFileName;
  final String? openFileContent;
  final String? errorMessage;

  const ReadonlyExplorerState({
    this.status = ReadonlyExplorerStatus.initial,
    this.currentPath = '/root',
    this.files = const [],
    this.openFileName,
    this.openFileContent,
    this.errorMessage,
  });

  ReadonlyExplorerState copyWith({
    ReadonlyExplorerStatus? status,
    String? currentPath,
    List<RemoteFileItem>? files,
    String? openFileName,
    String? openFileContent,
    bool clearFile = false,
    String? errorMessage,
  }) {
    return ReadonlyExplorerState(
      status: status ?? this.status,
      currentPath: currentPath ?? this.currentPath,
      files: files ?? this.files,
      openFileName: clearFile ? null : (openFileName ?? this.openFileName),
      openFileContent: clearFile ? null : (openFileContent ?? this.openFileContent),
      errorMessage: errorMessage,
    );
  }
}
