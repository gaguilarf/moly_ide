import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:code_text_field/code_text_field.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:highlight/languages/dart.dart';
import 'package:highlight/languages/javascript.dart';
import 'package:highlight/languages/python.dart';
import 'package:highlight/languages/xml.dart';
import 'package:highlight/languages/css.dart';
import 'package:highlight/languages/json.dart';
import 'package:highlight/languages/markdown.dart';
import 'package:highlight/languages/yaml.dart';
import 'package:flutter_highlight/themes/monokai-sublime.dart';

import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/cubit/ide_cubit.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/cubit/ide_state.dart';
import 'package:moly_ide/features/editor/presentation/widgets/git_diff_view.dart';

class CodeEditorWidget extends StatefulWidget {
  const CodeEditorWidget({super.key});

  @override
  State<CodeEditorWidget> createState() => _CodeEditorWidgetState();
}

class _CodeEditorWidgetState extends State<CodeEditorWidget> {
  CodeController? _codeController;
  String? _lastLoadedPath;
  bool _showDiffView = false;

  @override
  void dispose() {
    _codeController?.dispose();
    super.dispose();
  }

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

        if (_codeController == null || _lastLoadedPath != activeTab.path) {
          _initializeController(activeTab);
          _showDiffView = false; // reset diff view when tab changes
        } else {
          if (_codeController!.text != activeTab.currentContent) {
            _codeController!.text = activeTab.currentContent;
          }
        }

        return Container(
          color: const Color(0xFF0F0E17),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildTabBar(context, state),
              Expanded(
                child: _showDiffView && activeTab.gitDiffLines != null
                    ? GitDiffView(diffLines: activeTab.gitDiffLines!)
                    : Theme(
                        data: Theme.of(context).copyWith(
                          scrollbarTheme: ScrollbarThemeData(
                            thumbColor: WidgetStateProperty.all(
                              AppTheme.primaryPurple.withOpacity(0.3),
                            ),
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
    final activeTab = state.activeTab;
    final hasDiff = activeTab?.hasGitDiff ?? false;
    final diffLoaded = activeTab?.gitDiffLines != null;

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
                        // Git diff indicator dot (orange if has diff)
                        if (tab.hasGitDiff)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFE5C07B),
                              shape: BoxShape.circle,
                            ),
                          ),
                        // Modified indicator dot (blue)
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
                        GestureDetector(
                          onTap: () => context.read<IDECubit>().closeTab(index),
                          child: Icon(
                            Icons.close,
                            size: 12,
                            color: isActive
                                ? AppTheme.textSecondary
                                : AppTheme.textSecondary.withOpacity(0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Diff toggle button (only shown when diff is loaded)
          if (diffLoaded)
            Tooltip(
              message: _showDiffView ? 'Ver Editor' : 'Ver Diff Git',
              child: InkWell(
                onTap: () => setState(() => _showDiffView = !_showDiffView),
                borderRadius: BorderRadius.circular(4),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: _showDiffView
                        ? const Color(0xFF1A3E2A)
                        : (hasDiff ? const Color(0xFFE5C07B).withOpacity(0.15) : Colors.transparent),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: _showDiffView
                          ? const Color(0xFF4CAF50).withOpacity(0.5)
                          : (hasDiff
                              ? const Color(0xFFE5C07B).withOpacity(0.4)
                              : AppTheme.border),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.difference_outlined,
                        size: 13,
                        color: _showDiffView
                            ? const Color(0xFF4CAF50)
                            : (hasDiff ? const Color(0xFFE5C07B) : AppTheme.textSecondary),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'DIFF',
                        style: GoogleFonts.firaCode(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: _showDiffView
                              ? const Color(0xFF4CAF50)
                              : (hasDiff ? const Color(0xFFE5C07B) : AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          // Hide editor button
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
