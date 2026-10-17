import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/extensions/achievement_l10n.dart';
import '../../core/extensions/build_context_l10n.dart';
import '../../core/services/health_service.dart';
import '../../core/services/notification_service.dart';
import '../../core/utils/calendar_days.dart';
import '../../core/services/progress_file_service.dart';
import '../../data/models/custom_branch.dart';
import '../../data/models/enums.dart';
import '../../data/models/workout_log.dart';
import '../../data/progress_file.dart';
import '../../data/repositories/custom_course_repository.dart';
import '../../data/repositories/custom_routine_repository.dart';
import '../../data/repositories/progress_store.dart';
import '../../data/static/release_notes_catalog.dart';
import '../../domain/models/progress_snapshot.dart';
import '../../domain/services/health_import.dart';
import '../../domain/services/health_workout.dart';
import '../../domain/services/progress_merge.dart';
import '../../domain/services/streak_service.dart';
import '../../domain/services/workout_energy.dart';
import '../../l10n/app_localizations.dart';
import '../home/providers/home_provider.dart';
import '../home/providers/home_widget_sync.dart';
import '../profile/providers/profile_provider.dart';
import '../profile/providers/whats_new_provider.dart';
import 'providers/settings_provider.dart';

/// Settings → Your data → "Save progress to a file": the whole progress as a
/// file, offered through the share sheet (a download in a computer's
/// browser). [origin] is the tapped tile, for the share sheet on iPad.
Future<void> exportProgress(BuildContext context, WidgetRef ref,
    {Rect? origin}) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final now = DateTime.now();
  final text = ProgressFile.encode(
    ref.read(progressStoreProvider).read(),
    // The newest "What's new" entry is the pubspec version (a test checks).
    appVersion: ReleaseNotesCatalog.latest.version,
    exportedAt: now,
  );
  try {
    await ProgressFileService.export(text, ProgressFile.fileName(now),
        origin: origin, subject: l10n.progressExportSubject);
  } catch (_) {
    messenger.showSnackBar(SnackBar(content: Text(l10n.progressExportFailed)));
  }
}

/// Settings → Your data → "Add progress from a file": pick a file, show what
/// merging it changes, and on the user's yes write the merge
/// ([ProgressMerge]) and refresh everything that shows the progress.
Future<void> importProgress(BuildContext context, WidgetRef ref) async {
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);

  final ProgressSnapshot imported;
  try {
    final text = await ProgressFileService.pick();
    if (text == null) return;
    imported = ProgressFile.decode(text);
  } on ProgressFileException catch (e) {
    if (context.mounted) {
      await _tell(
          context,
          e.problem == ProgressFileProblem.newerApp
              ? l10n.progressImportNewer
              : l10n.progressImportNotOurs);
    }
    return;
  } catch (_) {
    // Not text, or the file could not be read.
    if (context.mounted) await _tell(context, l10n.progressImportNotOurs);
    return;
  }

  final store = ref.read(progressStoreProvider);
  final local = store.read();
  final result = ProgressMerge.merge(local, imported, now: DateTime.now());
  if (!context.mounted) return;
  if (!result.changesAnything) {
    await _tell(context, l10n.progressImportNothing);
    return;
  }

  final lines = importSummaryLines(result.summary, result.merged, l10n);
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.progressImportTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.progressImportIntro),
            if (lines.isNotEmpty) const SizedBox(height: 12),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3, right: 8),
                      child: Icon(Icons.add_circle_outline_rounded,
                          size: 16,
                          color: Theme.of(ctx).colorScheme.primary),
                    ),
                    Expanded(
                      child: Text(line,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.progressImportAdd),
        ),
      ],
    ),
  );
  if (ok != true) return;

  try {
    await store.replace(result.merged, previous: local);
  } catch (_) {
    if (context.mounted) await _tell(context, l10n.progressImportFailed);
    return;
  }
  _refreshAfterImport(ref, result);
  messenger.showSnackBar(SnackBar(content: Text(l10n.progressImportDone)));
  if (context.mounted) await _offerHealth(context, ref, result.addedLogs);
}

/// After an import, when this device saves workouts to Apple Health / Health
/// Connect: offers to add the file's workouts there too, leaving out every
/// one at a time when the store already has a workout (owner, 2026-10-17).
Future<void> _offerHealth(
    BuildContext context, WidgetRef ref, List<WorkoutLog> added) async {
  final settings = ref.read(settingsProvider);
  if (kIsWeb || !settings.healthWorkoutsEnabled) return;
  final range = HealthImport.rangeOf(added);
  if (range == null) return;
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final store = defaultTargetPlatform == TargetPlatform.iOS
      ? 'Apple Health'
      : 'Health Connect';
  final count = added.where((l) => HealthImport.spanOf(l) != null).length;

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(l10n.progressHealthTitle(store)),
      content: Text(l10n.progressHealthBody(count, store)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(l10n.progressHealthNotNow),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: Text(l10n.progressImportAdd),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;

  final navigator = Navigator.of(context, rootNavigator: true);
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox.square(
                dimension: 24, child: CircularProgressIndicator()),
            const SizedBox(width: 16),
            Expanded(child: Text(l10n.progressHealthWorking(store))),
          ],
        ),
      ),
    ),
  ));
  final lines = await _addToHealth(added, range,
      readWeight: settings.healthWeightEnabled,
      l10n: l10n,
      store: store);
  navigator.pop();
  messenger.showSnackBar(SnackBar(content: Text(lines.join('\n'))));
}

