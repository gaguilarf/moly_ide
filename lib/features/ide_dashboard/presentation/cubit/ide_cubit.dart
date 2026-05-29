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

  // Initialize workspace to home directory
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

  // Toggle File Explorer Panel
  void toggleExplorer() {
    emit(state.copyWith(isExplorerOpen: !state.isExplorerOpen));
  }

  // Toggle Editor Panel
  void toggleEditor() {
    emit(state.copyWith(isEditorOpen: !state.isEditorOpen));
  }

  // Set Editor Panel Open/Closed State
  void setEditorOpen(bool open) {
    emit(state.copyWith(isEditorOpen: open));
  }

  // Toggle Terminal Panel
  void toggleTerminal() {
    emit(state.copyWith(isTerminalExpanded: !state.isTerminalExpanded));
  }

  // Set Current Working Directory
  void changeDirectory(String newPath) {
    emit(state.copyWith(currentDirectory: newPath));
  }

  // Open file from explorer
  Future<void> openFile(String path, String name) async {
    // Check if file is already open
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
      emit(state.copyWith(
        openTabs: updatedTabs,
        activeTabIndex: updatedTabs.length - 1,
        isEditorOpen: true,
        loadingFileMessage: () => null,
      ));
    } catch (e) {
      emit(state.copyWith(
        loadingFileMessage: () => null,
        errorMessage: () => 'Error al abrir el archivo: ${e.toString()}',
      ));
    }
  }

  // Update editor draft in real time
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

  // Save current active file
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
      );

      final updatedTabs = List<IDEFileTab>.from(state.openTabs);
      updatedTabs[state.activeTabIndex] = updatedTab;

      emit(state.copyWith(
        openTabs: updatedTabs,
        savingFileMessage: () => null,
      ));
    } catch (e) {
      emit(state.copyWith(
        savingFileMessage: () => null,
        errorMessage: () => 'Error al guardar el archivo: ${e.toString()}',
      ));
    }
  }

  // Close Tab
  void closeTab(int index) {
    if (index < 0 || index >= state.openTabs.length) return;

    final updatedTabs = List<IDEFileTab>.from(state.openTabs)..removeAt(index);
    
    int newActiveIndex = state.activeTabIndex;
    if (updatedTabs.isEmpty) {
      newActiveIndex = -1;
    } else if (state.activeTabIndex >= updatedTabs.length) {
      newActiveIndex = updatedTabs.length - 1;
    } else if (state.activeTabIndex == index) {
      // If we closed the active tab, select a neighboring tab
      newActiveIndex = index > 0 ? index - 1 : 0;
    } else if (state.activeTabIndex > index) {
      newActiveIndex--;
    }

    emit(state.copyWith(
      openTabs: updatedTabs,
      activeTabIndex: newActiveIndex,
    ));
  }

  // Select Tab
  void selectTab(int index) {
    if (index >= 0 && index < state.openTabs.length) {
      emit(state.copyWith(activeTabIndex: index));
    }
  }

  // Clear active error
  void clearError() {
    emit(state.copyWith(errorMessage: () => null));
  }
}
