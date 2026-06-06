import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/features/ide_dashboard/presentation/cubit/ide_state.dart';

class GitDiffView extends StatelessWidget {
  final List<GitDiffLine> diffLines;

  const GitDiffView({super.key, required this.diffLines});

  @override
  Widget build(BuildContext context) {
    final added = diffLines.where((l) => l.type == GitDiffLineType.added).length;
    final removed = diffLines.where((l) => l.type == GitDiffLineType.removed).length;
    final hasChanges = added > 0 || removed > 0;

    if (!hasChanges) {
      return Container(
        color: const Color(0xFF0A0912),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.check_circle_outline, color: Color(0xFF4CAF50), size: 40),
              const SizedBox(height: 12),
              Text(
                'Sin cambios respecto al último commit',
                style: GoogleFonts.firaCode(color: Colors.white38, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: const Color(0xFF0A0912),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stats header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: const BoxDecoration(
              color: Color(0xFF0E0C1A),
              border: Border(bottom: BorderSide(color: Color(0xFF1E1B30), width: 1)),
            ),
            child: Row(
              children: [
                const Icon(Icons.difference_outlined, size: 14, color: Color(0xFF7C7A99)),
                const SizedBox(width: 8),
                Text(
                  'git diff HEAD',
                  style: GoogleFonts.firaCode(fontSize: 11, color: const Color(0xFF7C7A99)),
                ),
                const Spacer(),
                if (added > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D2818),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.4)),
                    ),
                    child: Text(
                      '+$added',
                      style: GoogleFonts.firaCode(
                        fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFF4CAF50),
                      ),
                    ),
                  ),
                if (added > 0 && removed > 0) const SizedBox(width: 6),
                if (removed > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2A0D0D),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFE57373).withOpacity(0.4)),
                    ),
                    child: Text(
                      '-$removed',
                      style: GoogleFonts.firaCode(
                        fontSize: 11, fontWeight: FontWeight.bold, color: const Color(0xFFE57373),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: diffLines.length,
              itemBuilder: (context, index) => _DiffLineRow(line: diffLines[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _DiffLineRow extends StatelessWidget {
  final GitDiffLine line;

  const _DiffLineRow({required this.line});

  @override
  Widget build(BuildContext context) {
    final (bgColor, lineNumColor, textColor, prefix) = switch (line.type) {
      GitDiffLineType.added => (
          const Color(0xFF0D2818),
          const Color(0xFF4CAF50),
          const Color(0xFFA8D8A0),
          '+',
        ),
      GitDiffLineType.removed => (
          const Color(0xFF2A0D0D),
          const Color(0xFFE57373),
          const Color(0xFFFFB0B0),
          '-',
        ),
      GitDiffLineType.context => (
          Colors.transparent,
          const Color(0xFF3A3560),
          const Color(0xFF6B6890),
          ' ',
        ),
    };

    return Container(
      color: bgColor,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Line number
            Container(
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 4),
              alignment: Alignment.centerRight,
              child: Text(
                line.lineNumber != null ? '${line.lineNumber}' : '',
                style: GoogleFonts.firaCode(fontSize: 11, color: lineNumColor),
              ),
            ),
            // +/- prefix
            Container(
              width: 18,
              alignment: Alignment.center,
              child: Text(
                prefix,
                style: GoogleFonts.firaCode(
                  fontSize: 13,
                  color: lineNumColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: Text(
                  line.content,
                  style: GoogleFonts.firaCode(fontSize: 13, color: textColor),
                  softWrap: false,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
