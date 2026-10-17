import '../../data/models/custom_branch.dart';
import '../../data/models/custom_course.dart';
import '../../data/models/custom_routine.dart';
import '../../data/models/skill_progress.dart';
import '../../data/models/user_profile.dart';
import '../../data/models/workout_log.dart';

/// Everything the app keeps about the user's training, as one value: what a
/// progress file holds (`ProgressFile`) and what `ProgressMerge` joins.
///
/// The objects are copies, never the ones that live in the Hive boxes
/// (`ProgressStore.read` makes them), so a merge can build on them freely.
class ProgressSnapshot {
  const ProgressSnapshot({
    required this.profile,
    required this.progress,
    required this.logs,
    required this.achievements,
    required this.routines,
    required this.branches,
    required this.courses,
  });

  final UserProfile profile;

  /// Skill progress by `SkillProgress.branchKey` (the box key).
  final Map<String, SkillProgress> progress;

  /// Every workout, in no particular order.
  final List<WorkoutLog> logs;

  /// Achievement id → when it was earned.
  final Map<String, DateTime> achievements;

  final List<CustomRoutine> routines;
  final List<CustomBranch> branches;
  final List<CustomCourse> courses;
}
