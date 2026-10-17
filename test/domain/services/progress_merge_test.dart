import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:treniday/data/models/custom_branch.dart';
import 'package:treniday/data/models/custom_course.dart';
import 'package:treniday/data/models/custom_routine.dart';
import 'package:treniday/data/models/enums.dart';
import 'package:treniday/data/models/exercise_result.dart';
import 'package:treniday/data/models/skill_progress.dart';
import 'package:treniday/data/models/user_profile.dart';
import 'package:treniday/data/models/workout_log.dart';
import 'package:treniday/data/progress_file.dart';
import 'package:treniday/data/static/exercise_catalog.dart';
import 'package:treniday/domain/models/progress_snapshot.dart';
import 'package:treniday/domain/services/progress_merge.dart';
import 'package:treniday/domain/services/sp_service.dart';
import 'package:treniday/domain/services/streak_service.dart';

final _now = DateTime(2026, 10, 17, 12);

/// Day [n] of September 2026, at [hour].
DateTime day(int n, {int hour = 9, int minute = 0}) =>
    DateTime(2026, 9, n, hour, minute);

WorkoutLog workout(DateTime date,
        {int sp = 100,
        bool primary = true,
        int? course = 0,
        int duration = 600,
        List<ExerciseResult> exercises = const []}) =>
    WorkoutLog(
      date: date,
      setType: SetType.daily,
      exercises: exercises,
      spEarned: sp,
      durationSec: duration,
      isPrimary: primary,
      courseIdIndex: course,
    );

/// A device that did [logs] the way the app keeps them: SP, rank, the streak
/// and the freezes counted workout by workout, the freeze flags on the logs.
ProgressSnapshot device(
  List<WorkoutLog> logs, {
  UserProfile? profile,
  Map<String, SkillProgress> progress = const {},
  Map<String, DateTime> achievements = const {},
  List<CustomRoutine> routines = const [],
  List<CustomBranch> branches = const [],
  List<CustomCourse> courses = const [],
}) {
  final p = profile ?? UserProfile();
  const streaks = StreakService();
  final kept = <WorkoutLog>[];
  for (final l in [...logs]..sort((a, b) => a.date.compareTo(b.date))) {
    var used = false, earned = false;
    if (l.isPrimary && l.spEarned > 0) {
      used = streaks.applyWorkout(p, l.date);
      earned = streaks.tryAwardFreeze(p);
    }
    p.totalSP += l.spEarned;
    p.rank = RankExtension.fromSP(p.totalSP);
    kept.add(WorkoutLog(
      date: l.date,
      setType: l.setType,
      exercises: l.exercises,
      spEarned: l.spEarned,
      durationSec: l.durationSec,
      isPrimary: l.isPrimary,
      courseIdIndex: l.courseIdIndex,
      freezeUsed: used,
      freezeEarned: earned,
    ));
  }
  return ProgressSnapshot(
    profile: p,
    progress: {...progress},
    logs: kept,
    achievements: {...achievements},
    routines: [...routines],
    branches: [...branches],
    courses: [...courses],
  );
}

ProgressMergeResult merge(ProgressSnapshot local, ProgressSnapshot imported) =>
    ProgressMerge.merge(local, imported, now: _now);

WorkoutLog logAt(ProgressSnapshot s, DateTime date) =>
    s.logs.singleWhere((l) => l.date == date);

/// What two devices must agree on after both merged: everything but the
/// order of things and each device's own settings.
Map<String, Object?> essence(ProgressSnapshot s) {
  final j = ProgressFile.toJson(s, appVersion: '', exportedAt: DateTime(2000));
  List<String> sorted(String key) =>
      [...(j[key] as List).map(jsonEncode)]..sort();
  final p = j['profile'] as Map<String, Object?>;
  return {
    'workouts': sorted('workouts'),
    'skillProgress': sorted('skillProgress'),
    'routines': sorted('routines'),
    'branches': sorted('branches'),
    'courses': sorted('courses'),
    'achievements': (j['achievements'] as Map).entries
        .map((e) => '${e.key}=${e.value}')
        .toList()
      ..sort(),
    for (final k in [
      'totalSP',
      'rank',
      'currentStreak',
      'longestStreak',
      'streakFreezeCount',
      'lastWorkoutDate',
    ])
      k: p[k],
  };
}

