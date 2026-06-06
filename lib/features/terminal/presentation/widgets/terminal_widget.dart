import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:xterm/xterm.dart';
import 'package:dartssh2/dartssh2.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:path_provider/path_provider.dart';
import 'package:moly_ide/core/di/injection.dart';
import 'package:moly_ide/core/ssh/ssh_service.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/cubit/ide_cubit.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/cubit/ide_state.dart';

class TerminalWidget extends StatefulWidget {
  const TerminalWidget({super.key});

  @override
  State<TerminalWidget> createState() => _TerminalWidgetState();
}

class _TerminalWidgetState extends State<TerminalWidget> {
  static const _utilsChannel = MethodChannel('com.moly.moly_ide/utils');

  // Pattern: Claude Code tool calls that edit files — Edit(...) or Write(...)
  static final _claudeEditPattern = RegExp(
    r'(?<![a-zA-Z])(?:Edit|Write)\(([^)]+)\)',
  );

  final SSHService _sshService = locator<SSHService>();
  
  late final Terminal _terminal;
  late final TerminalController _terminalController;
  SSHSession? _session;
  bool _isConnecting = false;
  bool _showDpad = true;

  // URL auto-detection & native mobile browser launcher state
  String? _detectedUrl;
  String? _lastPromptedUrl;
  String _stdoutRollingBuffer = '';

  // Flutter APK build & download state
  bool _isFlutterBuilding = false;
  bool _apkBuildSuccess = false;
  bool _apkDownloadDone = false;
  bool _isDownloadingApk = false;
  double _downloadProgress = 0.0;
  String _apkRemotePath = '';
  String _buildProjectDir = '';
  String _lastKnownDir = '';

  // Terminal dimensions (updated dynamically from LayoutBuilder)
  int _termCols = 80;
  int _termRows = 24;

  // Auto-open: reference to IDECubit (set in build) + debounce set
  IDECubit? _ideCubit;
  final Set<String> _autoOpenDebounce = {};

