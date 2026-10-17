import 'dart:convert';
import 'dart:math';

import '../../core/utils/calendar_days.dart';
import '../../data/models/custom_routine.dart';
import '../../data/models/enums.dart';
import '../../data/models/exercise.dart';
import '../../data/models/skill_progress.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/workout_log.dart';
import '../../data/progress_file.dart';
import '../../data/static/achievement_catalog.dart';
import '../../data/static/release_notes_catalog.dart';
import '../models/branch.dart';
import '../models/progress_snapshot.dart';
import 'achievement_service.dart';
import 'sp_service.dart';
import 'streak_service.dart';

/// A branch that reached a further stage through the merge.
class StageUp {
  const StageUp(this.branchKey, this.stage);

  /// `Branch.key`: a built-in branch's name or `custom_<id>`.
  final String branchKey;
  final int stage;
}

/// What adding a progress file changes, for the confirmation before it.
class ProgressMergeSummary {
  const ProgressMergeSummary({
    required this.addedWorkouts,
    required this.addedSp,
    required this.rankFrom,
    required this.rankTo,
    required this.streakFrom,
    required this.streakTo,
    required this.bestStreakFrom,
    required this.bestStreakTo,
    required this.newAchievementIds,
    required this.stageUps,
    required this.branchesMovedOn,
    required this.addedOwn,
    this.firstsChosenAgain = false,
  });

  final int addedWorkouts;
  final int addedSp;
  final Rank rankFrom;
  final Rank rankTo;

  /// The streak as Home shows it, before and after.
  final int streakFrom;
  final int streakTo;
  final int bestStreakFrom;
  final int bestStreakTo;

  /// Achievements earned on the other device or by the combined totals,
  /// only those this version shows.
  final List<String> newAchievementIds;

  final List<StageUp> stageUps;

  /// Branches further along within their stage (no new stage).
  final int branchesMovedOn;

  /// Own routines, branches and courses that are new here.
  final int addedOwn;

  /// A workout already here became the first one of its day, or stopped
  /// being it (the two devices had chosen differently).
  final bool firstsChosenAgain;
}

class ProgressMergeResult {
  const ProgressMergeResult({
    required this.merged,
    required this.summary,
    required this.changesAnything,
    required this.addedLogs,
  });

  final ProgressSnapshot merged;
  final ProgressMergeSummary summary;

  /// The workouts the file brought: what may go to Apple Health / Health
  /// Connect after the merge (`HealthImport`).
  final List<WorkoutLog> addedLogs;

  /// False when everything in the file is already here: nothing to write.
  final bool changesAnything;
}

