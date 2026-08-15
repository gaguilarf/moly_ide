import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:moly_ide/core/di/injection.dart';
import 'package:moly_ide/core/ssh/ssh_service.dart';
import 'package:moly_ide/core/theme/app_theme.dart';
import 'package:moly_ide/features/monitor/data/models/system_stats.dart';

/// Full-screen monitor of the remote VPS resources (CPU, RAM, swap, disk).
/// Polls the server over SSH every [_refreshInterval] and computes CPU usage
/// from the delta between consecutive /proc/stat snapshots.
class ResourceMonitorPage extends StatefulWidget {
  const ResourceMonitorPage({super.key});

  @override
  State<ResourceMonitorPage> createState() => _ResourceMonitorPageState();
}

class _ResourceMonitorPageState extends State<ResourceMonitorPage> {
  static const Duration _refreshInterval = Duration(seconds: 3);

  final SSHService _sshService = locator<SSHService>();

  Timer? _timer;
  bool _fetching = false;

  SystemStats? _stats;
  Map<String, CpuSnapshot>? _previousCpu;
  double? _cpuUsage;
  Map<String, double> _coreUsage = {};
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _fetchStats();
    _timer = Timer.periodic(_refreshInterval, (_) => _fetchStats());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchStats() async {
    if (_fetching) return;
    _fetching = true;
    try {
      final output = await _sshService.executeCommand(SystemStats.command);
      final stats = SystemStats.parse(output);

      double? cpuUsage;
      final coreUsage = <String, double>{};
      final previous = _previousCpu;
      if (previous != null) {
        for (final entry in stats.cpuSnapshots.entries) {
          final prev = previous[entry.key];
          if (prev == null) continue;
          final usage = entry.value.usageSince(prev);
          if (entry.key == 'cpu') {
            cpuUsage = usage;
          } else {
            coreUsage[entry.key] = usage;
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _stats = stats;
        _previousCpu = stats.cpuSnapshots;
        _cpuUsage = cpuUsage;
        _coreUsage = coreUsage;
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'No se pudo obtener métricas: $e';
      });
    } finally {
      _fetching = false;
    }
  }

  // Color by severity of usage
  static Color _usageColor(double ratio) {
    if (ratio < 0.60) return AppTheme.accentBlue;
    if (ratio < 0.85) return const Color(0xFFFFB74D);
    return const Color(0xFFFF5252);
  }

  static String _formatKb(int kb) {
    final mb = kb / 1024.0;
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  static String _formatUptime(Duration uptime) {
    final days = uptime.inDays;
    final hours = uptime.inHours % 24;
    final minutes = uptime.inMinutes % 60;
    if (days > 0) return '${days}d ${hours}h ${minutes}m';
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(
          bottom: BorderSide(color: AppTheme.border, width: 1.2),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: AppTheme.textPrimary),
            tooltip: 'Volver',
            onPressed: () => Navigator.pop(context),
          ),
          const Icon(Icons.monitor_heart_rounded,
              color: AppTheme.accentBlue, size: 22),
          const SizedBox(width: 8),
          Text(
            'Recursos del VPS',
            style: GoogleFonts.outfit(
              fontWeight: FontWeight.bold,
              fontSize: 17,
              foreground: Paint()
                ..shader = AppTheme.purpleBlueGradient.createShader(
                  const Rect.fromLTWH(0.0, 0.0, 160.0, 30.0),
                ),
            ),
          ),
          const Spacer(),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
            decoration: BoxDecoration(
              color: AppTheme.surfaceLight,
              borderRadius: AppTheme.borderRadius,
              border: Border.all(color: AppTheme.border, width: 1.0),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF00FF66),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _sshService.host ?? '',
                  style: GoogleFonts.firaCode(
                    fontSize: 11,
                    color: AppTheme.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final stats = _stats;

    if (stats == null && _errorMessage == null) {
      return const Center(
        child: CircularProgressIndicator(color: AppTheme.accentBlue),
      );
    }

    return ListView(
      padding: const EdgeInsets.all(12.0),
      children: [
        if (_errorMessage != null) _buildErrorBanner(),
        if (stats != null) ...[
          _buildCpuCard(stats),
          const SizedBox(height: 12),
          _buildUsageCard(
            title: 'Memoria RAM',
            icon: Icons.memory_rounded,
            usedLabel: _formatKb(stats.memUsedKb),
            totalLabel: _formatKb(stats.memTotalKb),
            freeLabel: '${_formatKb(stats.memAvailableKb)} disponibles',
            ratio: stats.memUsageRatio,
          ),
          if (stats.swapTotalKb > 0) ...[
            const SizedBox(height: 12),
            _buildUsageCard(
              title: 'Swap',
              icon: Icons.swap_horiz_rounded,
              usedLabel: _formatKb(stats.swapUsedKb),
              totalLabel: _formatKb(stats.swapTotalKb),
              freeLabel: '${_formatKb(stats.swapFreeKb)} libres',
              ratio: stats.swapUsageRatio,
            ),
          ],
          const SizedBox(height: 12),
          _buildUsageCard(
            title: 'Disco (/)',
            icon: Icons.storage_rounded,
            usedLabel: _formatKb(stats.diskUsedKb),
            totalLabel: _formatKb(stats.diskTotalKb),
            freeLabel:
                '${_formatKb(stats.diskTotalKb - stats.diskUsedKb)} libres',
            ratio: stats.diskUsageRatio,
          ),
          const SizedBox(height: 12),
          _buildInfoCard(stats),
          if (stats.topProcesses.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildProcessesCard(stats),
          ],
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: const Color(0xFFFF5252).withOpacity(0.12),
        borderRadius: AppTheme.borderRadius,
        border: Border.all(color: const Color(0xFFFF5252), width: 1.0),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded,
              color: Color(0xFFFF5252), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _errorMessage!,
              style: GoogleFonts.outfit(
                  fontSize: 12, color: AppTheme.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: AppTheme.borderRadius,
        border: Border.all(color: AppTheme.border, width: 1.0),
      ),
      child: child,
    );
  }

  Widget _cardTitle(IconData icon, String title, {Widget? trailing}) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.accentBlue, size: 18),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.outfit(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const Spacer(),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _progressBar(double ratio, {double height = 10}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height / 2),
      child: LinearProgressIndicator(
        value: ratio,
        minHeight: height,
        backgroundColor: AppTheme.surfaceLight,
        valueColor: AlwaysStoppedAnimation<Color>(_usageColor(ratio)),
      ),
    );
  }

  Widget _buildCpuCard(SystemStats stats) {
    final usage = _cpuUsage;
    final cores = _coreUsage.entries.toList()
      ..sort((a, b) {
        final an = int.tryParse(a.key.substring(3)) ?? 0;
        final bn = int.tryParse(b.key.substring(3)) ?? 0;
        return an.compareTo(bn);
      });

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(
            Icons.speed_rounded,
            'CPU',
            trailing: Text(
              usage != null ? '${(usage * 100).toStringAsFixed(1)}%' : '...',
              style: GoogleFonts.firaCode(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: usage != null
                    ? _usageColor(usage)
                    : AppTheme.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 12),
          _progressBar(usage ?? 0.0),
          if (cores.isNotEmpty) ...[
            const SizedBox(height: 16),
            ...cores.map((core) => Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 52,
                        child: Text(
                          'Core ${core.key.substring(3)}',
                          style: GoogleFonts.firaCode(
                            fontSize: 10,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      Expanded(child: _progressBar(core.value, height: 6)),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '${(core.value * 100).toStringAsFixed(0)}%',
                          textAlign: TextAlign.right,
                          style: GoogleFonts.firaCode(
                            fontSize: 10,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildUsageCard({
    required String title,
    required IconData icon,
    required String usedLabel,
    required String totalLabel,
    required String freeLabel,
    required double ratio,
  }) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(
            icon,
            title,
            trailing: Text(
              '${(ratio * 100).toStringAsFixed(1)}%',
              style: GoogleFonts.firaCode(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: _usageColor(ratio),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _progressBar(ratio),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '$usedLabel / $totalLabel',
                style: GoogleFonts.firaCode(
                  fontSize: 11,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              Text(
                freeLabel,
                style: GoogleFonts.firaCode(
                  fontSize: 11,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(SystemStats stats) {
    Widget item(String label, String value) {
      return Expanded(
        child: Column(
          children: [
            Text(
              value,
              style: GoogleFonts.firaCode(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                fontSize: 10,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      );
    }

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.info_outline_rounded, 'Sistema'),
          const SizedBox(height: 14),
          Row(
            children: [
              item('Load 1m', stats.load1.toStringAsFixed(2)),
              item('Load 5m', stats.load5.toStringAsFixed(2)),
              item('Load 15m', stats.load15.toStringAsFixed(2)),
              item('Uptime', _formatUptime(stats.uptime)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildProcessesCard(SystemStats stats) {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(Icons.list_alt_rounded, 'Procesos (top CPU)'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text('PROCESO',
                    style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary)),
              ),
              SizedBox(
                width: 60,
                child: Text('CPU %',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary)),
              ),
              SizedBox(
                width: 60,
                child: Text('RAM %',
                    textAlign: TextAlign.right,
                    style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.textSecondary)),
              ),
            ],
          ),
          const Divider(height: 16),
          ...stats.topProcesses.map((proc) => Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        proc.name,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.firaCode(
                          fontSize: 11,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        proc.cpuPercent.toStringAsFixed(1),
                        textAlign: TextAlign.right,
                        style: GoogleFonts.firaCode(
                          fontSize: 11,
                          color: _usageColor(proc.cpuPercent / 100),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 60,
                      child: Text(
                        proc.memPercent.toStringAsFixed(1),
                        textAlign: TextAlign.right,
                        style: GoogleFonts.firaCode(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
