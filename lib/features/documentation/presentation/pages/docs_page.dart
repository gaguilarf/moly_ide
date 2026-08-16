import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/auth/presentation/widgets/boton_cerrar_sesion.dart';
import 'package:moly_ide/features/documentation/data/models/doc_models.dart';
import 'package:moly_ide/features/documentation/presentation/cubit/docs_cubit.dart';
import 'package:moly_ide/features/documentation/presentation/cubit/docs_state.dart';
import 'package:moly_ide/features/updates/presentation/widgets/update_dialog.dart';

class DocsPage extends StatefulWidget {
  const DocsPage({super.key});

  @override
  State<DocsPage> createState() => _DocsPageState();
}

class _DocsPageState extends State<DocsPage> {
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    context.read<DocsCubit>().loadDocuments();
  }

  void _openDocumentViewer(BuildContext context, DocItemModel doc) {
    context.read<DocsCubit>().loadDocumentContent(doc.path);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bSheetCtx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.85,
          maxChildSize: 0.95,
          minChildSize: 0.5,
          expand: false,
          builder: (context, scrollController) {
            return BlocBuilder<DocsCubit, DocsState>(
              builder: (context, state) {
                return Column(
                  children: [
                    // Handle bar
                    Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppTheme.textSecondary.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 8.0,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              doc.title,
                              style: GoogleFonts.outfit(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              color: AppTheme.textSecondary,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: AppTheme.border, height: 1),
                    Expanded(
                      child: state.selectedDocContent == null
                          ? const Center(
                              child: CircularProgressIndicator(
                                color: AppTheme.accentBlue,
                              ),
                            )
                          : Markdown(
                              controller: scrollController,
                              data: state.selectedDocContent!,
                              styleSheet: MarkdownStyleSheet(
                                p: GoogleFonts.outfit(
                                  color: Colors.white70,
                                  fontSize: 14,
                                  height: 1.4,
                                ),
                                h1: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                                h2: GoogleFonts.outfit(
                                  color: AppTheme.accentBlue,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                                h3: GoogleFonts.outfit(
                                  color: AppTheme.primaryPurple,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                                code: GoogleFonts.firaCode(
                                  backgroundColor: AppTheme.surfaceLight,
                                  color: const Color(0xFF00FF66),
                                ),
                                codeblockDecoration: BoxDecoration(
                                  color: const Color(0xFF0D0D12),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.border),
                                ),
                              ),
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: Text(
          'Documentación Viva',
          style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.system_update_rounded,
              color: AppTheme.accentBlue,
            ),
            tooltip: 'Actualizar App',
            onPressed: () => UpdateDialog.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: AppTheme.accentBlue),
            tooltip: 'Recargar',
            onPressed: () => context.read<DocsCubit>().loadDocuments(),
          ),
          const BotonCerrarSesion(),
        ],
      ),
      body: BlocBuilder<DocsCubit, DocsState>(
        builder: (context, state) {
          if (state.status == DocsStatus.loading) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.accentBlue),
            );
          }

          final filteredDocs = state.documents.where((d) {
            final q = _searchQuery.toLowerCase();
            return d.title.toLowerCase().contains(q) ||
                d.category.toLowerCase().contains(q);
          }).toList();

          return Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Buscar documentos, guías y ADRs...',
                    hintStyle: GoogleFonts.outfit(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                    ),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: AppTheme.accentBlue,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: AppTheme.surface,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(
                        color: AppTheme.border.withOpacity(0.6),
                      ),
                    ),
                  ),
                  onChanged: (val) => setState(() => _searchQuery = val),
                ),
              ),

              // Docs List
              Expanded(
                child: filteredDocs.isEmpty
                    ? Center(
                        child: Text(
                          'No se encontraron documentos.',
                          style: GoogleFonts.outfit(
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: filteredDocs.length,
                        itemBuilder: (context, idx) {
                          final doc = filteredDocs[idx];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            color: AppTheme.surface,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: AppTheme.border.withOpacity(0.5),
                              ),
                            ),
                            child: ListTile(
                              leading: const Icon(
                                Icons.description_rounded,
                                color: AppTheme.primaryPurple,
                                size: 22,
                              ),
                              title: Text(
                                doc.title,
                                style: GoogleFonts.outfit(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                              subtitle: Text(
                                '${doc.category} • ${doc.path}',
                                style: GoogleFonts.firaCode(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary,
                                ),
                              ),
                              trailing: const Icon(
                                Icons.chevron_right_rounded,
                                color: AppTheme.textSecondary,
                                size: 20,
                              ),
                              onTap: () => _openDocumentViewer(context, doc),
                            ),
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
