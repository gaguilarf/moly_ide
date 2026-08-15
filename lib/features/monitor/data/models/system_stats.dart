// Parsing of remote system stats gathered over SSH.
//
// The monitor runs a single combined command whose sections are separated
// by the marker '@@@' (see [SystemStats.command]):
//   /proc/stat, /proc/meminfo, /proc/loadavg, /proc/uptime, df, ps

class CpuSnapshot {
  final String id; // 'cpu' (aggregate) or 'cpu0', 'cpu1', ...
  final int idle;
  final int total;

  const CpuSnapshot({required this.id, required this.idle, required this.total});

  /// CPU usage (0.0 - 1.0) between two snapshots of the same core.
  double usageSince(CpuSnapshot previous) {
    final totalDelta = total - previous.total;
    final idleDelta = idle - previous.idle;
    if (totalDelta <= 0) return 0.0;
    return ((totalDelta - idleDelta) / totalDelta).clamp(0.0, 1.0);
  }
}

class ProcessEntry {
  final String pid;
  final String name;
  final double cpuPercent;
  final double memPercent;

  const ProcessEntry({
    required this.pid,
    required this.name,
    required this.cpuPercent,
    required this.memPercent,
  });
}

class SystemStats {
  /// Aggregate + per-core snapshots keyed by id ('cpu', 'cpu0', ...).
  final Map<String, CpuSnapshot> cpuSnapshots;

  final int memTotalKb;
  final int memAvailableKb;
  final int swapTotalKb;
  final int swapFreeKb;

  final int diskTotalKb;
  final int diskUsedKb;

  final double load1;
  final double load5;
  final double load15;

  final Duration uptime;

  final List<ProcessEntry> topProcesses;

  const SystemStats({
    required this.cpuSnapshots,
    required this.memTotalKb,
    required this.memAvailableKb,
    required this.swapTotalKb,
    required this.swapFreeKb,
    required this.diskTotalKb,
    required this.diskUsedKb,
    required this.load1,
    required this.load5,
    required this.load15,
    required this.uptime,
    required this.topProcesses,
  });

  int get memUsedKb => (memTotalKb - memAvailableKb).clamp(0, memTotalKb);
  int get swapUsedKb => (swapTotalKb - swapFreeKb).clamp(0, swapTotalKb);

  double get memUsageRatio =>
      memTotalKb > 0 ? (memUsedKb / memTotalKb).clamp(0.0, 1.0) : 0.0;
  double get swapUsageRatio =>
      swapTotalKb > 0 ? (swapUsedKb / swapTotalKb).clamp(0.0, 1.0) : 0.0;
  double get diskUsageRatio =>
      diskTotalKb > 0 ? (diskUsedKb / diskTotalKb).clamp(0.0, 1.0) : 0.0;

  static const String command =
      "cat /proc/stat; echo '@@@'; "
      "cat /proc/meminfo; echo '@@@'; "
      "cat /proc/loadavg; echo '@@@'; "
      "cat /proc/uptime; echo '@@@'; "
      "df -kP /; echo '@@@'; "
      "ps -eo pid,comm,pcpu,pmem --sort=-pcpu 2>/dev/null | head -n 7";

  static SystemStats parse(String output) {
    final sections = output.split('@@@');

    final cpuSnapshots = _parseCpu(_section(sections, 0));
    final meminfo = _parseMeminfo(_section(sections, 1));
    final load = _parseLoadAvg(_section(sections, 2));
    final uptime = _parseUptime(_section(sections, 3));
    final disk = _parseDf(_section(sections, 4));
    final processes = _parseProcesses(_section(sections, 5));

    return SystemStats(
      cpuSnapshots: cpuSnapshots,
      memTotalKb: meminfo['MemTotal'] ?? 0,
      memAvailableKb: meminfo['MemAvailable'] ?? meminfo['MemFree'] ?? 0,
      swapTotalKb: meminfo['SwapTotal'] ?? 0,
      swapFreeKb: meminfo['SwapFree'] ?? 0,
      diskTotalKb: disk[0],
      diskUsedKb: disk[1],
      load1: load[0],
      load5: load[1],
      load15: load[2],
      uptime: uptime,
      topProcesses: processes,
    );
  }

  static String _section(List<String> sections, int index) =>
      index < sections.length ? sections[index] : '';

  static Map<String, CpuSnapshot> _parseCpu(String text) {
    final result = <String, CpuSnapshot>{};
    for (final line in text.split('\n')) {
      final trimmed = line.trim();
      if (!trimmed.startsWith('cpu')) continue;
      final parts = trimmed.split(RegExp(r'\s+'));
      if (parts.length < 5) continue;
      final values = parts
          .skip(1)
          .map((v) => int.tryParse(v) ?? 0)
          .toList(growable: false);
      // idle = idle + iowait (columns 4 and 5 of /proc/stat)
      final idle = values[3] + (values.length > 4 ? values[4] : 0);
      final total = values.fold<int>(0, (a, b) => a + b);
      result[parts[0]] = CpuSnapshot(id: parts[0], idle: idle, total: total);
    }
    return result;
  }

  static Map<String, int> _parseMeminfo(String text) {
    final result = <String, int>{};
    for (final line in text.split('\n')) {
      final match = RegExp(r'^(\w+):\s+(\d+)').firstMatch(line.trim());
      if (match != null) {
        result[match.group(1)!] = int.parse(match.group(2)!);
      }
    }
    return result;
  }

  static List<double> _parseLoadAvg(String text) {
    final parts = text.trim().split(RegExp(r'\s+'));
    return [
      parts.isNotEmpty ? double.tryParse(parts[0]) ?? 0.0 : 0.0,
      parts.length > 1 ? double.tryParse(parts[1]) ?? 0.0 : 0.0,
      parts.length > 2 ? double.tryParse(parts[2]) ?? 0.0 : 0.0,
    ];
  }

  static Duration _parseUptime(String text) {
    final parts = text.trim().split(RegExp(r'\s+'));
    final seconds = parts.isNotEmpty ? double.tryParse(parts[0]) ?? 0.0 : 0.0;
    return Duration(seconds: seconds.round());
  }

  /// Returns [totalKb, usedKb] of the root filesystem.
  static List<int> _parseDf(String text) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    // Skip the header line; POSIX format: fs total used avail use% mount
    for (final line in lines.skip(1)) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length >= 4) {
        final total = int.tryParse(parts[1]);
        final used = int.tryParse(parts[2]);
        if (total != null && used != null) return [total, used];
      }
    }
    return [0, 0];
  }

  static List<ProcessEntry> _parseProcesses(String text) {
    final result = <ProcessEntry>[];
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    // Skip the 'PID COMMAND %CPU %MEM' header line
    for (final line in lines.skip(1)) {
      final parts = line.split(RegExp(r'\s+'));
      if (parts.length < 4) continue;
      final cpu = double.tryParse(parts[parts.length - 2]);
      final mem = double.tryParse(parts[parts.length - 1]);
      if (cpu == null || mem == null) continue;
      result.add(ProcessEntry(
        pid: parts[0],
        name: parts.sublist(1, parts.length - 2).join(' '),
        cpuPercent: cpu,
        memPercent: mem,
      ));
    }
    return result;
  }
}
