import 'package:flutter_test/flutter_test.dart';
import 'package:treniday/core/extensions/achievement_l10n.dart';
import 'package:treniday/data/models/custom_branch.dart';
import 'package:treniday/data/models/enums.dart';
import 'package:treniday/data/models/user_profile.dart';
import 'package:treniday/domain/models/progress_snapshot.dart';
import 'package:treniday/domain/services/progress_merge.dart';
import 'package:treniday/features/settings/progress_transfer.dart';

import '../../helpers/all_translations.dart';

ProgressSnapshot _merged() => ProgressSnapshot(
      profile: UserProfile(),
      progress: const {},
      logs: const [],
      achievements: const {},
      routines: const [],
      branches: [
        CustomBranch(
            id: 'b1',
            name: 'Handstand path',
            exerciseIds: const [],
            createdAt: DateTime(2026, 10, 1)),
      ],
      courses: const [],
    );

const _summary = ProgressMergeSummary(
  addedWorkouts: 12,
  addedSp: 340,
  rankFrom: Rank.sportsman,
  rankTo: Rank.athlete,
  streakFrom: 9,
  streakTo: 14,
  bestStreakFrom: 14,
  bestStreakTo: 14,
  newAchievementIds: ['workouts_10', 'push_s3'],
  stageUps: [StageUp('push', 5), StageUp('custom_b1', 2)],
  branchesMovedOn: 3,
  addedOwn: 2,
);

void main() {
  test('every change of the summary is a line, in every language', () {
    for (final l10n in allTranslations) {
      final lines = importSummaryLines(_summary, _merged(), l10n);
      expect(lines, [
        l10n.progressImportWorkouts(12),
        l10n.progressImportSp(340),
        l10n.progressImportRank(
            Rank.sportsman.localizedName(l10n), Rank.athlete.localizedName(l10n)),
        l10n.progressImportStreak(9, 14),
        // The best streak did not change: no line.
        l10n.progressImportStage(BranchId.push.localizedName(l10n), 5),
        l10n.progressImportStage('Handstand path', 2),
        l10n.progressImportMovedOn(3),
        l10n.progressImportAchievements(2,
            '${AchievementL10n.name(l10n, 'workouts_10')}, ${AchievementL10n.name(l10n, 'push_s3')}'),
        l10n.progressImportOwn(2),
      ], reason: l10n.localeName);
      for (final line in lines.take(2)) {
        expect(line, matches(RegExp(r'\d')), reason: l10n.localeName);
      }
    }
  });

  test('the counted lines carry their number in every language', () {
    for (final l10n in allTranslations) {
      for (final n in [1, 2, 3, 5, 11, 21, 22, 101]) {
        for (final text in [
          l10n.progressImportWorkouts(n),
          l10n.progressImportStreak(0, n),
          l10n.progressImportBestStreak(0, n),
          l10n.progressImportAchievements(n, 'x'),
          l10n.progressImportMovedOn(n),
          l10n.progressImportOwn(n),
        ]) {
          expect(text, contains('$n'), reason: '${l10n.localeName}: $text');
        }
      }
    }
  });
}
