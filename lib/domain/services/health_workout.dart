import '../../data/models/enums.dart';
import '../../l10n/app_localizations.dart';
import 'workout_energy.dart';

/// What a workout is in Apple Health / Health Connect, by its course (owner,
/// 2026-10-17: "different types depending on the course"), and the MET its
/// calories are counted with (Compendium of Physical Activities).
/// `HealthService` turns it into each platform's activity type.
enum HealthWorkoutKind {
  /// Calisthenics, own courses and routines: strength with the body's weight
  /// (Apple Health "functional strength training", Health Connect
  /// "calisthenics").
  strength(WorkoutEnergy.strengthMet),

  /// Healthy Body, Evening Stretch, Morning Routine: mobility and stretching
  /// (Apple Health "flexibility"; Health Connect has a stretching type, but
  /// the health plugin cannot write it, so "calisthenics" with the course in
  /// the title). "Stretching, mild": 2.3.
  flexibility(2.3),

  /// Yoga on both platforms. "Yoga, Hatha": 2.5.
  yoga(2.5);

  const HealthWorkoutKind(this.met);

  final double met;

  /// The kind of a workout of [course]; null (an own course or routine) is
  /// strength, like Calisthenics.
  static HealthWorkoutKind of(CourseId? course) => switch (course) {
        CourseId.yoga => yoga,
        CourseId.healthyBody ||
        CourseId.eveningStretch ||
        CourseId.morningRoutine =>
          flexibility,
        CourseId.calisthenics || null => strength,
      };
}

/// The name of a workout of [course] in Health Connect ("TreniDay · Yoga");
/// Apple Health shows no names, only the kind.
String healthWorkoutTitle(CourseId? course, AppLocalizations l10n) =>
    course == null ? 'TreniDay' : 'TreniDay · ${course.localizedName(l10n)}';
