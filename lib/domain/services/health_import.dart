import '../../data/models/workout_log.dart';

/// A stretch of time: a workout in Apple Health / Health Connect, or one of
/// ours.
typedef TimeSpan = ({DateTime start, DateTime end});

/// Which workouts a progress file adds should go to Apple Health / Health
/// Connect after the merge (owner, 2026-10-17): not one that would overlap a
/// workout already there — of any app, ours from the other phone included —
/// so nothing is counted twice. Pure; `HealthService` does the reading and
/// writing.
abstract final class HealthImport {
  /// When [log] took place: its date is when it ended (`_finishWorkout`
  /// writes it at the end), its length goes back from there. Null for a log
  /// without a length (the debug screen's).
  static TimeSpan? spanOf(WorkoutLog log) => log.durationSec <= 0
      ? null
      : (
          start: log.date.subtract(Duration(seconds: log.durationSec)),
          end: log.date,
        );

  /// The time to read from the health store to check [logs]; null when none
  /// of them has a length.
  static TimeSpan? rangeOf(Iterable<WorkoutLog> logs) {
    DateTime? start, end;
    for (final s in logs.map(spanOf).nonNulls) {
      if (start == null || s.start.isBefore(start)) start = s.start;
      if (end == null || s.end.isAfter(end)) end = s.end;
    }
    return start == null ? null : (start: start, end: end!);
  }

  /// [logs] split by what the health store holds: [HealthImportPlan.toWrite]
  /// overlap none of [inHealth]; those starting before [checkedFrom] (the
  /// store would not show that far back, Health Connect on Android 13 and
  /// lower) are [HealthImportPlan.unchecked] and left out.
  static HealthImportPlan plan(
    Iterable<WorkoutLog> logs,
    Iterable<TimeSpan> inHealth, {
    required DateTime checkedFrom,
  }) {
    final toWrite = <WorkoutLog>[];
    var unchecked = 0;
    for (final log in logs) {
      final span = spanOf(log);
      if (span == null) continue;
      if (span.start.isBefore(checkedFrom)) {
        unchecked++;
      } else if (!inHealth.any((h) => overlap(span, h))) {
        toWrite.add(log);
      }
    }
    return HealthImportPlan(toWrite: toWrite, unchecked: unchecked);
  }

  /// Whether [a] and [b] share any time (touching ends do not count).
  static bool overlap(TimeSpan a, TimeSpan b) =>
      a.start.isBefore(b.end) && b.start.isBefore(a.end);
}

class HealthImportPlan {
  const HealthImportPlan({required this.toWrite, required this.unchecked});

  final List<WorkoutLog> toWrite;

  /// Workouts too old for the store to show: not written.
  final int unchecked;
}
