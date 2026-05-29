class IDEFileTab {
  final String path;
  final String name;
  final String originalContent;
  final String currentContent;
  final bool isModified;

  IDEFileTab({
    required this.path,
    required this.name,
    required this.originalContent,
    required this.currentContent,
    this.isModified = false,
  });

  IDEFileTab copyWith({
    String? currentContent,
    bool? isModified,
  }) {
    return IDEFileTab(
      path: path,
      name: name,
      originalContent: originalContent,
      currentContent: currentContent ?? this.currentContent,
      isModified: isModified ?? this.isModified,
    );
  }
}

class IDEState {
  final String currentDirectory;
  final List<IDEFileTab> openTabs;
  final int activeTabIndex;
  final bool isExplorerOpen;
  final bool isEditorOpen;
  final bool isTerminalExpanded;
  final String? loadingFileMessage;
  final String? savingFileMessage;
  final String? errorMessage;

  IDEFileTab? get activeTab =>
      openTabs.isNotEmpty && activeTabIndex >= 0 && activeTabIndex < openTabs.length
          ? openTabs[activeTabIndex]
          : null;

  const IDEState({
    this.currentDirectory = '',
    this.openTabs = const [],
    this.activeTabIndex = -1,
    this.isExplorerOpen = true,
    this.isEditorOpen = false,
    this.isTerminalExpanded = true,
    this.loadingFileMessage,
    this.savingFileMessage,
    this.errorMessage,
  });

  IDEState copyWith({
    String? currentDirectory,
    List<IDEFileTab>? openTabs,
    int? activeTabIndex,
    bool? isExplorerOpen,
    bool? isEditorOpen,
    bool? isTerminalExpanded,
    String? Function()? loadingFileMessage,
    String? Function()? savingFileMessage,
    String? Function()? errorMessage,
  }) {
    return IDEState(
      currentDirectory: currentDirectory ?? this.currentDirectory,
      openTabs: openTabs ?? this.openTabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
      isExplorerOpen: isExplorerOpen ?? this.isExplorerOpen,
      isEditorOpen: isEditorOpen ?? this.isEditorOpen,
      isTerminalExpanded: isTerminalExpanded ?? this.isTerminalExpanded,
      loadingFileMessage: loadingFileMessage != null ? loadingFileMessage() : this.loadingFileMessage,
      savingFileMessage: savingFileMessage != null ? savingFileMessage() : this.savingFileMessage,
      errorMessage: errorMessage != null ? errorMessage() : this.errorMessage,
    );
  }
}