/// Joins the progress of a file into this device's (owner, 2026-10-13:
/// "exactly a merge", never a replacement), so someone who trained on the
/// web and on a phone ends up with both. Pure; merging the same file twice
/// changes nothing the second time.
///
/// - Workouts: the union. A workout is known by the local time it ended (to
///   the millisecond), its course and its length.
/// - One first workout a day (owner, 2026-10-17): when both devices had one
///   on the same day, the one with more SP keeps them; the other becomes a
///   repeat workout and earns what a repeat one would ([bonusSpOf]). On a tie
///   the earlier one stays first, so every device decides the same. A
///   workout that is the first one on either side takes part, so two devices
///   that once chose differently agree after the next exchange of files.
/// - SP: this device's plus what the merge adds to the log; the rank follows.
/// - Streak and freezes: the merged training days replayed through
///   [StreakService], never below what a device knew about its last day.
/// - Skill progress: per branch the one further along ([compareProgress]).
/// - Achievements: the union with the earliest date, then what the combined
///   totals reach ([AchievementService.checkAfterMerge]).
/// - Own routines, branches, courses: the union by id; on the same id this
///   device's copy stays.
/// - Settings stay this device's; the name comes from the file only when
///   there is none here; the active built-in courses are the union.
abstract final class ProgressMerge {
  static ProgressMergeResult merge(
    ProgressSnapshot local,
    ProgressSnapshot imported, {
    required DateTime now,
  }) {
    // Copies: the inputs stay as they are.
    final mine = ProgressFile.copy(local);
    final theirs = ProgressFile.copy(imported);

    // ── Workouts ──────────────────────────────────────────────────────────
    final logs = [...mine.logs];
    final known = {for (final l in logs) logKey(l)};
    final added = [
      for (final l in theirs.logs)
        if (known.add(logKey(l))) l,
    ];
    logs.addAll(added);
    // The first workouts of the file, by key: a workout this device keeps as
    // a repeat one may be the first one there (each device chose before it
    // knew the other's).
    final theirFirsts = {
      for (final l in theirs.logs)
        if (l.isPrimary) logKey(l): l,
    };
    final firstsChanged = _keepOneFirstWorkoutADay(logs, {
      for (final l in added)
        if (l.isPrimary) _day(l.date),
      for (final l in mine.logs)
        if (!l.isPrimary && theirFirsts.containsKey(logKey(l))) _day(l.date),
    }, theirFirsts);

    // ── Streak ────────────────────────────────────────────────────────────
    final p = mine.profile;
    if (added.isNotEmpty || firstsChanged) {
      _replayStreak(logs, p, local.profile, imported.profile);
    }
    p.longestStreak = [
      p.longestStreak,
      local.profile.longestStreak,
      imported.profile.longestStreak,
      p.currentStreak,
    ].reduce(max);

    // ── SP and rank ───────────────────────────────────────────────────────
    int spOf(Iterable<WorkoutLog> ls) => ls.fold(0, (s, l) => s + l.spEarned);
    p.totalSP = local.profile.totalSP + spOf(logs) - spOf(local.logs);
    p.rank = RankExtension.fromSP(p.totalSP);

    // ── Skill progress ────────────────────────────────────────────────────
    final progress = mine.progress;
    final stageUps = <StageUp>[];
    var movedOn = 0;
    for (final e in theirs.progress.entries) {
      final here = progress[e.key];
      final there = e.value;
      if (here == null) {
        progress[e.key] = there;
        if (there.currentStage > 1) {
          stageUps.add(StageUp(e.key, there.currentStage));
        } else if (there.lastProgressedOn != null) {
          movedOn++;
        }
        continue;
      }
      final later = _later(here.lastProgressedOn, there.lastProgressedOn);
      if (compareProgress(there, here) > 0) {
        progress[e.key] = there..lastProgressedOn = later;
        if (there.currentStage > here.currentStage) {
          stageUps.add(StageUp(e.key, there.currentStage));
        } else {
          movedOn++;
        }
      } else {
        here.lastProgressedOn = later;
      }
    }

    // ── Own routines, branches, courses ───────────────────────────────────
    final routines = {for (final r in mine.routines) r.id: r};
    final branches = {for (final b in mine.branches) b.id: b};
    final courses = {for (final c in mine.courses) c.id: c};
    var addedOwn = 0;
    for (final r in theirs.routines) {
      final CustomRoutine? here = routines[r.id];
      if (here == null) {
        routines[r.id] = r;
        addedOwn++;
      } else {
        here.lastRunAt = _later(here.lastRunAt, r.lastRunAt);
      }
    }
    for (final b in theirs.branches) {
      if (branches.putIfAbsent(b.id, () => b) == b) addedOwn++;
    }
    for (final c in theirs.courses) {
      if (courses.putIfAbsent(c.id, () => c) == c) addedOwn++;
    }

    // ── Profile ───────────────────────────────────────────────────────────
    if ((p.displayName ?? '').trim().isEmpty &&
        (theirs.profile.displayName ?? '').trim().isNotEmpty) {
      p.displayName = theirs.profile.displayName;
    }
    final enrolled = p.activeCourseIds ?? const [0];
    final more = [
      for (final c in theirs.profile.activeCourseIds ?? const [0])
        if (!enrolled.contains(c)) c,
    ];
    if (more.isNotEmpty) p.activeCourseIds = [...enrolled, ...more];
    final seen = theirs.profile.lastSeenReleaseVersion;
    final seenHere = p.lastSeenReleaseVersion;
    if (seen != null &&
        (seenHere == null ||
            ReleaseNotesCatalog.compareVersions(seen, seenHere) > 0)) {
      p.lastSeenReleaseVersion = seen;
    }

    // ── Achievements ──────────────────────────────────────────────────────
    final achievements = mine.achievements;
    for (final e in theirs.achievements.entries) {
      final here = achievements[e.key];
      if (here == null || e.value.isBefore(here)) achievements[e.key] = e.value;
    }
    final reached = const AchievementService().checkAfterMerge(
      profile: p,
      totalWorkouts: logs.length,
      allProgress: {
        for (final v in progress.values) ?v.branchId: v,
      },
      alreadyEarned: achievements.keys.toSet(),
    );
    for (final id in reached) {
      achievements[id] = now;
    }

    final merged = ProgressSnapshot(
      profile: p,
      progress: progress,
      logs: logs,
      achievements: achievements,
      routines: [...routines.values],
      branches: [...branches.values],
      courses: [...courses.values],
    );
    return ProgressMergeResult(
      merged: merged,
      addedLogs: added,
      changesAnything: _text(merged) != _text(local),
      summary: ProgressMergeSummary(
        addedWorkouts: added.length,
        addedSp: p.totalSP - local.profile.totalSP,
        rankFrom: local.profile.rank,
        rankTo: p.rank,
        streakFrom: displayStreakOf(local.profile, now),
        streakTo: displayStreakOf(p, now),
        bestStreakFrom: local.profile.longestStreak,
        bestStreakTo: p.longestStreak,
        newAchievementIds: [
          for (final id in achievements.keys)
            if (!local.achievements.containsKey(id) &&
                AchievementCatalog.byId(id) != null)
              id,
        ],
        stageUps: stageUps,
        branchesMovedOn: movedOn,
        addedOwn: addedOwn,
        // This device's workouts come first in [logs], in the same order.
        firstsChosenAgain: Iterable.generate(local.logs.length)
            .any((i) => logs[i].isPrimary != local.logs[i].isPrimary),
      ),
    );
  }

