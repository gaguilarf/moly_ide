import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/di/injection.dart';
import 'package:moly_ide/core/ssh/ssh_service.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/cubit/ide_cubit.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/cubit/ide_state.dart';

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

  @override
  void initState() {
    super.initState();
    // Initial load will be triggered by directory changes in BlocBuilder
  }

  Future<void> _loadDirectoryContents(String path) async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await _sshService.listDirectory(path);
      
      // Sort: Directories first, then files alphabetically
      items.sort((a, b) {
        final aIsDir = a.attr.isDirectory;
        final bIsDir = b.attr.isDirectory;
        
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return a.filename.compareTo(b.filename);
      });

      // Filter out dot files/folders (except parent ..)
      final filteredItems = items.where((item) {
        return item.filename == '..' || !item.filename.startsWith('.');
      }).toList();

      if (mounted) {
        setState(() {
          _items = filteredItems;
          _isLoading = false;
        });
      }
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

  void _navigateToParent(String currentPath) {
    if (currentPath == '/' || currentPath.isEmpty) return;
    
    // Resolve parent directory path
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
              if (value.contains('/')) {
                return 'Nombre inválido';
              }
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
                final fullPath = currentPath == '/' ? '/$name' : '$currentPath/$name';
                
                Navigator.pop(dialContext);
                
                setState(() => _isLoading = true);
                try {
                  if (isDirectory) {
                    await _sshService.createDirectory(fullPath).timeout(const Duration(seconds: 5));
                  } else {
                    await _sshService.writeFile(fullPath, '').timeout(const Duration(seconds: 5));
                  }
                  _loadDirectoryContents(currentPath);
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al crear elemento: $e'),
                      backgroundColor: const Color(0xFFFF5252),
                    ),
                  );
                  setState(() => _isLoading = false);
                }
              }
            },
            child: const Text('Crear'),
          ),
        ],
      ),
    );
  }

  void _showRenameDialog(SftpName item, String currentPath) {
    final textController = TextEditingController(text: item.filename);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialContext) => AlertDialog(
        title: Text('Renombrar', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: textController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nuevo nombre'),
            validator: (value) {
              if (value == null || value.trim().isEmpty) return 'El nombre no puede estar vacío';
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
                final oldPath = currentPath == '/' ? '/${item.filename}' : '$currentPath/${item.filename}';
                final newPath = currentPath == '/' ? '/$newName' : '$currentPath/$newName';

                Navigator.pop(dialContext);
                setState(() => _isLoading = true);
                try {
                  await _sshService.rename(oldPath, newPath).timeout(const Duration(seconds: 5));
                  _loadDirectoryContents(currentPath);
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error al renombrar: $e'),
                        backgroundColor: const Color(0xFFFF5252),
                      ),
                    );
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

  void _showDeleteDialog(SftpName item, String currentPath) {
    final fullPath = currentPath == '/' ? '/${item.filename}' : '$currentPath/${item.filename}';
    final isDir = item.attr.isDirectory;

    showDialog(
      context: context,
      builder: (dialContext) => AlertDialog(
        title: Text('Eliminar Elemento', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        content: Text('¿Estás seguro de que deseas eliminar permanentemente ${isDir ? "la carpeta" : "el archivo"} "${item.filename}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialContext),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialContext);
              setState(() => _isLoading = true);
              try {
                if (isDir) {
                  await _sshService.deleteDirectory(fullPath);
                } else {
                  await _sshService.deleteFile(fullPath);
                }
                _loadDirectoryContents(currentPath);
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error al eliminar: $e'),
                    backgroundColor: const Color(0xFFFF5252),
                  ),
                );
                setState(() => _isLoading = false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5252)),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<IDECubit, IDEState>(
      listenWhen: (previous, current) => previous.currentDirectory != current.currentDirectory,
      listener: (context, state) {
        _loadDirectoryContents(state.currentDirectory);
      },
      builder: (context, state) {
        // Initial load trigger on first build
        if (_items.isEmpty && !_isLoading && _error == null && state.currentDirectory.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _loadDirectoryContents(state.currentDirectory);
          });
        }

        final currentDir = state.currentDirectory;

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0C0A15), // Deep dark violet-black for explorer sidebar
            border: Border(
              right: BorderSide(color: AppTheme.border, width: 1.2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Sidebar Header
              Container(
                padding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppTheme.border, width: 1.0),
                  ),
                ),
                child: Row(
                  children: [
                    const Expanded(
                      child: SizedBox.shrink(),
                    ),
                    // Action Buttons: New File, New Folder, Refresh
                    IconButton(
                      icon: const Icon(Icons.note_add_outlined, size: 18, color: AppTheme.accentBlue),
                      tooltip: 'Nuevo Archivo',
                      onPressed: () => _showCreateDialog(isDirectory: false, currentPath: currentDir),
                    ),
                    IconButton(
                      icon: const Icon(Icons.create_new_folder_outlined, size: 18, color: AppTheme.primaryPurple),
                      tooltip: 'Nueva Carpeta',
                      onPressed: () => _showCreateDialog(isDirectory: true, currentPath: currentDir),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 18, color: AppTheme.textPrimary),
                      tooltip: 'Actualizar',
                      onPressed: () => _loadDirectoryContents(currentDir),
                    ),
                    IconButton(
                      icon: const Icon(Icons.keyboard_double_arrow_left_rounded, size: 18, color: Color(0xFFFF5252)),
                      tooltip: 'Ocultar Explorador',
                      onPressed: () => context.read<IDECubit>().toggleExplorer(),
                    ),
                  ],
                ),
              ),

              // Breadcrumb Navigation
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                color: AppTheme.surface.withOpacity(0.4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        currentDir,
                        style: GoogleFonts.firaCode(
                          fontSize: 11,
                          color: AppTheme.accentBlue,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (currentDir != '/' && currentDir.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.arrow_upward_rounded, size: 16, color: Colors.white),
                        tooltip: 'Subir Nivel',
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        onPressed: () => _navigateToParent(currentDir),
                      ),
                  ],
                ),
              ),

              // Items List
              Expanded(
                child: _isLoading
                    ? const Center(
                        child: CircularProgressIndicator(strokeWidth: 2.0, color: AppTheme.primaryPurple),
                      )
                    : _error != null
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const Icon(Icons.error_outline, color: Color(0xFFFF5252), size: 36),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Error al cargar:',
                                    style: GoogleFonts.outfit(color: const Color(0xFFFF5252), fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _error!,
                                    style: GoogleFonts.firaCode(fontSize: 10, color: AppTheme.textSecondary),
                                    textAlign: TextAlign.center,
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : _items.isEmpty
                            ? Center(
                                child: Text(
                                  'Carpeta Vacía',
                                  style: GoogleFonts.outfit(color: AppTheme.textSecondary),
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(vertical: 4.0),
                                itemCount: _items.length,
                                itemBuilder: (context, index) {
                                  final item = _items[index];
                                  if (item.filename == '.' || item.filename == '..') {
                                    return const SizedBox.shrink();
                                  }

                                  final isDir = item.attr.isDirectory;
                                  final itemPath = currentDir == '/' ? '/${item.filename}' : '$currentDir/${item.filename}';

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        if (isDir) {
                                          context.read<IDECubit>().changeDirectory(itemPath);
                                        } else {
                                          context.read<IDECubit>().openFile(itemPath, item.filename);
                                        }
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                                        child: Row(
                                          children: [
                                            Icon(
                                              isDir ? Icons.folder : Icons.insert_drive_file_outlined,
                                              size: 18,
                                              color: isDir ? AppTheme.primaryPurple : AppTheme.accentBlue,
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                item.filename,
                                                style: GoogleFonts.outfit(
                                                  fontSize: 13,
                                                  color: Colors.white,
                                                  fontWeight: isDir ? FontWeight.w500 : FontWeight.normal,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            // Options Menu (Rename/Delete)
                                            PopupMenuButton<String>(
                                              icon: const Icon(Icons.more_vert, size: 16, color: AppTheme.textSecondary),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              itemBuilder: (context) => [
                                                const PopupMenuItem(
                                                  value: 'rename',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.drive_file_rename_outline, size: 16, color: AppTheme.accentBlue),
                                                      SizedBox(width: 8),
                                                      Text('Renombrar'),
                                                    ],
                                                  ),
                                                ),
                                                const PopupMenuItem(
                                                  value: 'delete',
                                                  child: Row(
                                                    children: [
                                                      Icon(Icons.delete, size: 16, color: Color(0xFFFF5252)),
                                                      SizedBox(width: 8),
                                                      Text('Eliminar', style: TextStyle(color: Color(0xFFFF5252))),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                              onSelected: (value) {
                                                if (value == 'rename') {
                                                  _showRenameDialog(item, currentDir);
                                                } else if (value == 'delete') {
                                                  _showDeleteDialog(item, currentDir);
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
              ),
            ],
          ),
        );
      },
    );
  }
}