/// Reads the workouts Health holds in [range], then writes the [added] ones
/// that overlap none of them; returns what to tell the user.
Future<List<String>> _addToHealth(
  List<WorkoutLog> added,
  TimeSpan range, {
  required bool readWeight,
  required AppLocalizations l10n,
  required String store,
}) async {
  final health = HealthService.instance;
  await health.requestWorkoutRead();
  var from = range.start;
  var inHealth = await health.workoutSpans(from, range.end);
  if (inHealth == null && defaultTargetPlatform == TargetPlatform.android) {
    // Health Connect on Android 13 and lower reads no further back than 30
    // days, and fails the whole read when asked for more.
    final limit = addCalendarDays(DateTime.now(), -30);
    if (limit.isAfter(from)) {
      from = limit;
      inHealth = await health.workoutSpans(from, range.end);
    }
  }
  if (inHealth == null) return [l10n.progressHealthFailed(store)];

  final plan = HealthImport.plan(added, inHealth, checkedFrom: from);
  final weightKg = WorkoutEnergy.resolveWeightKg(
      readWeight ? await health.readBodyWeight() : null);
  var written = 0;
  for (final log in plan.toWrite) {
    final span = HealthImport.spanOf(log)!;
    final course = log.courseIdIndex == null
        ? null
        : CourseId.values[log.courseIdIndex!];
    final kind = HealthWorkoutKind.of(course);
    final ok = await health.writeWorkout(
      start: span.start,
      end: span.end,
      calories: WorkoutEnergy.kcal(
          durationSec: log.durationSec, weightKg: weightKg, met: kind.met),
      kind: kind,
      title: healthWorkoutTitle(course, l10n),
    );
    if (ok) written++;
  }
  return healthResultLines(plan, written, l10n: l10n, store: store);
}

/// What adding the file's workouts to Health came to, in the user's words.
List<String> healthResultLines(
  HealthImportPlan plan,
  int written, {
  required AppLocalizations l10n,
  required String store,
}) =>
    [
      if (plan.toWrite.isNotEmpty && written == 0)
        l10n.progressHealthFailed(store)
      else if (written > 0)
        l10n.progressHealthDone(written, store)
      else if (plan.unchecked == 0)
        l10n.progressHealthAllThere(store),
      if (plan.unchecked > 0) l10n.progressHealthTooOld(plan.unchecked, store),
    ];

/// The lines of the confirmation: what the merge adds, in the user's words.
List<String> importSummaryLines(
    ProgressMergeSummary s, ProgressSnapshot merged, AppLocalizations l10n) {
  String branchName(String key) {
    for (final b in BranchId.values) {
      if (b.name == key) return b.localizedName(l10n);
    }
    for (final b in merged.branches) {
      if (key == CustomBranch.keyFor(b.id)) return b.name;
    }
    return key;
  }

  return [
    if (s.addedWorkouts > 0) l10n.progressImportWorkouts(s.addedWorkouts),
    if (s.addedSp > 0) l10n.progressImportSp(s.addedSp),
    if (s.rankTo != s.rankFrom)
      l10n.progressImportRank(
          s.rankFrom.localizedName(l10n), s.rankTo.localizedName(l10n)),
    if (s.streakTo != s.streakFrom)
      l10n.progressImportStreak(s.streakFrom, s.streakTo),
    if (s.bestStreakTo != s.bestStreakFrom)
      l10n.progressImportBestStreak(s.bestStreakFrom, s.bestStreakTo),
    for (final up in s.stageUps)
      l10n.progressImportStage(branchName(up.branchKey), up.stage),
    if (s.branchesMovedOn > 0) l10n.progressImportMovedOn(s.branchesMovedOn),
    if (s.newAchievementIds.isNotEmpty)
      l10n.progressImportAchievements(
        s.newAchievementIds.length,
        s.newAchievementIds.map((id) => AchievementL10n.name(l10n, id)).join(', '),
      ),
    if (s.addedOwn > 0) l10n.progressImportOwn(s.addedOwn),
  ];
}

/// After the boxes changed under the app: every provider that read them, the
/// home-screen widgets and the reminders (their plan follows the streak).
void _refreshAfterImport(WidgetRef ref, ProgressMergeResult result) {
  ref
    ..invalidate(displayStreakProvider)
    ..invalidate(homeDataProvider)
    ..invalidate(profileDataProvider)
    ..invalidate(customBranchesProvider)
    ..invalidate(customCoursesProvider)
    ..invalidate(customRoutinesProvider)
    ..invalidate(enrolledCoursesProvider)
    ..invalidate(activeCourseProvider)
    ..invalidate(seenReleaseVersionProvider)
    ..invalidate(settingsProvider);
  unawaited(ref.read(homeWidgetSyncProvider).push());
  unawaited(NotificationService.instance.scheduleAll(result.merged.profile));
}

Future<void> _tell(BuildContext context, String message) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(context.l10n.commonOk),
          ),
        ],
      ),
    );
