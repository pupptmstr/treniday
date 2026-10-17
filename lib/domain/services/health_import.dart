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

  /// How far before a workout the store is read. A store returns the
  /// workouts that *start* in the range read (HealthKit's predicate is on the
  /// start date), so one that began before the file's first workout and was
  /// still going on would be missed without it — found on the iOS simulator:
  /// a workout at 11:20–11:24 was written beside one at 11:18–11:21. Elapsed
  /// time on purpose (an overlap window, not a calendar day).
  static const lookBack = Duration(hours: 12);

  /// The time to read from the health store to check [logs]: from [lookBack]
  /// before the first of them to the end of the last; null when none of them
  /// has a length. A workout starting [lookBack] after the range's start is
  /// fully checked (see [plan]'s `checkedFrom`).
  static TimeSpan? rangeOf(Iterable<WorkoutLog> logs) {
    DateTime? start, end;
    for (final s in logs.map(spanOf).nonNulls) {
      if (start == null || s.start.isBefore(start)) start = s.start;
      if (end == null || s.end.isAfter(end)) end = s.end;
    }
    return start == null
        ? null
        : (start: start.subtract(lookBack), end: end!);
  }

  /// [logs] split by what the health store holds: [HealthImportPlan.toWrite]
  /// overlap none of [inHealth]; those starting before [checkedFrom] — the
  /// start of what was read plus [lookBack] (less was read when the store
  /// would not show that far back, Health Connect on Android 13 and lower) —
  /// are [HealthImportPlan.unchecked] and left out.
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
