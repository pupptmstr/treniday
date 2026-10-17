import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:treniday/data/models/branch_growth.dart';
import 'package:treniday/data/models/custom_branch.dart';
import 'package:treniday/data/models/custom_course.dart';
import 'package:treniday/data/models/custom_routine.dart';
import 'package:treniday/data/models/enums.dart';
import 'package:treniday/data/models/exercise_result.dart';
import 'package:treniday/data/models/skill_progress.dart';
import 'package:treniday/data/models/user_profile.dart';
import 'package:treniday/data/models/workout_log.dart';
import 'package:treniday/data/progress_file.dart';
import 'package:treniday/domain/models/progress_snapshot.dart';

/// A snapshot with every field set to something other than its default.
ProgressSnapshot fullSnapshot() => ProgressSnapshot(
      profile: UserProfile(
        rank: Rank.sportsman,
        totalSP: 2400,
        currentStreak: 12,
        longestStreak: 20,
        streakFreezeCount: 2,
        lastWorkoutDate: DateTime(2026, 10, 16),
        notificationHour: 7,
        notificationMinute: 30,
        notificationsEnabled: false,
        eveningReminderEnabled: false,
        streakThreatEnabled: false,
        locale: 'de',
        preferredWorkoutMinutes: 15,
        fitnessGoal: FitnessGoal.calisthenics,
        themeModeName: 'dark',
        hasPullUpBar: true,
        soundEnabled: false,
        hapticEnabled: false,
        healthWorkoutsEnabled: true,
        healthWeightEnabled: true,
        displayName: 'Petr',
        activeCourseIds: [CourseId.yoga.index, CourseId.calisthenics.index],
        activeCourseIndex: 1,
        lastSeenReleaseVersion: '0.9.10',
        activeCustomCourseId: 'c1',
        soundModeName: 'key',
      ),
      progress: {
        'push': SkillProgress(
          branchId: BranchId.push,
          currentStage: 4,
          currentReps: 9,
          currentSets: 2,
          currentRestSec: 45,
          isChallengeUnlocked: true,
          lastProgressedOn: DateTime(2026, 10, 16, 8, 1, 2, 3),
        ),
        'custom_b1': SkillProgress(
          customBranchId: 'b1',
          currentStage: 2,
          currentReps: 6,
          currentSets: 1,
          currentRestSec: 30,
        ),
      },
      logs: [
        WorkoutLog(
          date: DateTime(2026, 10, 16, 8, 30, 15, 123),
          setType: SetType.daily,
          exercises: [
            ExerciseResult(
                exerciseId: 'push_s4_diamond_pushup', targetReps: 10, completedReps: 9),
            ExerciseResult(
              exerciseId: 'core_s2_plank',
              targetReps: 0,
              completedReps: 0,
              targetDurationSec: 20,
              actualDurationSec: 18,
            ),
          ],
          spEarned: 140,
          durationSec: 610,
          courseIdIndex: CourseId.calisthenics.index,
          freezeUsed: true,
          freezeEarned: true,
          estimatedDurationSec: 540,
          growth: [
            BranchGrowth(
              branchKey: 'push',
              fromStage: 4,
              toStage: 4,
              fromAmount: 7,
              toAmount: 9,
              fromSets: 2,
              toSets: 2,
              fromRestSec: 45,
              toRestSec: 45,
            ),
            BranchGrowth(
              branchKey: 'custom_b1',
              fromStage: 1,
              toStage: 2,
              fromAmount: 8,
              toAmount: 6,
              fromSets: 1,
              toSets: 1,
              fromRestSec: 30,
              toRestSec: 30,
              challengeUnlocked: true,
            ),
          ],
        ),
        WorkoutLog(
          date: DateTime(2026, 10, 16, 19, 0),
          setType: SetType.skill,
          exercises: const [],
          spEarned: 20,
          durationSec: 300,
          isPrimary: false,
        ),
      ],
      achievements: {
        'first_workout': DateTime(2026, 10, 1, 9),
        'retired_friend_badge': DateTime(2026, 9, 1),
      },
      routines: [
        CustomRoutine(
          id: 'r1',
          name: 'Morning',
          exerciseIds: ['push_s1_wall_pushup', 'some_future_exercise'],
          createdAt: DateTime(2026, 10, 2),
          lastRunAt: DateTime(2026, 10, 15, 7),
        ),
      ],
      branches: [
        CustomBranch(
          id: 'b1',
          name: 'Mine',
          exerciseIds: ['push_s1_wall_pushup', 'push_s2_knee_pushup'],
          createdAt: DateTime(2026, 10, 3),
        ),
      ],
      courses: [
        CustomCourse(
          id: 'c1',
          name: 'Course',
          branchKeys: ['push', 'custom_b1'],
          hostIndex: CourseId.yoga.index,
          createdAt: DateTime(2026, 10, 4),
          shown: false,
        ),
      ],
    );

String encode(ProgressSnapshot s) => ProgressFile.encode(s,
    appVersion: '0.9.11', exportedAt: DateTime(2026, 10, 17, 12));

Map<String, Object?> jsonOf(ProgressSnapshot s) =>
    jsonDecode(encode(s)) as Map<String, Object?>;

ProgressFileProblem? problemOf(String text) {
  try {
    ProgressFile.decode(text);
    return null;
  } on ProgressFileException catch (e) {
    return e.problem;
  }
}

