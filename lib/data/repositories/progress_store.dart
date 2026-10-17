import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce/hive_ce.dart';

import '../../domain/models/progress_snapshot.dart';
import '../models/custom_branch.dart';
import '../models/custom_course.dart';
import '../models/custom_routine.dart';
import '../models/skill_progress.dart';
import '../models/user_profile.dart';
import '../models/workout_log.dart';
import '../progress_file.dart';

/// The whole of the user's data in the Hive boxes as one [ProgressSnapshot]:
/// what a progress file is written from, and where a merged one goes.
class ProgressStore {
  Box<UserProfile> get _profile => Hive.box<UserProfile>('user_profile');
  Box<SkillProgress> get _progress => Hive.box<SkillProgress>('skill_progress');
  Box<WorkoutLog> get _logs => Hive.box<WorkoutLog>('workout_log');
  Box<DateTime> get _achievements => Hive.box<DateTime>('achievements');
  Box<CustomRoutine> get _routines => Hive.box<CustomRoutine>('custom_routines');
  Box<CustomBranch> get _branches => Hive.box<CustomBranch>('custom_branches');
  Box<CustomCourse> get _courses => Hive.box<CustomCourse>('custom_courses');

  /// A copy of everything stored (the box objects stay untouched). A device
  /// that never saved a profile reads a default one.
  ProgressSnapshot read() => ProgressFile.copy(ProgressSnapshot(
        profile: _profile.get('profile') ?? UserProfile(),
        progress: {
          for (final p in _progress.values) p.branchKey: p,
        },
        logs: [..._logs.values],
        achievements: {
          for (final k in _achievements.keys.cast<String>())
            k: _achievements.get(k)!,
        },
        routines: [..._routines.values],
        branches: [..._branches.values],
        courses: [..._courses.values],
      ));

  /// Replaces what is stored with [next], a merge of [previous] (what [read]
  /// gave). Hive has no transaction across boxes, so if a write fails,
  /// [previous] is written back before the error goes on.
  Future<void> replace(ProgressSnapshot next,
      {required ProgressSnapshot previous}) async {
    try {
      await _write(next);
    } catch (_) {
      try {
        await _write(ProgressFile.copy(previous));
      } catch (_) {
        // Nothing more can be done; the first error is the one to report.
      }
      rethrow;
    }
  }

  Future<void> _write(ProgressSnapshot s) async {
    await _profile.put('profile', s.profile);
    await _putAll(_progress, s.progress);
    // Logs have auto-increment keys that nothing refers to.
    await _logs.clear();
    await _logs.addAll(s.logs);
    await _putAll(_achievements, s.achievements);
    await _putAll(_routines, {for (final r in s.routines) r.id: r});
    await _putAll(_branches, {for (final b in s.branches) b.id: b});
    await _putAll(_courses, {for (final c in s.courses) c.id: c});
  }

  /// [box] holds exactly [entries] afterwards.
  static Future<void> _putAll<T>(Box<T> box, Map<String, T> entries) async {
    await box.deleteAll(box.keys.where((k) => !entries.containsKey(k)).toList());
    await box.putAll(entries);
  }
}

final progressStoreProvider = Provider<ProgressStore>((_) => ProgressStore());
