import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:moly_ide/core/ssh/ssh_service.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/cubit/ide_state.dart';

class IDECubit extends Cubit<IDEState> {
  final SSHService _sshService;

  IDECubit({required SSHService sshService})
      : _sshService = sshService,
        super(const IDEState()) {
    initWorkspace();
  }

  Future<void> initWorkspace() async {
    try {
      final homeDir = await _sshService.getHomeDirectory();
      emit(state.copyWith(currentDirectory: homeDir));
    } catch (e) {
      emit(state.copyWith(
        currentDirectory: '/',
        errorMessage: () => 'Error al obtener directorio inicial: ${e.toString()}',
      ));
    }
  }

  void toggleExplorer() {
    emit(state.copyWith(isExplorerOpen: !state.isExplorerOpen));
  }

  void toggleEditor() {
    emit(state.copyWith(isEditorOpen: !state.isEditorOpen));
  }

  void setEditorOpen(bool open) {
    emit(state.copyWith(isEditorOpen: open));
  }

  void toggleTerminal() {
    emit(state.copyWith(isTerminalExpanded: !state.isTerminalExpanded));
  }

  void changeDirectory(String newPath) {
    emit(state.copyWith(currentDirectory: newPath));
  }

  Future<void> openFile(String path, String name) async {
    final existingIndex = state.openTabs.indexWhere((tab) => tab.path == path);
    if (existingIndex != -1) {
      emit(state.copyWith(
        activeTabIndex: existingIndex,
        isEditorOpen: true,
      ));
      return;
    }

    emit(state.copyWith(loadingFileMessage: () => 'Abriendo $name...'));

    try {
      final content = await _sshService.readFile(path);
      final newTab = IDEFileTab(
        path: path,
        name: name,
        originalContent: content,
        currentContent: content,
      );

      final updatedTabs = List<IDEFileTab>.from(state.openTabs)..add(newTab);
      final newIndex = updatedTabs.length - 1;

      emit(state.copyWith(
        openTabs: updatedTabs,
        activeTabIndex: newIndex,
        isEditorOpen: true,
        loadingFileMessage: () => null,
      ));

      // Load git diff in background — non-blocking
      _loadGitDiff(newIndex, path);
    } catch (e) {
      emit(state.copyWith(
        loadingFileMessage: () => null,
        errorMessage: () => 'Error al abrir el archivo: ${e.toString()}',
      ));
    }
  }

  Future<void> _loadGitDiff(int tabIndex, String filePath) async {
    try {
      final raw = await _sshService.executeCommand(
        'git diff HEAD -- "$filePath" 2>/dev/null',
      );
      final diffLines = _parseUnifiedDiff(raw);

      if (isClosed) return;
      if (tabIndex >= state.openTabs.length) return;

      final updatedTab = state.openTabs[tabIndex].copyWith(
        gitDiffLines: () => diffLines,
      );
      final updatedTabs = List<IDEFileTab>.from(state.openTabs);
      updatedTabs[tabIndex] = updatedTab;
      emit(state.copyWith(openTabs: updatedTabs));
    } catch (_) {
      // Non-critical — silently ignore diff loading errors
    }
  }

  List<GitDiffLine> _parseUnifiedDiff(String diffText) {
    final lines = diffText.split('\n');
    final result = <GitDiffLine>[];
    int currentNewLine = 0;
    bool inHunk = false;

    for (final line in lines) {
      if (line.startsWith('@@')) {
        final match = RegExp(r'\+(\d+)').firstMatch(line);
        if (match != null) {
          currentNewLine = int.parse(match.group(1)!) - 1;
        }
        inHunk = true;
        continue;
      }

      if (!inHunk || line.isEmpty) continue;

      if (line.startsWith('+') && !line.startsWith('+++')) {
        currentNewLine++;
        result.add(GitDiffLine(
          lineNumber: currentNewLine,
          content: line.substring(1),
          type: GitDiffLineType.added,
        ));
      } else if (line.startsWith('-') && !line.startsWith('---')) {
        result.add(GitDiffLine(
          content: line.substring(1),
          type: GitDiffLineType.removed,
        ));
      } else if (line.startsWith(' ')) {
        currentNewLine++;
        result.add(GitDiffLine(
          lineNumber: currentNewLine,
          content: line.substring(1),
          type: GitDiffLineType.context,
        ));
      }
    }

    return result;
  }