  @override
  void initState() {
    super.initState();
    _terminal = Terminal(
      maxLines: 1000,
    );
    _terminalController = TerminalController();
    
    // Connect interactive shell once widget completes mounting
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startSession();
    });
  }

  @override
  void dispose() {
    _session?.close();
    if (_sshService.activeTerminalSession == _session) {
      _sshService.activeTerminalSession = null;
    }
    super.dispose();
  }

  Future<void> _startSession() async {
    if (_isConnecting) return;

    setState(() {
      _isConnecting = true;
      _detectedUrl = null;
      _lastPromptedUrl = null;
      _stdoutRollingBuffer = '';
      _isFlutterBuilding = false;
      _apkBuildSuccess = false;
      _apkDownloadDone = false;
      _isDownloadingApk = false;
      _downloadProgress = 0.0;
    });

    _terminal.write('\r\n\x1b[1;35m[Moly IDE] Conectando sesión terminal interactiva...\x1b[0m\r\n');

    try {
      final session = await _sshService.createShellSession(
        terminalWidth: _termCols,
        terminalHeight: _termRows,
      );

      _session = session;
      _sshService.activeTerminalSession = session;

      // Pipe SSH session stdout into Virtual Terminal and check for URLs
      session.stdout.cast<List<int>>().transform(utf8.decoder).listen(
        (data) {
          _terminal.write(data);
          _handleIncomingStdout(data);
        },
        onError: (err) {
          _terminal.write('\r\n\x1b[1;31m[Error de Terminal]: $err\x1b[0m\r\n');
        },
        onDone: () {
          _terminal.write('\r\n\x1b[1;33m[Conexión cerrada por el servidor]\x1b[0m\r\n');
        },
      );

      // Pipe Virtual Terminal inputs into SSH session stdin
      _terminal.onOutput = (input) {
        session.write(utf8.encode(input));
      };

      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }

      _terminal.write('\x1b[1;32m[Moly IDE] ¡Terminal conectada con éxito!\x1b[0m\r\n\r\n');
    } catch (e) {
      if (mounted) {
        setState(() {
          _isConnecting = false;
        });
      }
      _terminal.write('\x1b[1;31m[Moly IDE] Error al conectar terminal: $e\x1b[0m\r\n');
    }
  }

  // Send a quick preset command to terminal input
  void _sendPresetCommand(String command) {
    if (_session == null) return;
    _session!.write(utf8.encode('$command\r'));
  }

  // Paste clipboard contents directly into SSH session stdin
  Future<void> _handlePaste() async {
    if (_session == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: La sesión de terminal no está activa.'),
            backgroundColor: Color(0xFFFF5252),
          ),
        );
      }
      return;
    }
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData != null && clipboardData.text != null) {
        final text = clipboardData.text!;
        if (text.isNotEmpty) {
          // Send plain text directly to SSH stdin
          _session!.write(utf8.encode(text));
          
          if (mounted) {
            final visibleText = text.length > 25 ? '${text.substring(0, 25)}...' : text;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Pegado en terminal: "$visibleText"'),
                duration: const Duration(seconds: 3),
                action: SnackBarAction(
                  label: '↵ ENTER',
                  textColor: AppTheme.accentBlue,
                  onPressed: () {
                    if (_session != null) {
                      _session!.write(utf8.encode('\r'));
                    }
                  },
                ),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('El portapapeles contiene un texto vacío.'),
                duration: Duration(seconds: 1),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('El portapapeles está vacío o no contiene texto plano.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al pegar: $e'),
            backgroundColor: const Color(0xFFFF5252),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  // Copy selected terminal text into system clipboard
  Future<void> _handleCopy() async {
    try {
      final selection = _terminalController.selection;
      if (selection != null) {
        final text = _terminal.buffer.getText(selection);
        if (text.isNotEmpty) {
          await Clipboard.setData(ClipboardData(text: text));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Texto copiado al portapapeles.'),
                duration: Duration(seconds: 1),
              ),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('La selección está vacía.'),
                duration: Duration(seconds: 1),
              ),
            );
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No hay texto seleccionado. Mantén presionado y arrastra en la consola para seleccionar.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al copiar: $e'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<IDECubit, IDEState>(
      builder: (context, state) {
        // Keep track of the IDE directory and cubit reference for auto-open
        _lastKnownDir = state.currentDirectory;
        _ideCubit = context.read<IDECubit>();

        const isExpanded = true;
        final double width = MediaQuery.of(context).size.width;
        final isMobile = width < 500;

        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF07050E), // Ultra dark black for console vibes
            border: Border(
              top: BorderSide(color: AppTheme.border, width: 1.0),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Terminal Title Bar & Quick Actions
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                decoration: const BoxDecoration(
                  color: Color(0xFF0F0C1B),
                  border: Border(
                    bottom: BorderSide(color: AppTheme.border, width: 1.0),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.terminal_rounded,
                      size: 16,
                      color: AppTheme.primaryPurple,
                    ),
                    if (!isMobile) ...[
                      const SizedBox(width: 8),
                      Text(
                        'TERMINAL DEL VPS',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textSecondary,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                    
                    const SizedBox(width: 16),
                    
                    // Quick Action Presets inside a Horizontally Scrollable area!
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Gradient Claude Code button
                            GestureDetector(
                              onTap: () => _sendPresetCommand('claude'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  gradient: AppTheme.purpleBlueGradient,
                                  borderRadius: AppTheme.borderRadius,
                                  boxShadow: [
                                    BoxShadow(
                                      color: AppTheme.primaryPurple.withOpacity(0.3),
                                      blurRadius: 4,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.psychology_outlined, size: 12, color: Colors.white),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Claude Code',
                                      style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            
                            const SizedBox(width: 6),

                            // Build APK chip
                            _buildApkChip(state.currentDirectory),

                            const SizedBox(width: 6),

                            // Shortcut 2: Copiar (Copy) selected text
                            _buildCopyChip(),
                            
                            const SizedBox(width: 6),

                            // Shortcut 3: Paste from phone clipboard
                            _buildPasteChip(),

                            const SizedBox(width: 6),

                            // Shortcut 4: Toggle D-pad and helper keys
                            _buildTeclasToggleChip(),
                            
                            const SizedBox(width: 6),

                            // Shortcut 5: Clear
                            _buildPresetChip('Clear', 'clear'),

                            const SizedBox(width: 6),

                            // Shortcut 6: Git Status
                            _buildPresetChip('Git Status', 'git status'),

                            const SizedBox(width: 6),

                            // Shortcut 7: Directory List
                            _buildPresetChip('Listar', 'ls -la'),
                          ],
                        ),
                      ),
                    ),

                    // Refresh terminal session
                    IconButton(
                      icon: const Icon(Icons.sync_rounded, size: 16, color: Colors.white),
                      tooltip: 'Reiniciar Terminal',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        _session?.close();
                        _terminal.write('\x1b[2J\x1b[H');
                        _startSession();
                      },
                    ),
                  ],
                ),
              ),

              // Dedicated Dev Keys Panel (placed between header bar and terminal view)
              if (isExpanded && _showDpad)
                Container(
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Color(0xFF0C0A15), // Deep dark matching workspace console
                    border: Border(
                      bottom: BorderSide(color: AppTheme.border, width: 1.0),
                    ),
                  ),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    children: [
                      _buildHelperKey('Enter ↵', '\r'),
                      const SizedBox(width: 8),
                      _buildHelperKey('Tab', '\t'),
                      const SizedBox(width: 8),
                      _buildHelperKey('Esc', '\x1b'),
                      const SizedBox(width: 8),
                      _buildHelperKey('Ctrl+C', '\x03'),
                      const SizedBox(width: 8),
                      _buildHelperKey('Ctrl+Z', '\x1a'),
                      const SizedBox(width: 8),
                      _buildHelperKey('Ctrl+D', '\x04'),
                      const SizedBox(width: 8),
                      _buildHelperKey('Ctrl+A', '\x01'),
                      const SizedBox(width: 8),
                      _buildHelperKey('Ctrl+E', '\x05'),
                    ],
                  ),
                ),

              // Terminal Shell Output
              if (isExpanded)
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Fira Code 12px metrics: ~7.2px wide, ~16px tall per cell
                      const double charW = 7.2;
                      const double charH = 16.0;
                      const double padding = 8.0;
                      final cols = ((constraints.maxWidth - padding * 2) / charW).floor().clamp(40, 300);
                      final rows = ((constraints.maxHeight - padding * 2) / charH).floor().clamp(10, 80);
                      if (cols != _termCols || rows != _termRows) {
                        WidgetsBinding.instance.addPostFrameCallback((_) => _resizeTerminal(cols, rows));
                      }
                      return Stack(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(padding),
                            child: TerminalView(
                              _terminal,
                              controller: _terminalController,
                              backgroundOpacity: 0,
                              textStyle: TerminalStyle(
                                fontSize: 12,
                                fontFamily: GoogleFonts.firaCode().fontFamily ?? 'monospace',
                              ),
                            ),
                          ),
                          if (_detectedUrl != null && !_apkBuildSuccess)
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 12,
                              child: _buildDetectedUrlCard(),
                            ),
                          if (_apkBuildSuccess)
                            Positioned(
                              left: 12,
                              right: 12,
                              bottom: 12,
                              child: _buildApkCard(),
                            ),
                        ],
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

  void _detectAndOpenClaudeFiles(String cleanData) {
    final cubit = _ideCubit;
    if (cubit == null) return;

    for (final match in _claudeEditPattern.allMatches(cleanData)) {
      var path = (match.group(1) ?? '').trim();
      if (path.isEmpty || !path.contains('/')) continue;

      // Resolve relative paths using known current dir
      if (!path.startsWith('/')) {
        if (_lastKnownDir.isEmpty) continue;
        path = '$_lastKnownDir/$path';
      }

      // Skip non-file paths (directories, no extension with no dot at all)
      final name = path.split('/').last;
      if (name.isEmpty) continue;

      // Debounce: ignore same path within 4 seconds
      if (_autoOpenDebounce.contains(path)) continue;
      _autoOpenDebounce.add(path);
      Future.delayed(const Duration(seconds: 4), () => _autoOpenDebounce.remove(path));

      final existingIndex = cubit.state.openTabs.indexWhere((t) => t.path == path);
      if (existingIndex != -1) {
        // Already open — silently reload content if unmodified
        cubit.reloadOpenFile(path);
      } else {
        // Open new tab and show editor
        cubit.openFile(path, name);
      }
    }
  }

  void _resizeTerminal(int cols, int rows) {
    if (cols == _termCols && rows == _termRows) return;
    if (!mounted) return;
    _termCols = cols;
    _termRows = rows;
    _terminal.resize(cols, rows);
    _session?.resizeTerminal(cols, rows);
  }

  Widget _buildPresetChip(String label, String command) {
    return InkWell(
      onTap: () => _sendPresetCommand(command),
      borderRadius: AppTheme.borderRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: AppTheme.borderRadius,
          border: Border.all(color: AppTheme.border, width: 0.8),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 10,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildPasteChip() {
    return InkWell(
      onTap: _handlePaste,
      borderRadius: AppTheme.borderRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: AppTheme.borderRadius,
          border: Border.all(color: AppTheme.border, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.paste_rounded, size: 10, color: AppTheme.accentBlue),
            const SizedBox(width: 4),
            Text(
              'Pegar',
              style: GoogleFonts.outfit(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCopyChip() {
    return InkWell(
      onTap: _handleCopy,
      borderRadius: AppTheme.borderRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: AppTheme.borderRadius,
          border: Border.all(color: AppTheme.border, width: 0.8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.copy_rounded, size: 10, color: AppTheme.accentBlue),
            const SizedBox(width: 4),
            Text(
              'Copiar',
              style: GoogleFonts.outfit(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeclasToggleChip() {
    return InkWell(
      onTap: () {
        setState(() {
          _showDpad = !_showDpad;
        });
      },
      borderRadius: AppTheme.borderRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: _showDpad
              ? AppTheme.primaryPurple.withOpacity(0.15)
              : AppTheme.surfaceLight,
          borderRadius: AppTheme.borderRadius,
          border: Border.all(
            color: _showDpad ? AppTheme.primaryPurple : AppTheme.border,
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.keyboard_rounded,
              size: 10,
              color: _showDpad ? AppTheme.accentBlue : Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              'Teclas',
              style: GoogleFonts.outfit(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Process terminal stdout chunks in a sliding rolling buffer to detect URLs and build events
  void _handleIncomingStdout(String data) {
    // Strip ANSI escape sequences (e.g., color formatting \x1B[39m, cursor movement \x1B[2G)
    // to prevent URL parameters or paths from being broken up.
    final cleanData = data.replaceAll(RegExp(r'\x1B\[[0-9;]*[a-zA-Z]'), '');

    _stdoutRollingBuffer += cleanData;
    if (_stdoutRollingBuffer.length > 2000) {
      _stdoutRollingBuffer = _stdoutRollingBuffer.substring(_stdoutRollingBuffer.length - 2000);
    }
    _detectUrlsInRoll();
    _detectFlutterBuildCompletion();
    _detectAndOpenClaudeFiles(cleanData);
  }

  // Detect "✓  Built build/app/outputs/flutter-apk/app-release.apk" in the rolling buffer
  void _detectFlutterBuildCompletion() {
    if (_apkBuildSuccess) return;
    final buf = _stdoutRollingBuffer;
    if (buf.contains('app-release.apk') && buf.contains('Built ')) {
      final projectDir = _buildProjectDir.isNotEmpty ? _buildProjectDir : _lastKnownDir;
      const relPath = 'build/app/outputs/flutter-apk/app-release.apk';
      setState(() {
        _isFlutterBuilding = false;
        _apkBuildSuccess = true;
        _apkRemotePath = projectDir.isEmpty ? relPath : '$projectDir/$relPath';
      });
    }
  }

  // Scan rolling buffer for URLs using a robust character-by-character parser
  void _detectUrlsInRoll() {
    int startIndex = _stdoutRollingBuffer.lastIndexOf('https://');
    if (startIndex == -1) {
      startIndex = _stdoutRollingBuffer.lastIndexOf('http://');
    }
    if (startIndex == -1) return;

    StringBuffer url = StringBuffer();
    int i = startIndex;
    bool afterNewline = false;

    // Set of common English/Spanish terminal words that might follow a URL in terminal instructions
    final stopWords = {
      'and', 'to', 'enter', 'please', 'in', 'use', 'click', 'press', 'code', 'the', 'for', 'with', 'your',
      'y', 'para', 'introduzca', 'por', 'favor', 'en', 'haga', 'presione', 'codigo', 'el', 'su', 'con',
      'paste', 'here', 'if', 'prompted'
    };

    while (i < _stdoutRollingBuffer.length) {
      String char = _stdoutRollingBuffer[i];

      if (char == '\r' || char == '\n') {
        afterNewline = true;
        i++;
        continue;
      }

      if (afterNewline) {
        // Skip backslashes, spaces, and tabs after newline (indentation or line continuation escape)
        if (char == ' ' || char == '\t' || char == '\\') {
          i++;
          continue;
        }

        // We reached the first non-space character on the new line.
        // Let's grab the next word to see if it is a URL continuation or a separate sentence.
        int wordEnd = i;
        while (wordEnd < _stdoutRollingBuffer.length && 
               _stdoutRollingBuffer[wordEnd] != ' ' && 
               _stdoutRollingBuffer[wordEnd] != '\t' && 
               _stdoutRollingBuffer[wordEnd] != '\r' && 
               _stdoutRollingBuffer[wordEnd] != '\n') {
          wordEnd++;
        }
        String nextWord = _stdoutRollingBuffer.substring(i, wordEnd);

        // Check if it's a URL continuation:
        // Typically contains typical URL symbols like &, ?, =, %, / or is long and doesn't match stop words.
        bool isContinuation = false;
        if (nextWord.contains('&') || 
            nextWord.contains('?') || 
            nextWord.contains('=') || 
            nextWord.contains('%') || 
            nextWord.contains('/') ||
            nextWord.contains('#')) {
          isContinuation = true;
        } else if (nextWord.length > 5 && !stopWords.contains(nextWord.toLowerCase())) {
          isContinuation = true;
        }

        if (isContinuation) {
          afterNewline = false;
          // Continue parsing normally from this character
        } else {
          // It's a new sentence or word, so the URL has ended!
          break;
        }
      }

      // Normal parsing (when not immediately after a newline)
      if (char == ' ' || char == '\t' || char == '"' || char == '<' || char == '>' || char == '|') {
        break;
      }

      url.write(char);
      i++;
    }

    String rawUrl = url.toString();
    
    // Trim wrapping or trailing punctuation/quotes that belong to surrounding text
    while (rawUrl.endsWith('.') || 
           rawUrl.endsWith(',') || 
           rawUrl.endsWith(';') || 
           rawUrl.endsWith(':') ||
           rawUrl.endsWith("'") ||
           rawUrl.endsWith('"') ||
           rawUrl.endsWith(')') ||
           rawUrl.endsWith(']')) {
      rawUrl = rawUrl.substring(0, rawUrl.length - 1);
    }
    
    // If it's a new URL and different from the last prompted URL, display it
    if (rawUrl.isNotEmpty && rawUrl != _lastPromptedUrl) {
      setState(() {
        _detectedUrl = rawUrl;
        _lastPromptedUrl = rawUrl;
      });
    }
  }

  void _startFlutterBuild(String projectDir) {
    setState(() {
      _isFlutterBuilding = true;
      _apkBuildSuccess = false;
      _apkDownloadDone = false;
      _buildProjectDir = projectDir;
      _downloadProgress = 0.0;
    });
    _sendPresetCommand('flutter build apk --release');
  }

  void _closeApkCard() {
    setState(() {
      _apkBuildSuccess = false;
      _apkDownloadDone = false;
      _downloadProgress = 0.0;
    });
  }

  Future<void> _downloadApk() async {
    setState(() {
      _isDownloadingApk = true;
      _downloadProgress = 0.0;
    });

    try {
      final bytes = await _sshService.downloadFileBinary(
        _apkRemotePath,
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _downloadProgress = received / total);
          }
        },
      );

      final dir = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/app-release.apk';
      await File(filePath).writeAsBytes(bytes);

      if (mounted) {
        setState(() {
          _isDownloadingApk = false;
          _downloadProgress = 1.0;
          _apkDownloadDone = true;
        });
        await _utilsChannel.invokeMethod('installApk', {'path': filePath});
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloadingApk = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error al descargar APK: $e'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    }
  }

  void _closeUrlCard() {
    setState(() {
      _detectedUrl = null;
    });
  }

  // Build high-end floating glassmorphic Link / Login card
  Widget _buildDetectedUrlCard() {
    final urlStr = _detectedUrl ?? '';
    final isLogin = urlStr.contains('login') || 
                    urlStr.contains('auth') || 
                    urlStr.contains('oauth') || 
                    urlStr.contains('signin');
    
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0C1B).withOpacity(0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isLogin ? AppTheme.primaryPurple.withOpacity(0.6) : AppTheme.accentBlue.withOpacity(0.6),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: (isLogin ? AppTheme.primaryPurple : AppTheme.accentBlue).withOpacity(0.15),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    isLogin ? Icons.vpn_key_rounded : Icons.open_in_browser_rounded,
                    size: 16,
                    color: isLogin ? AppTheme.primaryPurple : AppTheme.accentBlue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isLogin ? '🔑 Inicio de Sesión Detectado' : '🔗 Enlace de Consola Detectado',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _closeUrlCard,
                    child: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // URL Display
              Text(
                urlStr,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.firaCode(
                  fontSize: 10,
                  color: AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              // Action Buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // Copy link button
                  InkWell(
                    onTap: () async {
                      if (urlStr.isNotEmpty) {
                        await Clipboard.setData(ClipboardData(text: urlStr));
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Enlace copiado al portapapeles.'),
                              duration: Duration(seconds: 1),
                            ),
                          );
                        }
                      }
                    },
                    borderRadius: AppTheme.borderRadius,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceLight,
                        borderRadius: AppTheme.borderRadius,
                        border: Border.all(color: AppTheme.border, width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.copy_rounded, size: 10, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'Copiar',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              color: Colors.white,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Launch in mobile default browser button
                  GestureDetector(
                    onTap: () async {
                      if (urlStr.isNotEmpty) {
                        try {
                          final Uri uri = Uri.parse(urlStr);
                          if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                            throw 'No se pudo abrir el enlace en el navegador externo.';
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error al abrir enlace: $e'),
                                backgroundColor: const Color(0xFFFF5252),
                              ),
                            );
                          }
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: AppTheme.purpleBlueGradient,
                        borderRadius: AppTheme.borderRadius,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primaryPurple.withOpacity(0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.launch_rounded, size: 10, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'Abrir en Móvil',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildApkChip(String currentDir) {
    return GestureDetector(
      onTap: () {
        if (!_isFlutterBuilding) _startFlutterBuild(currentDir);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          gradient: _isFlutterBuilding
              ? null
              : const LinearGradient(
                  colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
          color: _isFlutterBuilding ? AppTheme.surfaceLight : null,
          borderRadius: AppTheme.borderRadius,
          border: _isFlutterBuilding
              ? Border.all(color: const Color(0xFF43A047), width: 0.8)
              : null,
          boxShadow: _isFlutterBuilding
              ? null
              : [BoxShadow(color: const Color(0xFF1B5E20).withOpacity(0.4), blurRadius: 4)],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isFlutterBuilding)
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: Color(0xFF43A047)),
              )
            else
              const Icon(Icons.android_rounded, size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text(
              _isFlutterBuilding ? 'Compilando...' : 'Build APK',
              style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildApkCard() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8.0, sigmaY: 8.0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0C1B).withOpacity(0.85),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF43A047).withOpacity(0.6), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1B5E20).withOpacity(0.2),
                blurRadius: 10,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.android_rounded, size: 16, color: Color(0xFF43A047)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _apkDownloadDone ? 'APK listo para instalar' : 'APK compilado exitosamente',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  if (!_isDownloadingApk)
                    GestureDetector(
                      onTap: _closeApkCard,
                      child: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textSecondary),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _apkRemotePath,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.firaCode(fontSize: 10, color: AppTheme.textSecondary),
              ),
              if (_isDownloadingApk || _apkDownloadDone) ...[
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: _downloadProgress,
                  backgroundColor: AppTheme.surfaceLight,
                  valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF43A047)),
                  borderRadius: BorderRadius.circular(4),
                  minHeight: 6,
                ),
                const SizedBox(height: 4),
                Text(
                  _apkDownloadDone
                      ? 'Descarga completa — abriendo instalador...'
                      : 'Descargando... ${(_downloadProgress * 100).toStringAsFixed(0)}%',
                  style: GoogleFonts.outfit(fontSize: 10, color: AppTheme.textSecondary),
                  textAlign: TextAlign.end,
                ),
              ],
              if (!_isDownloadingApk && !_apkDownloadDone) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: _downloadApk,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1B5E20), Color(0xFF43A047)],
                        ),
                        borderRadius: AppTheme.borderRadius,
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF1B5E20).withOpacity(0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.download_rounded, size: 10, color: Colors.white),
                          const SizedBox(width: 4),
                          Text(
                            'Descargar e Instalar',
                            style: GoogleFonts.outfit(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHelperKey(String label, String sequence) {
    return InkWell(
      onTap: () {
        if (_session == null) return;
        _session!.write(utf8.encode(sequence));
      },
      borderRadius: AppTheme.borderRadius,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: AppTheme.borderRadius,
          border: Border.all(color: AppTheme.border, width: 0.8),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11,
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
