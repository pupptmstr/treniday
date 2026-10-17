import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive_ce.dart';
import 'package:treniday/data/models/enums.dart';
import 'package:treniday/data/models/skill_progress.dart';
import 'package:treniday/data/models/user_profile.dart';
import 'package:treniday/data/models/workout_log.dart';
import 'package:treniday/data/progress_file.dart';
import 'package:treniday/data/repositories/achievement_repository.dart';
import 'package:treniday/data/repositories/progress_store.dart';
import 'package:treniday/data/repositories/skill_progress_repository.dart';
import 'package:treniday/data/repositories/user_repository.dart';
import 'package:treniday/data/repositories/workout_repository.dart';
import 'package:treniday/domain/models/progress_snapshot.dart';
import 'package:treniday/domain/services/progress_merge.dart';

import '../../helpers/hive_test_env.dart';
import '../progress_file_test.dart' show fullSnapshot;

/// The file of [s] with everything in a fixed order: after a restart Hive
/// gives the keys sorted, and the order means nothing.
String textOf(ProgressSnapshot s) {
  List<String> keys(Map<String, Object?> m) => m.keys.toList()..sort();
  return ProgressFile.encode(
      ProgressSnapshot(
        profile: s.profile,
        progress: {for (final k in keys(s.progress)) k: s.progress[k]!},
        logs: [...s.logs]..sort((a, b) => a.date.compareTo(b.date)),
        achievements: {
          for (final k in keys(s.achievements)) k: s.achievements[k]!,
        },
        routines: [...s.routines]..sort((a, b) => a.id.compareTo(b.id)),
        branches: [...s.branches]..sort((a, b) => a.id.compareTo(b.id)),
        courses: [...s.courses]..sort((a, b) => a.id.compareTo(b.id)),
      ),
      appVersion: '0.9.11',
      exportedAt: DateTime(2026, 10, 17));
}

void main() {
  late HiveTestEnv env;
  setUp(() async => env = await HiveTestEnv.open());
  tearDown(() => env.dispose());

  test('what is stored, read as a snapshot of copies', () async {
    await UserRepository().saveProfile(UserProfile(totalSP: 120));
    await WorkoutRepository().addLog(WorkoutLog(
      date: DateTime(2026, 10, 16, 8, 30),
      setType: SetType.daily,
      exercises: const [],
      spEarned: 120,
      durationSec: 600,
    ));
    await SkillProgressRepository()
        .saveProgress(SkillProgress(branchId: BranchId.legs, currentStage: 3));
    await AchievementRepository().markEarned('first_workout');

    final s = ProgressStore().read();
    expect(s.profile.totalSP, 120);
    expect(s.logs.single.spEarned, 120);
    expect(s.progress['legs']!.currentStage, 3);
    expect(s.achievements.keys, ['first_workout']);

    // Copies: changing the snapshot leaves the boxes as they were.
    s.profile.totalSP = 9999;
    s.progress['legs']!.currentStage = 5;
    expect(UserRepository().getProfile().totalSP, 120);
    expect(SkillProgressRepository().getProgress(BranchId.legs).currentStage, 3);
  });

  test('a device that never saved a profile reads a default one', () {
    final s = ProgressStore().read();
    expect(s.profile.totalSP, 0);
    expect(s.logs, isEmpty);
  });

  test('replace writes every box, and it is there after a restart', () async {
    final store = ProgressStore();
    final previous = store.read();
    final next = fullSnapshot();
    await store.replace(next, previous: previous);
    await env.reopen();
    expect(textOf(ProgressStore().read()), textOf(next));
    expect(UserRepository().getProfile().displayName, 'Petr');
    expect(WorkoutRepository().totalCount, 2);
  });

  test('replace leaves nothing of the old state behind', () async {
    final store = ProgressStore();
    await store.replace(fullSnapshot(), previous: store.read());
    // A smaller state, as the write-back after a failed write would be.
    final small = ProgressFile.copy(fullSnapshot());
    small.logs.removeLast();
    small.progress.remove('custom_b1');
    small.achievements.remove('retired_friend_badge');
    small.routines.clear();
    await store.replace(small, previous: store.read());
    await env.reopen();
    expect(textOf(ProgressStore().read()), textOf(small));
  });

  test('a merged file written and read back merges into nothing new', () async {
    final store = ProgressStore();
    await UserRepository().saveProfile(UserProfile(displayName: 'Ann'));
    final imported = ProgressFile.decode(textOf(fullSnapshot()));
    final local = store.read();
    final result = ProgressMerge.merge(local, imported, now: DateTime(2026, 10, 17));
    await store.replace(result.merged, previous: local);
    await env.reopen();
    final again = ProgressMerge.merge(ProgressStore().read(), imported,
        now: DateTime(2026, 10, 18));
    expect(again.changesAnything, isFalse);
    expect(Hive.box<WorkoutLog>('workout_log').length, 2);
    expect(UserRepository().getProfile().displayName, 'Ann');
  });
}
