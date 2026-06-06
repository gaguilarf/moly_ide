import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/di/injection.dart';
import 'package:moly_ide/core/ssh/ssh_service.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/cubit/ide_cubit.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/cubit/ide_state.dart';

enum _GitStatus { modified, added, deleted, renamed, untracked }

class _GitChangedFile {
  final String relPath;
  final String absPath;
  final _GitStatus status;

  _GitChangedFile({
    required this.relPath,
    required this.absPath,
    required this.status,
  });

  String get filename => relPath.split('/').last;
}

class _TreeItem {
  final SftpName node;
  final String fullPath;
  final int depth;

  const _TreeItem({
    required this.node,
    required this.fullPath,
    required this.depth,
  });
}

class FileExplorerWidget extends StatefulWidget {
  const FileExplorerWidget({super.key});

  @override
  State<FileExplorerWidget> createState() => _FileExplorerWidgetState();
}

class _FileExplorerWidgetState extends State<FileExplorerWidget> {
  final SSHService _sshService = locator<SSHService>();

  List<SftpName> _items = [];
  bool _isLoading = false;
  String? _error;

  // Tree state
  final Set<String> _expandedPaths = {};
  final Map<String, List<SftpName>> _childrenCache = {};
  final Set<String> _loadingPaths = {};

  // Git state
  Map<String, _GitStatus> _gitStatusByFilename = {};
  List<_GitChangedFile> _changedFiles = [];
  bool _showChangesSection = true;