  void updateFileDraft(String newContent) {
    final activeTab = state.activeTab;
    if (activeTab == null) return;

    final isModified = newContent != activeTab.originalContent;
    final updatedTab = activeTab.copyWith(
      currentContent: newContent,
      isModified: isModified,
    );

    final updatedTabs = List<IDEFileTab>.from(state.openTabs);
    updatedTabs[state.activeTabIndex] = updatedTab;

    emit(state.copyWith(openTabs: updatedTabs));
  }

  Future<void> saveActiveFile() async {
    final activeTab = state.activeTab;
    if (activeTab == null || !activeTab.isModified) return;

    emit(state.copyWith(savingFileMessage: () => 'Guardando ${activeTab.name}...'));

    try {
      await _sshService.writeFile(activeTab.path, activeTab.currentContent);

      final updatedTab = IDEFileTab(
        path: activeTab.path,
        name: activeTab.name,
        originalContent: activeTab.currentContent,
        currentContent: activeTab.currentContent,
        isModified: false,
        gitDiffLines: const [], // reset diff after save (no changes vs HEAD now pending re-check)
      );

      final updatedTabs = List<IDEFileTab>.from(state.openTabs);
      updatedTabs[state.activeTabIndex] = updatedTab;

      emit(state.copyWith(
        openTabs: updatedTabs,
        savingFileMessage: () => null,
      ));

      // Reload diff after save
      _loadGitDiff(state.activeTabIndex, activeTab.path);
    } catch (e) {
      emit(state.copyWith(
        savingFileMessage: () => null,
        errorMessage: () => 'Error al guardar el archivo: ${e.toString()}',
      ));
    }
  }

  Future<void> reloadOpenFile(String path) async {
    final tabIndex = state.openTabs.indexWhere((t) => t.path == path);
    if (tabIndex == -1) return;
    final tab = state.openTabs[tabIndex];
    if (tab.isModified) return;
    try {
      final content = await _sshService.readFile(path);
      final updatedTab = IDEFileTab(
        path: tab.path,
        name: tab.name,
        originalContent: content,
        currentContent: content,
        isModified: false,
      );
      final updatedTabs = List<IDEFileTab>.from(state.openTabs);
      updatedTabs[tabIndex] = updatedTab;
      emit(state.copyWith(openTabs: updatedTabs));
      _loadGitDiff(tabIndex, path);
    } catch (_) {}
  }

  void closeTab(int index) {
    if (index < 0 || index >= state.openTabs.length) return;

    final updatedTabs = List<IDEFileTab>.from(state.openTabs)..removeAt(index);

    int newActiveIndex = state.activeTabIndex;
    if (updatedTabs.isEmpty) {
      newActiveIndex = -1;
    } else if (state.activeTabIndex >= updatedTabs.length) {
      newActiveIndex = updatedTabs.length - 1;
    } else if (state.activeTabIndex == index) {
      newActiveIndex = index > 0 ? index - 1 : 0;
    } else if (state.activeTabIndex > index) {
      newActiveIndex--;
    }

    emit(state.copyWith(
      openTabs: updatedTabs,
      activeTabIndex: newActiveIndex,
    ));
  }

  void selectTab(int index) {
    if (index >= 0 && index < state.openTabs.length) {
      emit(state.copyWith(activeTabIndex: index));
    }
  }

  void clearError() {
    emit(state.copyWith(errorMessage: () => null));
  }
}
