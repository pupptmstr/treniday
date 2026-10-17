import 'dart:convert';

import '../domain/models/progress_snapshot.dart';
import 'models/branch_growth.dart';
import 'models/custom_branch.dart';
import 'models/custom_course.dart';
import 'models/custom_routine.dart';
import 'models/enums.dart';
import 'models/exercise_result.dart';
import 'models/skill_progress.dart';
import 'models/user_profile.dart';
import 'models/workout_log.dart';

/// Why a progress file could not be read.
enum ProgressFileProblem {
  /// Not JSON, not ours, or damaged.
  notProgressFile,

  /// Written by a newer app: a format version or a branch, course or rank
  /// this version does not know. Updating the app helps.
  newerApp,
}

class ProgressFileException implements Exception {
  const ProgressFileException(this.problem, this.detail);

  final ProgressFileProblem problem;
  final String detail;

  @override
  String toString() => 'ProgressFileException(${problem.name}: $detail)';
}

/// The progress file: the whole [ProgressSnapshot] as JSON of our own,
/// written field by field (not the Hive binary files), so it survives Hive
/// field changes and moves between the web, iOS and Android.
///
/// Enums are stored by name, dates as the local date and time they were
/// recorded at, to the millisecond (what Hive keeps). Exercise and
/// achievement ids are kept even when this version does not know them (the
/// screens skip unknown ids, and an old device may hold retired ones); a
/// branch, course or rank it does not know refuses the file as
/// [ProgressFileProblem.newerApp], since the models cannot hold it.
abstract final class ProgressFile {
  /// Marks the file as ours.
  static const String app = 'treniday';

  /// Raised when the structure changes; a newer one is refused.
  static const int formatVersion = 1;

  /// `treniday-progress-2026-10-17.json`.
  static String fileName(DateTime now) =>
      'treniday-progress-${now.year}-${_two(now.month)}-${_two(now.day)}.json';

  static String encode(
    ProgressSnapshot s, {
    required String appVersion,
    required DateTime exportedAt,
  }) =>
      jsonEncode(toJson(s, appVersion: appVersion, exportedAt: exportedAt));

  static Map<String, Object?> toJson(
    ProgressSnapshot s, {
    required String appVersion,
    required DateTime exportedAt,
  }) =>
      {
        'app': app,
        'formatVersion': formatVersion,
        'appVersion': appVersion,
        'exportedAt': dateToJson(exportedAt),
        'profile': _profileToJson(s.profile),
        'skillProgress': [
          for (final p in s.progress.values) _progressToJson(p),
        ],
        'workouts': [for (final l in s.logs) _logToJson(l)],
        'achievements': {
          for (final e in s.achievements.entries) e.key: dateToJson(e.value),
        },
        'routines': [for (final r in s.routines) _routineToJson(r)],
        'branches': [for (final b in s.branches) _branchToJson(b)],
        'courses': [for (final c in s.courses) _courseToJson(c)],
      };

  /// A deep copy of [s]: new objects with the same values, none of them in a
  /// Hive box.
  static ProgressSnapshot copy(ProgressSnapshot s) =>
      fromJson(toJson(s, appVersion: '', exportedAt: DateTime(2000)));

