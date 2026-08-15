import 'package:flutter_test/flutter_test.dart';
import 'package:moly_ide/features/monitor/data/models/system_stats.dart';

const _sampleOutput = '''
cpu  10000 200 3000 80000 500 0 100 0 0 0
cpu0 5000 100 1500 40000 250 0 50 0 0 0
cpu1 5000 100 1500 40000 250 0 50 0 0 0
@@@
MemTotal:        4030428 kB
MemFree:          512000 kB
MemAvailable:    2015214 kB
Buffers:          100000 kB
Cached:           800000 kB
SwapTotal:       1048576 kB
SwapFree:         524288 kB
@@@
0.52 0.34 0.21 1/234 5678
@@@
93784.12 180000.00
@@@
Filesystem     1024-blocks     Used Available Capacity Mounted on
/dev/vda1         41152736 20576368  20576368      50% /
@@@
  PID COMMAND         %CPU %MEM
    1 systemd          0.1  0.3
  845 node            25.5 12.4
 1024 claude           7.2  8.1
''';

void main() {
  group('SystemStats.parse', () {
    final stats = SystemStats.parse(_sampleOutput);

    test('parses cpu snapshots (aggregate and per core)', () {
      expect(stats.cpuSnapshots.keys, containsAll(['cpu', 'cpu0', 'cpu1']));
      final cpu = stats.cpuSnapshots['cpu']!;
      expect(cpu.idle, 80500); // idle + iowait
      expect(cpu.total, 93800);
    });

    test('parses memory and swap', () {
      expect(stats.memTotalKb, 4030428);
      expect(stats.memAvailableKb, 2015214);
      expect(stats.memUsedKb, 2015214);
      expect(stats.memUsageRatio, closeTo(0.5, 0.001));
      expect(stats.swapTotalKb, 1048576);
      expect(stats.swapUsageRatio, closeTo(0.5, 0.001));
    });

    test('parses disk usage of root filesystem', () {
      expect(stats.diskTotalKb, 41152736);
      expect(stats.diskUsedKb, 20576368);
      expect(stats.diskUsageRatio, closeTo(0.5, 0.001));
    });

    test('parses load average and uptime', () {
      expect(stats.load1, 0.52);
      expect(stats.load5, 0.34);
      expect(stats.load15, 0.21);
      expect(stats.uptime.inSeconds, 93784);
    });

    test('parses top processes skipping the header', () {
      expect(stats.topProcesses.length, 3);
      expect(stats.topProcesses[1].name, 'node');
      expect(stats.topProcesses[1].cpuPercent, 25.5);
      expect(stats.topProcesses[1].memPercent, 12.4);
    });

    test('computes cpu usage between two snapshots', () {
      const before = CpuSnapshot(id: 'cpu', idle: 1000, total: 2000);
      const after = CpuSnapshot(id: 'cpu', idle: 1600, total: 3000);
      // total delta 1000, idle delta 600 -> 40% busy
      expect(after.usageSince(before), closeTo(0.4, 0.001));
      // No elapsed time -> 0
      expect(before.usageSince(before), 0.0);
    });

    test('handles missing sections gracefully', () {
      final empty = SystemStats.parse('');
      expect(empty.memTotalKb, 0);
      expect(empty.diskTotalKb, 0);
      expect(empty.topProcesses, isEmpty);
    });
  });
}