  /// What tells one workout from another across devices: the local time it
  /// ended to the millisecond, its course and its length.
  static String logKey(WorkoutLog l) =>
      '${ProgressFile.dateToJson(l.date)}|${l.courseIdIndex}|${l.durationSec}';

  /// > 0 when [a] is further along than [b]: the stage, then the step within
  /// it in the order [ProgressionService] takes them — reps grow, then a set
  /// is added (reps start again), then the rest shrinks, then the challenge
  /// opens. So: challenge open, less rest, more sets, more reps.
  static int compareProgress(SkillProgress a, SkillProgress b) {
    int by(int x, int y) => x.compareTo(y);
    final steps = [
      by(a.currentStage, b.currentStage),
      by(a.isChallengeUnlocked ? 1 : 0, b.isChallengeUnlocked ? 1 : 0),
      by(b.currentRestSec, a.currentRestSec),
      by(a.currentSets, b.currentSets),
      by(a.currentReps, b.currentReps),
    ];
    return steps.firstWhere((c) => c != 0, orElse: () => 0);
  }

  /// The SP [log], a first workout of the day, would have earned as a repeat
  /// one: no ×1.5 for the first of the day, then half (as `_finishWorkout`
  /// gives a repeat workout). Counted again from its exercises when they
  /// still give exactly its SP as a first workout; otherwise (an exercise this
  /// version does not know, an own stage made of a warm-up) a third of it,
  /// which is the same up to rounding.
  static int bonusSpOf(WorkoutLog log) {
    final exercises = <Exercise>[];
    for (final r in log.exercises) {
      final e = OwnBranch.exerciseById(r.exerciseId);
      if (e == null) return (log.spEarned / 3).round();
      exercises.add(e);
    }
    const sp = SPService();
    final first = sp.forWorkout(
        results: log.exercises, exercises: exercises, isFirstToday: true);
    if (first != log.spEarned) return (log.spEarned / 3).round();
    return (sp.forWorkout(
                results: log.exercises,
                exercises: exercises,
                isFirstToday: false) *
            0.5)
        .round();
  }

  /// On each of [days] keeps one first workout and makes the others repeat
  /// ones; returns whether any workout changed between the two.
  ///
  /// The candidates are the first workouts of the day here and those that are
  /// the first ones in the file ([theirFirsts], by [logKey]; a workout kept
  /// here as a repeat one comes back with its full SP). The winner: the most
  /// SP, on a tie the earlier one, then the smaller [logKey] — never "this
  /// device's", or two devices merging each other's files would keep
  /// different ones.
  static bool _keepOneFirstWorkoutADay(List<WorkoutLog> logs,
      Set<DateTime> days, Map<String, WorkoutLog> theirFirsts) {
    bool before(WorkoutLog a, WorkoutLog b) {
      if (a.spEarned != b.spEarned) return a.spEarned > b.spEarned;
      final byTime = a.date.compareTo(b.date);
      if (byTime != 0) return byTime < 0;
      return logKey(a).compareTo(logKey(b)) < 0;
    }

    var changed = false;
    for (final day in days) {
      // Index → the workout as a first one.
      final firsts = <int, WorkoutLog>{
        for (var i = 0; i < logs.length; i++)
          if (_day(logs[i].date) == day)
            i: ?(logs[i].isPrimary ? logs[i] : theirFirsts[logKey(logs[i])]),
      };
      if (firsts.isEmpty) continue;
      var keep = firsts.keys.first;
      for (final i in firsts.keys) {
        if (before(firsts[i]!, firsts[keep]!)) keep = i;
      }
      for (final MapEntry(key: i, value: first) in firsts.entries) {
        final next = i == keep
            ? first
            : _copyLog(first,
                isPrimary: false,
                spEarned: bonusSpOf(first),
                freezeUsed: false,
                freezeEarned: false);
        if (next.isPrimary != logs[i].isPrimary ||
            next.spEarned != logs[i].spEarned) {
          changed = true;
        }
        logs[i] = next;
      }
    }
    return changed;
  }