/// [fullSnapshot]'s file with [edit] applied to its JSON.
String edited(void Function(Map<String, Object?> json) edit) {
  final json = jsonOf(fullSnapshot());
  edit(json);
  return jsonEncode(json);
}

void main() {
  test('a file read back writes the same file: every field survives', () {
    final text = encode(fullSnapshot());
    expect(encode(ProgressFile.decode(text)), text);
  });

  test('the file says what it is and where it comes from', () {
    final json = jsonOf(fullSnapshot());
    expect(json['app'], 'treniday');
    expect(json['formatVersion'], ProgressFile.formatVersion);
    expect(json['appVersion'], '0.9.11');
    expect(json['exportedAt'], '2026-10-17T12:00:00.000');
  });

  test('enums by name, dates as the local time to the millisecond', () {
    final json = jsonOf(fullSnapshot());
    final profile = json['profile'] as Map<String, Object?>;
    expect(profile['rank'], 'sportsman');
    expect(profile['activeCourses'], ['yoga', 'calisthenics']);
    final log = (json['workouts'] as List).first as Map<String, Object?>;
    expect(log['date'], '2026-10-16T08:30:15.123');
    expect(log['course'], 'calisthenics');
    expect(log['setType'], 'daily');
    final course = (json['courses'] as List).single as Map<String, Object?>;
    expect(course['host'], 'yoga');
  });

  test('microseconds are dropped: Hive keeps milliseconds', () {
    // A workout just finished is held with microseconds; read back from the
    // box it has milliseconds. Both must write the same date.
    expect(ProgressFile.dateToJson(DateTime(2026, 10, 16, 8, 30, 15, 123, 456)),
        ProgressFile.dateToJson(DateTime(2026, 10, 16, 8, 30, 15, 123)));
  });

  test('a UTC time is written as the local time it stands for', () {
    final local = DateTime(2026, 10, 16, 8, 30);
    expect(ProgressFile.dateToJson(local.toUtc()),
        ProgressFile.dateToJson(local));
  });

  test('unknown exercise and achievement ids are kept', () {
    final back = ProgressFile.decode(encode(fullSnapshot()));
    expect(back.routines.single.exerciseIds, contains('some_future_exercise'));
    expect(back.achievements.keys, contains('retired_friend_badge'));
  });

  test('copy gives new objects with the same values', () {
    final s = fullSnapshot();
    final c = ProgressFile.copy(s);
    expect(identical(c.profile, s.profile), isFalse);
    expect(identical(c.logs.first, s.logs.first), isFalse);
    expect(encode(c), encode(s));
  });

  test('the file name carries the date', () {
    expect(ProgressFile.fileName(DateTime(2026, 3, 9, 23, 59)),
        'treniday-progress-2026-03-09.json');
  });

  group('refused', () {
    test('not JSON, or not ours', () {
      expect(problemOf('hello'), ProgressFileProblem.notProgressFile);
      expect(problemOf('[]'), ProgressFileProblem.notProgressFile);
      expect(problemOf('{"app": "other", "formatVersion": 1}'),
          ProgressFileProblem.notProgressFile);
      expect(problemOf(edited((j) => j.remove('formatVersion'))),
          ProgressFileProblem.notProgressFile);
    });

    test('damaged: a missing field or a wrong type', () {
      expect(problemOf(edited((j) => j.remove('workouts'))),
          ProgressFileProblem.notProgressFile);
      expect(
          problemOf(edited((j) => (j['profile'] as Map)['totalSP'] = 'many')),
          ProgressFileProblem.notProgressFile);
      expect(problemOf(edited((j) => (j['profile'] as Map).remove('rank'))),
          ProgressFileProblem.notProgressFile);
      expect(
          problemOf(edited(
              (j) => ((j['workouts'] as List).first as Map)['date'] = 'soon')),
          ProgressFileProblem.notProgressFile);
    });

    test('a newer format', () {
      expect(
          problemOf(edited(
              (j) => j['formatVersion'] = ProgressFile.formatVersion + 1)),
          ProgressFileProblem.newerApp);
    });

    test('a branch, course or rank this version does not know', () {
      expect(
          problemOf(edited((j) =>
              ((j['skillProgress'] as List).first as Map)['branch'] = 'swim')),
          ProgressFileProblem.newerApp);
      expect(
          problemOf(edited((j) =>
              ((j['workouts'] as List).first as Map)['course'] = 'pilates')),
          ProgressFileProblem.newerApp);
      expect(problemOf(edited((j) => (j['profile'] as Map)['rank'] = 'titan')),
          ProgressFileProblem.newerApp);
      expect(
          problemOf(edited((j) => ((j['courses'] as List).single
              as Map)['branches'] = ['push', 'swim'])),
          ProgressFileProblem.newerApp);
    });

    test('a stage beyond the branch: a newer app gave it more', () {
      expect(
          problemOf(edited((j) => ((j['skillProgress'] as List).first
              as Map)['stage'] = BranchId.push.stageCount + 1)),
          ProgressFileProblem.newerApp);
    });
  });

  test('a file from a newer app version that this one can hold is read', () {
    // The web build is often newer than the store app: only what cannot be
    // held refuses a file, not the version number.
    final text = edited((j) => j['appVersion'] = '0.9.99');
    expect(problemOf(text), isNull);
  });
}