  Future<void> _loadDirectoryContents(String path) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await _sshService.listDirectory(path);
      _sortItems(items);
      final filtered =
          items.where((i) => i.filename == '..' || !i.filename.startsWith('.')).toList();
      if (mounted) {
        setState(() {
          _items = filtered;
          _isLoading = false;
        });
      }
      _loadGitStatus(path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _items = [];
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _sortItems(List<SftpName> items) {
    items.sort((a, b) {
      final aIsDir = a.attr.isDirectory;
      final bIsDir = b.attr.isDirectory;
      if (aIsDir && !bIsDir) return -1;
      if (!aIsDir && bIsDir) return 1;
      return a.filename.compareTo(b.filename);
    });
  }

  Future<void> _toggleExpand(String path) async {
    if (_expandedPaths.contains(path)) {
      setState(() => _expandedPaths.remove(path));
      return;
    }
    if (!_childrenCache.containsKey(path)) {
      setState(() => _loadingPaths.add(path));
      try {
        final items = await _sshService.listDirectory(path);
        _sortItems(items);
        final filtered =
            items.where((i) => i.filename != '..' && !i.filename.startsWith('.')).toList();
        if (mounted) {
          setState(() {
            _childrenCache[path] = filtered;
            _loadingPaths.remove(path);
            _expandedPaths.add(path);
          });
        }
      } catch (_) {
        if (mounted) setState(() => _loadingPaths.remove(path));
      }
    } else {
      setState(() => _expandedPaths.add(path));
    }
  }

  List<_TreeItem> _buildFlatTree(List<SftpName> items, String parentPath, int depth) {
    final result = <_TreeItem>[];
    for (final item in items) {
      if (item.filename == '.' || item.filename == '..') continue;
      final fullPath =
          parentPath == '/' ? '/${item.filename}' : '$parentPath/${item.filename}';
      result.add(_TreeItem(node: item, fullPath: fullPath, depth: depth));
      if (item.attr.isDirectory && _expandedPaths.contains(fullPath)) {
        final children = _childrenCache[fullPath];
        if (children != null) {
          result.addAll(_buildFlatTree(children, fullPath, depth + 1));
        }
      }
    }
    return result;
  }

  void _invalidateAndReload(String currentDir) {
    _expandedPaths.clear();
    _childrenCache.clear();
    _loadingPaths.clear();
    _loadDirectoryContents(currentDir);
  }

  Future<void> _loadGitStatus(String path) async {
    try {
      final rootRaw = await _sshService.executeCommand(
        'git -C "$path" rev-parse --show-toplevel 2>/dev/null',
      );
      final gitRoot = rootRaw.trim();
      if (gitRoot.isEmpty) return;

      final statusRaw = await _sshService.executeCommand(
        'git -C "$path" status --porcelain 2>/dev/null',
      );

      final Map<String, _GitStatus> statusByFilename = {};
      final List<_GitChangedFile> changedFiles = [];

      for (final line in statusRaw.split('\n')) {
        if (line.length < 4) continue;
        final xy = line.substring(0, 2);
        var filePath = line.substring(3).trim();
        if (filePath.contains(' -> ')) {
          filePath = filePath.split(' -> ').last;
        }
        if (filePath.isEmpty) continue;

        final _GitStatus status;
        if (xy == '??' || xy == '!!') {
          status = _GitStatus.untracked;
        } else if (xy[0] == 'D' || xy[1] == 'D') {
          status = _GitStatus.deleted;
        } else if (xy[0] == 'A' && xy[1] == ' ') {
          status = _GitStatus.added;
        } else if (xy[0] == 'R' || xy[1] == 'R') {
          status = _GitStatus.renamed;
        } else {
          status = _GitStatus.modified;
        }

        final absPath = '$gitRoot/$filePath';
        final filename = filePath.split('/').last;
        statusByFilename[filename] = status;
        changedFiles.add(_GitChangedFile(
          relPath: filePath,
          absPath: absPath,
          status: status,
        ));
      }

      if (mounted) {
        setState(() {
          _gitStatusByFilename = statusByFilename;
          _changedFiles = changedFiles;
        });
      }
    } catch (_) {}
  }

  void _navigateToParent(String currentPath) {
    if (currentPath == '/' || currentPath.isEmpty) return;
    final parts = currentPath.split('/');
    parts.removeLast();
    if (parts.isEmpty || (parts.length == 1 && parts[0].isEmpty)) {
      context.read<IDECubit>().changeDirectory('/');
    } else {
      context.read<IDECubit>().changeDirectory(parts.join('/'));
    }
  }

  void _showCreateDialog({required bool isDirectory, required String currentPath}) {
    final textController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialContext) => AlertDialog(
        title: Text(
          isDirectory ? 'Nueva Carpeta' : 'Nuevo Archivo',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
        ),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: textController,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Nombre',
              hintText: isDirectory ? 'ej. src, lib, assets' : 'ej. main.py, index.js',
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'El nombre no puede estar vacío';
              }
              if (value.contains('/')) return 'Nombre inválido';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final name = textController.text.trim();
                final fullPath =
                    currentPath == '/' ? '/$name' : '$currentPath/$name';
                Navigator.pop(dialContext);
                setState(() => _isLoading = true);
                try {
                  if (isDirectory) {
                    await _sshService
                        .createDirectory(fullPath)
                        .timeout(const Duration(seconds: 5));
                  } else {
                    await _sshService
                        .writeFile(fullPath, '')
                        .timeout(const Duration(seconds: 5));
                  }
                  _invalidateAndReload(currentPath);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Error al crear elemento: $e'),
                      backgroundColor: const Color(0xFFFF5252),
                    ));
                    setState(() => _isLoading = false);
                  }
                }
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(SftpName item, String itemFullPath) {
    final textController = TextEditingController(text: item.filename);
    final formKey = GlobalKey<FormState>();
    final lastSlash = itemFullPath.lastIndexOf('/');
    final parentPath = lastSlash <= 0 ? '/' : itemFullPath.substring(0, lastSlash);

    showDialog(
      context: context,
      builder: (dialContext) => AlertDialog(
        title: Text('Renombrar',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nuevo nombre'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'El nombre no puede estar vacío';
              }
              if (value.contains('/')) return 'Nombre inválido';
              if (value.trim() == item.filename) return 'El nombre es igual al actual';
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (formKey.currentState?.validate() ?? false) {
                final newName = textController.text.trim();
                final newPath =
                    parentPath == '/' ? '/$newName' : '$parentPath/$newName';
                Navigator.pop(dialContext);
                final currentDir =
                    context.read<IDECubit>().state.currentDirectory;
                setState(() => _isLoading = true);
                try {
                  await _sshService
                      .rename(itemFullPath, newPath)
                      .timeout(const Duration(seconds: 5));
                  _invalidateAndReload(currentDir);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                      content: Text('Error al renombrar: $e'),
                      backgroundColor: const Color(0xFFFF5252),
                    ));
                    setState(() => _isLoading = false);
                  }
                }
              }
            },
            child: const Text('Renombrar'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(SftpName item, String itemFullPath) {
    final isDir = item.attr.isDirectory;

    showDialog(
      context: context,
      builder: (dialContext) => AlertDialog(
        title: Text('Eliminar Elemento',
            style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text(
            '¿Estás seguro de que deseas eliminar permanentemente '
            '${isDir ? "la carpeta" : "el archivo"} "${item.filename}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialContext);
              final currentDir =
                  context.read<IDECubit>().state.currentDirectory;
              setState(() => _isLoading = true);
              try {
                if (isDir) {
                  await _sshService.deleteDirectory(itemFullPath);
                } else {
                  await _sshService.deleteFile(itemFullPath);
                }
                _invalidateAndReload(currentDir);
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Error al eliminar: $e'),
                    backgroundColor: const Color(0xFFFF5252),
                  ));
                  setState(() => _isLoading = false);
                }
              }
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF5252)),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  Color _gitStatusColor(_GitStatus status) {
    return switch (status) {
      _GitStatus.modified => const Color(0xFFE5C07B),
      _GitStatus.added => const Color(0xFF98C379),
      _GitStatus.deleted => const Color(0xFFE06C75),
      _GitStatus.renamed => const Color(0xFFC678DD),
      _GitStatus.untracked => const Color(0xFF56B6C2),
    };
  }

  String _gitStatusLetter(_GitStatus status) {
    return switch (status) {
      _GitStatus.modified => 'M',
      _GitStatus.added => 'A',
      _GitStatus.deleted => 'D',
      _GitStatus.renamed => 'R',
      _GitStatus.untracked => 'U',
    };
  }

  Widget _buildTreeRow(BuildContext context, _TreeItem treeItem) {
    final item = treeItem.node;
    final isDir = item.attr.isDirectory;
    final itemPath = treeItem.fullPath;
    final depth = treeItem.depth;
    final gitStatus = _gitStatusByFilename[item.filename];
    final isExpanded = _expandedPaths.contains(itemPath);
    final isLoadingDir = _loadingPaths.contains(itemPath);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (isDir) {
            _toggleExpand(itemPath);
          } else {
            context.read<IDECubit>().openFile(itemPath, item.filename);
          }
        },
        child: Padding(
          padding: EdgeInsets.only(
            left: 8.0 + depth * 16.0,
            right: 4.0,
            top: 6.0,
            bottom: 6.0,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: isDir
                    ? isLoadingDir
                        ? const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: AppTheme.primaryPurple,
                            ),
                          )
                        : Icon(
                            isExpanded
                                ? Icons.expand_more
                                : Icons.chevron_right,
                            size: 16,
                            color: AppTheme.textSecondary,
                          )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 2),
              Icon(
                isDir
                    ? (isExpanded ? Icons.folder_open : Icons.folder)
                    : Icons.insert_drive_file_outlined,
                size: 16,
                color: isDir ? AppTheme.primaryPurple : AppTheme.accentBlue,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  item.filename,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: gitStatus != null
                        ? _gitStatusColor(gitStatus)
                        : Colors.white,
                    fontWeight: isDir ? FontWeight.w500 : FontWeight.normal,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (gitStatus != null)
                Container(
                  width: 16,
                  height: 16,
                  margin: const EdgeInsets.only(right: 2),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _gitStatusColor(gitStatus).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    _gitStatusLetter(gitStatus),
                    style: GoogleFonts.firaCode(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: _gitStatusColor(gitStatus),
                    ),
                  ),
                ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert,
                    size: 14, color: AppTheme.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'rename',
                    child: Row(children: [
                      Icon(Icons.drive_file_rename_outline,
                          size: 16, color: AppTheme.accentBlue),
                      SizedBox(width: 8),
                      Text('Renombrar'),
                    ]),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(children: [
                      Icon(Icons.delete, size: 16, color: Color(0xFFFF5252)),
                      SizedBox(width: 8),
                      Text('Eliminar',
                          style: TextStyle(color: Color(0xFFFF5252))),
                    ]),
                  ),
                ],
                onSelected: (value) {
                  if (value == 'rename') {
                    _showRenameDialog(item, itemPath);
                  } else if (value == 'delete') {
                    _showDeleteDialog(item, itemPath);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<IDECubit, IDEState>(
      listenWhen: (previous, current) =>
          previous.currentDirectory != current.currentDirectory,
      listener: (context, state) {
        _gitStatusByFilename = {};
        _changedFiles = [];
        _expandedPaths.clear();
        _childrenCache.clear();
        _loadingPaths.clear();
        _loadDirectoryContents(state.currentDirectory);
      },
      builder: (context, state) {
        if (_items.isEmpty &&
            !_isLoading &&
            _error == null &&
            state.currentDirectory.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadDirectoryContents(state.currentDirectory);
          });
        }

        final currentDir = state.currentDirectory;
        final treeItems = _buildFlatTree(_items, currentDir, 0);

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0C0A15),
            border: Border(
              right: BorderSide(color: AppTheme.border, width: 1.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppTheme.border, width: 1.0),
                  ),
                ),
                child: Row(
                  children: [
                    const Expanded(child: SizedBox.shrink()),
                    IconButton(
                      icon: const Icon(Icons.note_add_outlined,
                          size: 18, color: AppTheme.accentBlue),
                      tooltip: 'Nuevo Archivo',
                      onPressed: () => _showCreateDialog(
                          isDirectory: false, currentPath: currentDir),
                    ),
                    IconButton(
                      icon: const Icon(Icons.create_new_folder_outlined,
                          size: 18, color: AppTheme.primaryPurple),
                      tooltip: 'Nueva Carpeta',
                      onPressed: () => _showCreateDialog(
                          isDirectory: true, currentPath: currentDir),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded,
                          size: 18, color: AppTheme.textPrimary),
                      tooltip: 'Actualizar',
                      onPressed: () => _invalidateAndReload(currentDir),
                    ),
                    IconButton(
                      icon: const Icon(
                          Icons.keyboard_double_arrow_left_rounded,
                          size: 18,
                          color: Color(0xFFFF5252)),
                      tooltip: 'Ocultar Explorador',
                      onPressed: () =>
                          context.read<IDECubit>().toggleExplorer(),
                    ),
                  ],
                ),
              ),

              // Breadcrumb
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 8.0),
                color: AppTheme.surface.withOpacity(0.4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        currentDir,
                        style: GoogleFonts.firaCode(
                            fontSize: 11, color: AppTheme.accentBlue),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (currentDir != '/' && currentDir.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.arrow_upward_rounded,
                            size: 16, color: Colors.white),
                        tooltip: 'Subir Nivel',
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        onPressed: () => _navigateToParent(currentDir),
                      ),
                  ],
                ),
              ),

              // Git Changes Section
              if (_changedFiles.isNotEmpty) _buildChangesSection(context),

              // Tree List
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2.0,
                            color: AppTheme.primaryPurple),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.error_outline,
                                      color: Color(0xFFFF5252), size: 36),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Error al cargar:',
                                    style: GoogleFonts.outfit(
                                        color: const Color(0xFFFF5252),
                                        fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _error!,
                                    style: GoogleFonts.firaCode(
                                        fontSize: 10,
                                        color: AppTheme.textSecondary),
                                    textAlign: TextAlign.center,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : treeItems.isEmpty
                            ? Center(
                                child: Text(
                                  'Carpeta Vacía',
                                  style: GoogleFonts.outfit(
                                      color: AppTheme.textSecondary),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 4.0),
                                itemCount: treeItems.length,
                                itemBuilder: (context, index) =>
                                    _buildTreeRow(context, treeItems[index]),
                              ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildChangesSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () =>
              setState(() => _showChangesSection = !_showChangesSection),
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 6.0),
            color: const Color(0xFF0E0C1A),
            child: Row(
              children: [
                const Icon(Icons.source_outlined,
                    size: 14, color: Color(0xFFE5C07B)),
                const SizedBox(width: 6),
                Text(
                  'CAMBIOS (${_changedFiles.length})',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFFE5C07B),
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Icon(
                  _showChangesSection ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppTheme.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_showChangesSection)
          Container(
            constraints: const BoxConstraints(maxHeight: 180),
            color: const Color(0xFF090812),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 2),
              shrinkWrap: true,
              itemCount: _changedFiles.length,
              itemBuilder: (context, index) {
                final file = _changedFiles[index];
                final color = _gitStatusColor(file.status);
                final letter = _gitStatusLetter(file.status);

                return InkWell(
                  onTap: () {
                    if (file.status != _GitStatus.deleted) {
                      context
                          .read<IDECubit>()
                          .openFile(file.absPath, file.filename);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 5),
                    child: Row(
                      children: [
                        Container(
                          width: 16,
                          height: 16,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            letter,
                            style: GoogleFonts.firaCode(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: color,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            file.relPath,
                            style: GoogleFonts.firaCode(
                              fontSize: 11,
                              color: file.status == _GitStatus.deleted
                                  ? color.withOpacity(0.6)
                                  : color,
                              decoration: file.status == _GitStatus.deleted
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        const Divider(height: 1, color: AppTheme.border),
      ],
    );
  }
}
