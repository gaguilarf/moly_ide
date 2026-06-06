import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:moly_ide/core/di/injection.dart';
import 'package:moly_ide/core/ssh/ssh_service.dart';
import 'package:moly_ide/core/theme/app_theme.dart';

class FloatingDpadWidget extends StatefulWidget {
  final void Function(Offset delta)? onDragUpdate;

  const FloatingDpadWidget({super.key, this.onDragUpdate});

  @override
  State<FloatingDpadWidget> createState() => _FloatingDpadWidgetState();
}

class _FloatingDpadWidgetState extends State<FloatingDpadWidget> {
  final SSHService _sshService = locator<SSHService>();
  bool _showDpad = false;

  void _sendArrowKey(String direction) {
    final session = _sshService.activeTerminalSession;
    if (session == null) return;
    
    String sequence;
    switch (direction) {
      case 'up':
        sequence = '\x1b[A';
        break;
      case 'down':
        sequence = '\x1b[B';
        break;
      case 'left':
        sequence = '\x1b[D';
        break;
      case 'right':
        sequence = '\x1b[C';
        break;
      default:
        return;
    }
    session.write(utf8.encode(sequence));
  }

  @override
  Widget build(BuildContext context) {
    return _showDpad ? _buildArrowKeys() : _buildCollapsedButton();
  }

  Widget _buildArrowKeys() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFF0F0C1B).withOpacity(0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.primaryPurple.withOpacity(0.4),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Up arrow row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 28),
              _buildArrowButton(Icons.keyboard_arrow_up_rounded, 'up'),
              const SizedBox(width: 28),
            ],
          ),
          const SizedBox(height: 2),
          // Left / Right row with center close button
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildArrowButton(Icons.keyboard_arrow_left_rounded, 'left'),
              const SizedBox(width: 4),
              // Center collapse button (toggles panel into tiny floating icon)
              InkWell(
                onTap: () {
                  setState(() {
                    _showDpad = false;
                  });
                },
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue.withOpacity(0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.close_rounded,
                      size: 10,
                      color: AppTheme.accentBlue,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _buildArrowButton(Icons.keyboard_arrow_right_rounded, 'right'),
            ],
          ),
          const SizedBox(height: 2),
          // Down arrow row
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 28),
              _buildArrowButton(Icons.keyboard_arrow_down_rounded, 'down'),
              const SizedBox(width: 28),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildArrowButton(IconData icon, String direction) {
    return InkWell(
      onTap: () => _sendArrowKey(direction),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight.withOpacity(0.7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppTheme.border.withOpacity(0.25),
            width: 0.8,
          ),
        ),
        child: Icon(
          icon,
          size: 18,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildCollapsedButton() {
    return GestureDetector(
      onTap: () => setState(() => _showDpad = true),
      onPanUpdate: (details) => widget.onDragUpdate?.call(details.delta),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: const Color(0xFF0F0C1B).withOpacity(0.85),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppTheme.primaryPurple.withOpacity(0.5),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryPurple.withOpacity(0.2),
              blurRadius: 4,
            ),
          ],
        ),
        child: const Icon(
          Icons.open_with_rounded,
          size: 18,
          color: AppTheme.accentBlue,
        ),
      ),
    );
  }
}