  /// Replays the training days of [logs] into [p] (streak, freezes, the last
  /// day, the longest streak) and marks on each day's counting workout the
  /// freeze used or earned, as `_finishWorkout` would have.
  ///
  /// A day counts as `_finishWorkout` counts it: its first workout did real
  /// work (SP, or a set of a real exercise). If a device's profile knows a
  /// later day than its log, or a longer streak on the same last day (a log
  /// from before a field was kept), that device's streak stands.
  static void _replayStreak(List<WorkoutLog> logs, UserProfile p,
      UserProfile local, UserProfile imported) {
    final counting = <DateTime, int>{};
    for (var i = 0; i < logs.length; i++) {
      final l = logs[i];
      if (!l.isPrimary || !_didRealWork(l)) continue;
      final day = _day(l.date);
      final j = counting[day];
      if (j == null || l.date.isBefore(logs[j].date)) counting[day] = i;
    }
    final replay = UserProfile();
    const streaks = StreakService();
    final flags = <int, (bool, bool)>{};
    for (final day in counting.keys.toList()..sort()) {
      final used = streaks.applyWorkout(replay, day);
      final earned = streaks.tryAwardFreeze(replay);
      flags[counting[day]!] = (used, earned);
    }
    for (var i = 0; i < logs.length; i++) {
      final (used, earned) = flags[i] ?? (false, false);
      if (logs[i].freezeUsed != used || logs[i].freezeEarned != earned) {
        logs[i] = _copyLog(logs[i], freezeUsed: used, freezeEarned: earned);
      }
    }

    p
      ..currentStreak = replay.currentStreak
      ..streakFreezeCount = replay.streakFreezeCount
      ..lastWorkoutDate = replay.lastWorkoutDate
      ..longestStreak = replay.longestStreak;
    for (final side in [local, imported]) {
      final last = side.lastWorkoutDate;
      if (last == null) continue;
      final ahead =
          p.lastWorkoutDate == null ? 1 : calendarDaysBetween(p.lastWorkoutDate!, last);
      if (ahead > 0 || (ahead == 0 && side.currentStreak > p.currentStreak)) {
        p
          ..currentStreak = side.currentStreak
          ..streakFreezeCount = side.streakFreezeCount
          ..lastWorkoutDate = _day(last);
      }
    }
  }

  /// What `_finishWorkout` asks before a workout counts for the streak.
  static bool _didRealWork(WorkoutLog l) =>
      l.spEarned > 0 ||
      l.exercises.any((r) {
        final e = OwnBranch.exerciseById(r.exerciseId);
        return e != null &&
            e.stage > 0 &&
            (r.completedReps > 0 || (r.actualDurationSec ?? 0) > 0);
      });

  static WorkoutLog _copyLog(
    WorkoutLog l, {
    bool? isPrimary,
    int? spEarned,
    bool? freezeUsed,
    bool? freezeEarned,
  }) =>
      WorkoutLog(
        date: l.date,
        setType: l.setType,
        exercises: l.exercises,
        spEarned: spEarned ?? l.spEarned,
        durationSec: l.durationSec,
        isPrimary: isPrimary ?? l.isPrimary,
        courseIdIndex: l.courseIdIndex,
        freezeUsed: freezeUsed ?? l.freezeUsed,
        freezeEarned: freezeEarned ?? l.freezeEarned,
        estimatedDurationSec: l.estimatedDurationSec,
        growth: l.growth,
      );

  static DateTime? _later(DateTime? a, DateTime? b) =>
      a == null ? b : (b == null || !b.isAfter(a) ? a : b);

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  static String _text(ProgressSnapshot s) => jsonEncode(
      ProgressFile.toJson(s, appVersion: '', exportedAt: DateTime(2000)));
}