  /// Reads a file's text; throws [ProgressFileException].
  static ProgressSnapshot decode(String text) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } on FormatException catch (e) {
      throw ProgressFileException(
          ProgressFileProblem.notProgressFile, 'not JSON: ${e.message}');
    }
    return fromJson(json);
  }

  static ProgressSnapshot fromJson(Object? json) {
    if (json is! Map<String, Object?> || json['app'] != app) {
      throw const ProgressFileException(
          ProgressFileProblem.notProgressFile, 'not a TreniDay progress file');
    }
    final version = json['formatVersion'];
    if (version is! int) {
      throw const ProgressFileException(
          ProgressFileProblem.notProgressFile, 'no formatVersion');
    }
    if (version > formatVersion) {
      throw ProgressFileException(
          ProgressFileProblem.newerApp, 'formatVersion $version');
    }
    try {
      final r = _Reader(json);
      final progress = <String, SkillProgress>{};
      for (final p in r.objects('skillProgress').map(_progressFromJson)) {
        progress[p.branchKey] = p;
      }
      return ProgressSnapshot(
        profile: _profileFromJson(r.object('profile')),
        progress: progress,
        logs: [...r.objects('workouts').map(_logFromJson)],
        achievements: {
          for (final e in r.object('achievements').map.entries)
            e.key: _date(e.value),
        },
        routines: [...r.objects('routines').map(_routineFromJson)],
        branches: [...r.objects('branches').map(_branchFromJson)],
        courses: [...r.objects('courses').map(_courseFromJson)],
      );
    } on ProgressFileException {
      rethrow;
    } catch (e) {
      // A missing field or a value of the wrong type: damaged.
      throw ProgressFileException(
          ProgressFileProblem.notProgressFile, 'damaged: $e');
    }
  }

  /// The local date and time of [d] to the millisecond, without a zone:
  /// "2026-10-17T08:30:00.123". Hive keeps milliseconds, so a workout read
  /// back from the box and one still in memory write the same text.
  static String dateToJson(DateTime d) {
    final l = d.toLocal();
    return DateTime(l.year, l.month, l.day, l.hour, l.minute, l.second,
            l.millisecond)
        .toIso8601String();
  }

  static DateTime _date(Object? v) {
    final d = DateTime.parse(v as String);
    return d.isUtc ? d.toLocal() : d;
  }

  static DateTime? _dateOrNull(Object? v) => v == null ? null : _date(v);

  static T _byName<T extends Enum>(List<T> values, Object? name, String what) {
    // No name at all is a damaged file, an unknown one a newer app's.
    if (name is! String) throw FormatException('no $what');
    for (final v in values) {
      if (v.name == name) return v;
    }
    throw ProgressFileException(ProgressFileProblem.newerApp, '$what $name');
  }

  // ── Profile ─────────────────────────────────────────────────────────────────

  static Map<String, Object?> _profileToJson(UserProfile p) => {
        'rank': p.rank.name,
        'totalSP': p.totalSP,
        'currentStreak': p.currentStreak,
        'longestStreak': p.longestStreak,
        'streakFreezeCount': p.streakFreezeCount,
        'lastWorkoutDate': _orNull(p.lastWorkoutDate, dateToJson),
        'notificationHour': p.notificationHour,
        'notificationMinute': p.notificationMinute,
        'notificationsEnabled': p.notificationsEnabled,
        'eveningReminderEnabled': p.eveningReminderEnabled,
        'streakThreatEnabled': p.streakThreatEnabled,
        'locale': p.locale,
        'preferredWorkoutMinutes': p.preferredWorkoutMinutes,
        'fitnessGoal': p.fitnessGoal?.name,
        'themeModeName': p.themeModeName,
        'hasPullUpBar': p.hasPullUpBar,
        'soundEnabled': p.soundEnabled,
        'hapticEnabled': p.hapticEnabled,
        'healthWorkoutsEnabled': p.healthWorkoutsEnabled,
        'healthWeightEnabled': p.healthWeightEnabled,
        'displayName': p.displayName,
        'activeCourses': p.activeCourseIds == null
            ? null
            : [
                for (final i in p.activeCourseIds!)
                  if (i >= 0 && i < CourseId.values.length)
                    CourseId.values[i].name,
              ],
        'activeCourseIndex': p.activeCourseIndex,
        'lastSeenReleaseVersion': p.lastSeenReleaseVersion,
        'activeCustomCourseId': p.activeCustomCourseId,
        'soundModeName': p.soundModeName,
      };

  static UserProfile _profileFromJson(_Reader r) {
    final courses = r.listOrNull('activeCourses');
    final goal = r.raw('fitnessGoal');
    return UserProfile(
      rank: _byName(Rank.values, r.raw('rank'), 'rank'),
      totalSP: r.integer('totalSP'),
      currentStreak: r.integer('currentStreak'),
      longestStreak: r.integer('longestStreak'),
      streakFreezeCount: r.integer('streakFreezeCount'),
      lastWorkoutDate: _dateOrNull(r.raw('lastWorkoutDate')),
      notificationHour: r.integer('notificationHour'),
      notificationMinute: r.integer('notificationMinute'),
      notificationsEnabled: r.boolean('notificationsEnabled'),
      eveningReminderEnabled: r.boolean('eveningReminderEnabled'),
      streakThreatEnabled: r.boolean('streakThreatEnabled'),
      locale: r.raw('locale') as String?,
      preferredWorkoutMinutes: r.raw('preferredWorkoutMinutes') as int?,
      fitnessGoal: goal == null
          ? null
          : _byName(FitnessGoal.values, goal, 'fitness goal'),
      themeModeName: r.raw('themeModeName') as String?,
      hasPullUpBar: r.raw('hasPullUpBar') as bool?,
      soundEnabled: r.raw('soundEnabled') as bool?,
      hapticEnabled: r.raw('hapticEnabled') as bool?,
      healthWorkoutsEnabled: r.raw('healthWorkoutsEnabled') as bool?,
      healthWeightEnabled: r.raw('healthWeightEnabled') as bool?,
      displayName: r.raw('displayName') as String?,
      activeCourseIds: courses == null
          ? null
          : [for (final c in courses) _byName(CourseId.values, c, 'course').index],
      activeCourseIndex: r.raw('activeCourseIndex') as int?,
      lastSeenReleaseVersion: r.raw('lastSeenReleaseVersion') as String?,
      activeCustomCourseId: r.raw('activeCustomCourseId') as String?,
      soundModeName: r.raw('soundModeName') as String?,
    );
  }

  // ── Skill progress ──────────────────────────────────────────────────────────

  static Map<String, Object?> _progressToJson(SkillProgress p) => {
        'branch': p.branchId?.name,
        'customBranchId': p.customBranchId,
        'stage': p.currentStage,
        'reps': p.currentReps,
        'sets': p.currentSets,
        'restSec': p.currentRestSec,
        'challengeUnlocked': p.isChallengeUnlocked,
        'lastProgressedOn': _orNull(p.lastProgressedOn, dateToJson),
      };

  static SkillProgress _progressFromJson(_Reader r) {
    final custom = r.raw('customBranchId') as String?;
    final name = r.raw('branch');
    final branch =
        custom == null ? _byName(BranchId.values, name, 'branch') : null;
    final stage = r.integer('stage');
    if (branch != null && stage > branch.stageCount) {
      // A newer app gave the branch more stages.
      throw ProgressFileException(
          ProgressFileProblem.newerApp, '${branch.name} stage $stage');
    }
    return SkillProgress(
      branchId: branch,
      customBranchId: custom,
      currentStage: stage,
      currentReps: r.integer('reps'),
      currentSets: r.integer('sets'),
      currentRestSec: r.integer('restSec'),
      isChallengeUnlocked: r.boolean('challengeUnlocked'),
      lastProgressedOn: _dateOrNull(r.raw('lastProgressedOn')),
    );
  }

  // ── Workouts ────────────────────────────────────────────────────────────────

  static Map<String, Object?> _logToJson(WorkoutLog l) => {
        'date': dateToJson(l.date),
        'setType': l.setType.name,
        'exercises': [
          for (final e in l.exercises)
            {
              'id': e.exerciseId,
              'targetReps': e.targetReps,
              'completedReps': e.completedReps,
              'targetSec': e.targetDurationSec,
              'actualSec': e.actualDurationSec,
            },
        ],
        'sp': l.spEarned,
        'durationSec': l.durationSec,
        'primary': l.isPrimary,
        'course': l.courseIdIndex == null
            ? null
            : CourseId.values[l.courseIdIndex!].name,
        'freezeUsed': l.freezeUsed,
        'freezeEarned': l.freezeEarned,
        'estimatedSec': l.estimatedDurationSec,
        'growth': l.growth == null
            ? null
            : [
                for (final g in l.growth!)
                  {
                    'branch': g.branchKey,
                    'fromStage': g.fromStage,
                    'toStage': g.toStage,
                    'fromAmount': g.fromAmount,
                    'toAmount': g.toAmount,
                    'fromSets': g.fromSets,
                    'toSets': g.toSets,
                    'fromRestSec': g.fromRestSec,
                    'toRestSec': g.toRestSec,
                    'challengeUnlocked': g.challengeUnlocked,
                  },
              ],
      };

  static WorkoutLog _logFromJson(_Reader r) {
    final course = r.raw('course');
    final growth = r.listOrNull('growth');
    return WorkoutLog(
      date: _date(r.raw('date')),
      setType: _byName(SetType.values, r.raw('setType'), 'set type'),
      exercises: [
        for (final e in r.objects('exercises'))
          ExerciseResult(
            exerciseId: e.string('id'),
            targetReps: e.integer('targetReps'),
            completedReps: e.integer('completedReps'),
            targetDurationSec: e.raw('targetSec') as int?,
            actualDurationSec: e.raw('actualSec') as int?,
          ),
      ],
      spEarned: r.integer('sp'),
      durationSec: r.integer('durationSec'),
      isPrimary: r.boolean('primary'),
      courseIdIndex: course == null
          ? null
          : _byName(CourseId.values, course, 'course').index,
      freezeUsed: r.boolean('freezeUsed'),
      freezeEarned: r.boolean('freezeEarned'),
      estimatedDurationSec: r.raw('estimatedSec') as int?,
      growth: growth == null
          ? null
          : [
              for (final g in growth.map(_Reader.of))
                BranchGrowth(
                  branchKey: _branchKey(g.string('branch')),
                  fromStage: g.integer('fromStage'),
                  toStage: g.integer('toStage'),
                  fromAmount: g.integer('fromAmount'),
                  toAmount: g.integer('toAmount'),
                  fromSets: g.integer('fromSets'),
                  toSets: g.integer('toSets'),
                  fromRestSec: g.integer('fromRestSec'),
                  toRestSec: g.integer('toRestSec'),
                  challengeUnlocked: g.boolean('challengeUnlocked'),
                ),
            ],
    );
  }

  /// A `Branch.key`: an own branch's, or the name of a built-in one this
  /// version knows.
  static String _branchKey(String key) {
    if (key.startsWith(CustomBranch.keyPrefix)) return key;
    return _byName(BranchId.values, key, 'branch').name;
  }

  // ── Own routines, branches, courses ─────────────────────────────────────────

  static Map<String, Object?> _routineToJson(CustomRoutine r) => {
        'id': r.id,
        'name': r.name,
        'exercises': r.exerciseIds,
        'createdAt': dateToJson(r.createdAt),
        'lastRunAt': _orNull(r.lastRunAt, dateToJson),
      };

  static CustomRoutine _routineFromJson(_Reader r) => CustomRoutine(
        id: r.string('id'),
        name: r.string('name'),
        exerciseIds: r.strings('exercises'),
        createdAt: _date(r.raw('createdAt')),
        lastRunAt: _dateOrNull(r.raw('lastRunAt')),
      );

  static Map<String, Object?> _branchToJson(CustomBranch b) => {
        'id': b.id,
        'name': b.name,
        'exercises': b.exerciseIds,
        'createdAt': dateToJson(b.createdAt),
      };

  static CustomBranch _branchFromJson(_Reader r) => CustomBranch(
        id: r.string('id'),
        name: r.string('name'),
        exerciseIds: r.strings('exercises'),
        createdAt: _date(r.raw('createdAt')),
      );

  static Map<String, Object?> _courseToJson(CustomCourse c) => {
        'id': c.id,
        'name': c.name,
        'branches': c.branchKeys,
        'host': CourseId.values[c.hostIndex].name,
        'createdAt': dateToJson(c.createdAt),
        'shown': c.shown,
      };

  static CustomCourse _courseFromJson(_Reader r) => CustomCourse(
        id: r.string('id'),
        name: r.string('name'),
        branchKeys: [for (final k in r.strings('branches')) _branchKey(k)],
        hostIndex: _byName(CourseId.values, r.raw('host'), 'host').index,
        createdAt: _date(r.raw('createdAt')),
        shown: r.boolean('shown'),
      );

  static String? _orNull<T>(T? v, String Function(T) f) =>
      v == null ? null : f(v);

  static String _two(int n) => n.toString().padLeft(2, '0');
}

/// Typed reads from a JSON object; a missing field or a wrong type throws
/// (a `TypeError`), which [ProgressFile.fromJson] reports as damaged.
class _Reader {
  _Reader(this.map);

  static _Reader of(Object? json) => _Reader(json as Map<String, Object?>);

  final Map<String, Object?> map;

  Object? raw(String key) => map[key];
  String string(String key) => map[key] as String;
  int integer(String key) => map[key] as int;
  bool boolean(String key) => map[key] as bool;
  _Reader object(String key) => _Reader.of(map[key]);
  List<Object?>? listOrNull(String key) => map[key] as List<Object?>?;
  List<String> strings(String key) => [...(map[key] as List<Object?>).cast<String>()];
  Iterable<_Reader> objects(String key) =>
      (map[key] as List<Object?>).map(_Reader.of);
}
