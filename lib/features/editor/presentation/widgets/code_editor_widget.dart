import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:google_fonts/google_fonts.dart';

// Highlight languages for syntax coloring
import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/xml.dart'; // Handles HTML/XML
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/cubit/ide_cubit.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/cubit/ide_state.dart';

class CodeEditorWidget extends StatefulWidget {
  const CodeEditorWidget({super.key});

  @override
  State<CodeEditorWidget> createState() => _CodeEditorWidgetState();
}

class _CodeEditorWidgetState extends State<CodeEditorWidget> {
  CodeController? _codeController;
  String? _lastLoadedPath;

  @override
  void dispose() {
    _codeController?.dispose();
    super.dispose();
  }

  // Map file extension to highlight parser language
  dynamic _getLanguageForExtension(String filename) {
    final ext = filename.split('.').last.toLowerCase();
    switch (ext) {
      case 'dart':
        return dart;
      case 'js':
      case 'ts':
        return javascript;
      case 'py':
        return python;
      case 'html':
      case 'xml':
        return xml;
      case 'css':
        return css;
      case 'json':
        return json;
      case 'md':
        return markdown;
      case 'yaml':
      case 'yml':
        return yaml;
      default:
        return null;
    }
  }

  void _initializeController(IDEFileTab activeTab) {
    _codeController?.dispose();
    _codeController = CodeController(
      text: activeTab.currentContent,
      language: _getLanguageForExtension(activeTab.name),
    );
    _lastLoadedPath = activeTab.path;

    // Listen to changes in the editor and send them to the IDECubit
    _codeController!.addListener(() {
      final text = _codeController!.text;
      final cubit = context.read<IDECubit>();
      if (cubit.state.activeTab?.currentContent != text) {
        cubit.updateFileDraft(text);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<IDECubit, IDEState>(
      builder: (context, state) {
        final activeTab = state.activeTab;

        if (activeTab == null) {
          return _buildEmptyState(context);
        }

        // Re-initialize controller only if the active tab file has changed
        if (_codeController == null || _lastLoadedPath != activeTab.path) {
          _initializeController(activeTab);
        } else {
          // If the model content was updated from outside (e.g. saved), synchronize
          if (_codeController!.text != activeTab.currentContent) {
            // Temporarily remove listener to avoid cycle
            _codeController!.text = activeTab.currentContent;
          }
        }

        return Container(
          color: const Color(0xFF0F0E17), // Deep dark workspace color
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Tab Bar Container
              _buildTabBar(context, state),

              // Code Field Editor
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    // Customizing scrollbars inside editor
                    scrollbarTheme: ScrollbarThemeData(
                      thumbColor: MaterialStateProperty.all(AppTheme.primaryPurple.withOpacity(0.3)),
                      radius: AppTheme.radius,
                    ),
                  ),
                  child: CodeTheme(
                    data: CodeThemeData(styles: monokaiSublimeTheme),
                    child: SingleChildScrollView(
                      child: CodeField(
                        controller: _codeController!,
                        textStyle: AppTheme.codeStyle,
                        lineNumberStyle: const LineNumberStyle(
                          width: 46,
                          textAlign: TextAlign.right,
                          margin: 16.0,
                          textStyle: TextStyle(
                            color: Color(0xFF4C476D),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabBar(BuildContext context, IDEState state) {
    return Container(
      height: 40,
      decoration: const BoxDecoration(
        color: Color(0xFF0B0A0F),
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1.0),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: state.openTabs.length,
              itemBuilder: (context, index) {
                final tab = state.openTabs[index];
                final isActive = index == state.activeTabIndex;

                return InkWell(
                  onTap: () => context.read<IDECubit>().selectTab(index),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: isActive ? const Color(0xFF0F0E17) : Colors.transparent,
                      border: Border(
                        right: const BorderSide(color: AppTheme.divider, width: 1.0),
                        top: BorderSide(
                          color: isActive ? AppTheme.accentBlue : Colors.transparent,
                          width: 2.0,
                        ),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Modified indicator dot
                        if (tab.isModified)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 8),
                            decoration: const BoxDecoration(
                              color: AppTheme.accentBlue,
                              shape: BoxShape.circle,
                            ),
                          ),
                        Text(
                          tab.name,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                            color: isActive ? Colors.white : AppTheme.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Close tab button
                        GestureDetector(
                          onTap: () => context.read<IDECubit>().closeTab(index),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              Icons.close,
                              size: 12,
                              color: isActive ? AppTheme.textSecondary : AppTheme.textSecondary.withOpacity(0.5),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          // Symmetrical close editor button
          IconButton(
            icon: const Icon(
              Icons.keyboard_double_arrow_right_rounded,
              size: 18,
              color: Color(0xFFFF5252),
            ),
            tooltip: 'Ocultar Editor',
            onPressed: () => context.read<IDECubit>().toggleEditor(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Container(
      color: const Color(0xFF0D0C15),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showIcon = constraints.maxHeight > 240;
          final spacing = showIcon ? 24.0 : 8.0;
          
          return Center(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showIcon) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryPurple.withOpacity(0.04),
                        borderRadius: AppTheme.borderRadius,
                        border: Border.all(
                          color: AppTheme.border.withOpacity(0.2),
                          width: 1.5,
                        ),
                      ),
                      child: const Icon(
                        Icons.code_off_rounded,
                        size: 48,
                        color: AppTheme.border,
                      ),
                    ),
                    SizedBox(height: spacing),
                  ],
                  Text(
                    'No hay archivos abiertos',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    child: Text(
                      'Selecciona un archivo del explorador izquierdo para comenzar a codificar.\nUsa la terminal de abajo para interactuar con Claude Code.',
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: AppTheme.textSecondary,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