void main() {
  test('a device with nothing yet gets everything in the file', () {
    final phone = device([]);
    final web = device([workout(day(1)), workout(day(2)), workout(day(3))]);
    final r = merge(phone, web);
    final m = r.merged;
    expect(m.logs, hasLength(3));
    expect(m.profile.totalSP, 300);
    expect(m.profile.currentStreak, 3);
    expect(m.profile.lastWorkoutDate, DateTime(2026, 9, 3));
    // The file had none of its achievements stored: the totals give them.
    expect(m.achievements.keys, containsAll(['first_workout', 'streak_3']));
    expect(m.achievements['first_workout'], _now);
    expect(r.changesAnything, isTrue);
    expect(r.summary.addedWorkouts, 3);
    expect(r.summary.addedSp, 300);
    expect(r.addedLogs.map((l) => l.date), [day(1), day(2), day(3)]);
  });

  test('a file added twice changes nothing the second time', () {
    final phone = device([workout(day(1)), workout(day(2))],
        achievements: {'first_workout': day(1)});
    final web = device([workout(day(2, hour: 18)), workout(day(3), sp: 70)]);
    final once = merge(phone, web).merged;
    final twice = merge(once, web);
    expect(twice.changesAnything, isFalse);
    expect(essence(twice.merged), essence(once));
    // The merged device's own file adds nothing to it either.
    expect(merge(once, once).changesAnything, isFalse);
  });

  test("a device's own file adds nothing", () {
    final phone = device([workout(day(1)), workout(day(2), sp: 50)],
        achievements: {'first_workout': day(1)},
        progress: {
          'push': SkillProgress(branchId: BranchId.push, currentStage: 2),
        });
    final r = merge(phone, phone);
    expect(r.changesAnything, isFalse);
    expect(r.summary.addedWorkouts, 0);
    expect(r.summary.addedSp, 0);
  });

  test('both devices end up the same: A into B, then B into A', () {
    final a = device([
      workout(day(1)),
      workout(day(2), sp: 100),
    ], achievements: {
      'first_workout': day(1)
    }, progress: {
      'push': SkillProgress(branchId: BranchId.push, currentStage: 3),
    });
    final b = device([
      workout(day(2, hour: 19), sp: 60),
      workout(day(3), sp: 80),
      workout(day(3, hour: 20), sp: 30, primary: false),
    ], progress: {
      'push': SkillProgress(branchId: BranchId.push, currentStage: 2),
      'core': SkillProgress(branchId: BranchId.core, currentStage: 4),
    });
    final bMerged = merge(b, a).merged;
    final aMerged = merge(a, bMerged).merged;
    expect(essence(aMerged), essence(bMerged));
    expect(aMerged.profile.currentStreak, 3);
  });

  group('one first workout a day (owner, 2026-10-17)', () {
    test('the one with more SP keeps them, the other becomes a repeat one', () {
      final phone = device([workout(day(5), sp: 100)]);
      final web = device([workout(day(5, hour: 20), sp: 60)]);
      final m = merge(phone, web).merged;
      expect(logAt(m, day(5)).isPrimary, isTrue);
      expect(logAt(m, day(5)).spEarned, 100);
      final repeat = logAt(m, day(5, hour: 20));
      expect(repeat.isPrimary, isFalse);
      expect(repeat.spEarned, 20); // no exercises to count: a third
      expect(m.profile.totalSP, 120);
      expect(m.profile.currentStreak, 1);
    });

    test("this device's workout becomes the repeat one when the other had more",
        () {
      final phone = device([workout(day(5), sp: 60)]);
      final web = device([workout(day(5, hour: 20), sp: 150)]);
      final r = merge(phone, web);
      final m = r.merged;
      expect(logAt(m, day(5)).isPrimary, isFalse);
      expect(logAt(m, day(5)).spEarned, 20);
      expect(logAt(m, day(5, hour: 20)).isPrimary, isTrue);
      expect(m.profile.totalSP, 170);
      expect(r.summary.addedSp, 110);
    });

    test("on a tie this device's stays the first", () {
      final phone = device([workout(day(5, hour: 21), sp: 90)]);
      final web = device([workout(day(5, hour: 7), sp: 90)]);
      final m = merge(phone, web).merged;
      expect(logAt(m, day(5, hour: 21)).isPrimary, isTrue);
      expect(logAt(m, day(5, hour: 7)).isPrimary, isFalse);
    });

    test('repeat workouts already there stay as they are', () {
      final phone = device([
        workout(day(5), sp: 100),
        workout(day(5, hour: 12), sp: 40, primary: false),
      ]);
      final web = device([workout(day(5, hour: 20), sp: 30)]);
      final m = merge(phone, web).merged;
      expect(logAt(m, day(5, hour: 12)).spEarned, 40);
      expect(m.logs.where((l) => l.isPrimary), hasLength(1));
    });
  });

  group('bonusSpOf', () {
    final pushUp = ExerciseCatalog.byId('push_s3_full_pushup')!;

    test('counts the exercises again as a repeat workout', () {
      final results = [
        ExerciseResult(
            exerciseId: pushUp.id, targetReps: 12, completedReps: 12),
        ExerciseResult(
            exerciseId: pushUp.id, targetReps: 12, completedReps: 10),
      ];
      const sp = SPService();
      final asFirst = sp.forWorkout(
          results: results, exercises: [pushUp, pushUp], isFirstToday: true);
      final asRepeat = (sp.forWorkout(
                  results: results,
                  exercises: [pushUp, pushUp],
                  isFirstToday: false) *
              0.5)
          .round();
      final log = workout(day(1), sp: asFirst, exercises: results);
      expect(ProgressMerge.bonusSpOf(log), asRepeat);
      expect(asRepeat, lessThan(asFirst));
    });

    test('a third when the exercises do not give its SP', () {
      final unknown = workout(day(1), sp: 100, exercises: [
        ExerciseResult(
            exerciseId: 'some_future_exercise',
            targetReps: 10,
            completedReps: 10),
      ]);
      expect(ProgressMerge.bonusSpOf(unknown), 33);
      final changed = workout(day(1), sp: 999, exercises: [
        ExerciseResult(exerciseId: pushUp.id, targetReps: 5, completedReps: 5),
      ]);
      expect(ProgressMerge.bonusSpOf(changed), 333);
    });
  });

  group('the streak', () {
    test("joins the two devices' days", () {
      final phone = device([workout(day(1)), workout(day(2))]);
      final web = device([workout(day(3)), workout(day(4))]);
      final m = merge(phone, web).merged;
      expect(m.profile.currentStreak, 4);
      expect(m.profile.longestStreak, 4);
      expect(m.profile.lastWorkoutDate, DateTime(2026, 9, 4));
    });

    test('a day the other device trained gives back the freeze used on it',
        () {
      // Days 1–7 earn a freeze, day 8 is missed, day 9 uses the freeze.
      final phone =
          device([for (var d = 1; d <= 7; d++) workout(day(d)), workout(day(9))]);
      expect(logAt(phone, day(9)).freezeUsed, isTrue);
      expect(phone.profile.streakFreezeCount, 0);
      final web = device([workout(day(8))]);
      final m = merge(phone, web).merged;
      expect(m.profile.currentStreak, 9);
      expect(m.profile.streakFreezeCount, 1);
      expect(logAt(m, day(9)).freezeUsed, isFalse);
      expect(logAt(m, day(7)).freezeEarned, isTrue);
    });

    test('a workout without real work does not count', () {
      final phone = device([workout(day(1)), workout(day(2))]);
      final web = device([workout(day(3), sp: 0)]);
      final m = merge(phone, web).merged;
      expect(m.profile.currentStreak, 2);
    });

    test("never below what a device knew of its last day", () {
      // The profile counted 30 days, the log keeps only the last of them.
      final phone = device([]);
      phone.logs.add(workout(day(20)));
      phone.profile
        ..currentStreak = 30
        ..longestStreak = 30
        ..lastWorkoutDate = DateTime(2026, 9, 20);
      final web = device([workout(day(2))]);
      final m = merge(phone, web).merged;
      expect(m.profile.currentStreak, 30);
      expect(m.profile.longestStreak, 30);
    });

    test('the longest streak of either device stays', () {
      final phone = device([workout(day(1))]);
      phone.profile.longestStreak = 40;
      final web = device([workout(day(10))]);
      web.profile.longestStreak = 55;
      final m = merge(phone, web).merged;
      expect(m.profile.longestStreak, 55);
      expect(m.profile.currentStreak, 1);
    });

    test('across the DST change (Berlin 2026-10-25)', () {
      final phone = device([
        workout(DateTime(2026, 10, 24, 9)),
        workout(DateTime(2026, 10, 26, 9)),
      ]);
      final web = device([workout(DateTime(2026, 10, 25, 23, 30))]);
      final m = merge(phone, web).merged;
      expect(m.profile.currentStreak, 3);
      expect(m.profile.lastWorkoutDate, DateTime(2026, 10, 26));
    });
  });

  test('a workout is the same one with or without its microseconds', () {
    final phone = device([workout(DateTime(2026, 9, 1, 9, 0, 0, 123, 456))]);
    final web = device([workout(DateTime(2026, 9, 1, 9, 0, 0, 123))]);
    expect(merge(phone, web).summary.addedWorkouts, 0);
  });

  group('skill progress', () {
    test('per branch the one further along; the later day of progress stays',
        () {
      final phone = device([], progress: {
        'push': SkillProgress(
            branchId: BranchId.push,
            currentStage: 3,
            currentReps: 8,
            lastProgressedOn: DateTime(2026, 10, 16)),
        'core': SkillProgress(branchId: BranchId.core, currentStage: 2),
      });
      final web = device([], progress: {
        'push': SkillProgress(
            branchId: BranchId.push,
            currentStage: 3,
            currentReps: 10,
            lastProgressedOn: DateTime(2026, 10, 15)),
        'core': SkillProgress(branchId: BranchId.core, currentStage: 4),
        'custom_b1': SkillProgress(customBranchId: 'b1', currentStage: 2),
      });
      final r = merge(phone, web);
      final push = r.merged.progress['push']!;
      expect(push.currentReps, 10);
      expect(push.lastProgressedOn, DateTime(2026, 10, 16));
      expect(r.merged.progress['core']!.currentStage, 4);
      expect(r.merged.progress['custom_b1']!.currentStage, 2);
      expect([for (final s in r.summary.stageUps) '${s.branchKey} ${s.stage}'],
          ['core 4', 'custom_b1 2']);
      expect(r.summary.branchesMovedOn, 1);
    });

    test('a branch further along here stays as it is', () {
      final phone = device([], progress: {
        'legs': SkillProgress(branchId: BranchId.legs, currentStage: 5),
      });
      final web = device([], progress: {
        'legs': SkillProgress(branchId: BranchId.legs, currentStage: 2),
      });
      final r = merge(phone, web);
      expect(r.merged.progress['legs']!.currentStage, 5);
      expect(r.changesAnything, isFalse);
    });

    test('the order of the steps within a stage', () {
      SkillProgress p(
              {int stage = 2,
              bool challenge = false,
              int rest = 60,
              int sets = 1,
              int reps = 5}) =>
          SkillProgress(
            branchId: BranchId.push,
            currentStage: stage,
            isChallengeUnlocked: challenge,
            currentRestSec: rest,
            currentSets: sets,
            currentReps: reps,
          );
      int cmp(SkillProgress a, SkillProgress b) =>
          ProgressMerge.compareProgress(a, b).sign;
      expect(cmp(p(stage: 3), p(challenge: true, rest: 15, sets: 3)), 1);
      expect(cmp(p(challenge: true), p(rest: 15, sets: 3, reps: 12)), 1);
      expect(cmp(p(rest: 45, sets: 3), p(rest: 60, sets: 3, reps: 12)), 1);
      expect(cmp(p(sets: 2, reps: 5), p(sets: 1, reps: 12)), 1);
      expect(cmp(p(reps: 7), p(reps: 5)), 1);
      expect(cmp(p(), p()), 0);
    });
  });

  test('achievements: the union with the earliest date, and what only the '
      'combined totals reach', () {
    final phone = device([for (var d = 1; d <= 6; d++) workout(day(d))],
        achievements: {'first_workout': day(1), 'streak_3': day(3)});
    final web = device([for (var d = 1; d <= 5; d++) workout(day(d, hour: 20))],
        achievements: {
          'first_workout': DateTime(2026, 8, 30),
          'push_s3': day(4),
        });
    final r = merge(phone, web);
    final a = r.merged.achievements;
    expect(a['first_workout'], DateTime(2026, 8, 30));
    expect(a['push_s3'], day(4));
    expect(a['workouts_10'], _now); // 6 + 5 workouts
    expect(r.summary.newAchievementIds, containsAll(['push_s3', 'workouts_10']));
    expect(r.summary.newAchievementIds, isNot(contains('first_workout')));
  });

  test('a rank reached by the SP of both', () {
    final phone = device([workout(day(1), sp: 300)]);
    final web = device([workout(day(2), sp: 300)]);
    final m = merge(phone, web).merged;
    expect(m.profile.rank, Rank.amateur);
    expect(m.achievements.keys, contains('rank_amateur'));
  });

  test("own routines, branches and courses: the union; on the same id this "
      "device's copy stays", () {
    CustomRoutine routine(String id, String name, {DateTime? lastRun}) =>
        CustomRoutine(
            id: id,
            name: name,
            exerciseIds: ['push_s1_wall_pushup'],
            createdAt: day(1),
            lastRunAt: lastRun);
    final phone = device([],
        routines: [routine('r1', 'Mine', lastRun: day(2))],
        branches: [
          CustomBranch(
              id: 'b1', name: 'Mine', exerciseIds: [], createdAt: day(1)),
        ]);
    final web = device([], routines: [
      routine('r1', 'Theirs', lastRun: day(9)),
      routine('r2', 'New'),
    ], branches: [
      CustomBranch(id: 'b1', name: 'Theirs', exerciseIds: [], createdAt: day(1)),
      CustomBranch(id: 'b2', name: 'New', exerciseIds: [], createdAt: day(2)),
    ], courses: [
      CustomCourse(
          id: 'c1',
          name: 'New',
          branchKeys: ['custom_b2'],
          hostIndex: 0,
          createdAt: day(3)),
    ]);
    final r = merge(phone, web);
    final routines = {for (final x in r.merged.routines) x.id: x};
    expect(routines['r1']!.name, 'Mine');
    expect(routines['r1']!.lastRunAt, day(9));
    expect(routines.keys, ['r1', 'r2']);
    expect([for (final b in r.merged.branches) b.name], ['Mine', 'New']);
    expect(r.merged.courses.single.id, 'c1');
    expect(r.summary.addedOwn, 3);
  });

  group('the profile', () {
    test("settings stay this device's; courses are the union", () {
      final phone = device([],
          profile: UserProfile(
            themeModeName: 'dark',
            notificationHour: 7,
            activeCourseIds: [CourseId.calisthenics.index],
            activeCourseIndex: 0,
            lastSeenReleaseVersion: '0.9.9',
          ));
      final web = device([],
          profile: UserProfile(
            themeModeName: 'light',
            notificationHour: 21,
            displayName: 'Petr',
            activeCourseIds: [CourseId.yoga.index, CourseId.calisthenics.index],
            lastSeenReleaseVersion: '0.9.11',
          ));
      final p = merge(phone, web).merged.profile;
      expect(p.themeModeName, 'dark');
      expect(p.notificationHour, 7);
      expect(p.activeCourseIds,
          [CourseId.calisthenics.index, CourseId.yoga.index]);
      expect(p.activeCourseIndex, 0);
      expect(p.displayName, 'Petr'); // none here
      expect(p.lastSeenReleaseVersion, '0.9.11');
    });

    test('the name here stays', () {
      final phone = device([], profile: UserProfile(displayName: 'Ann'));
      final web = device([], profile: UserProfile(displayName: 'Petr'));
      expect(merge(phone, web).merged.profile.displayName, 'Ann');
    });

    test('a profile without a course list (from before courses) means Calisthenics', () {
      final phone = device([], profile: UserProfile(activeCourseIds: []));
      final web = device([]); // activeCourseIds null
      expect(merge(phone, web).merged.profile.activeCourseIds,
          [CourseId.calisthenics.index]);
    });
  });

  test('the inputs are left as they were', () {
    final phone = device([workout(day(5), sp: 60)]);
    final web = device([workout(day(5, hour: 20), sp: 150)]);
    final before = jsonEncode(ProgressFile.toJson(phone,
        appVersion: '', exportedAt: DateTime(2000)));
    merge(phone, web);
    expect(
        jsonEncode(ProgressFile.toJson(phone,
            appVersion: '', exportedAt: DateTime(2000))),
        before);
    expect(phone.logs.single.isPrimary, isTrue);
  });

  test('the streak shown before and after', () {
    final phone = device([workout(DateTime(2026, 10, 15, 9))]);
    final web = device([workout(DateTime(2026, 10, 16, 9))]);
    final s = merge(phone, web).summary;
    // Two days without training and no freeze: Home shows the streak gone.
    expect(s.streakFrom, 0);
    expect(s.streakTo, 2);
  });
}
