import 'package:flutter_test/flutter_test.dart';
import 'package:treniday/data/models/enums.dart';
import 'package:treniday/data/models/workout_log.dart';
import 'package:treniday/domain/services/health_import.dart';
import 'package:treniday/domain/services/health_workout.dart';
import 'package:treniday/domain/services/workout_energy.dart';

import '../../helpers/all_translations.dart';

/// A workout that ended at [hour]:[minute] on 2026-10-[day] after [minutes].
WorkoutLog ended(int day, int hour, {int minute = 0, int minutes = 20}) =>
    WorkoutLog(
      date: DateTime(2026, 10, day, hour, minute),
      setType: SetType.daily,
      exercises: const [],
      spEarned: 100,
      durationSec: minutes * 60,
    );

TimeSpan span(int day, int fromHour, int fromMinute, int toHour, int toMinute) =>
    (
      start: DateTime(2026, 10, day, fromHour, fromMinute),
      end: DateTime(2026, 10, day, toHour, toMinute),
    );

void main() {
  group('HealthImport', () {
    test('a workout took place before the moment it ended', () {
      final s = HealthImport.spanOf(ended(5, 9))!;
      expect(s.start, DateTime(2026, 10, 5, 8, 40));
      expect(s.end, DateTime(2026, 10, 5, 9));
    });

    test('a workout without a length has no time (the debug screen\'s)', () {
      expect(HealthImport.spanOf(ended(5, 9, minutes: 0)), isNull);
    });

    test('the range to read covers every workout', () {
      final r = HealthImport.rangeOf([ended(7, 9), ended(3, 20), ended(5, 9)])!;
      expect(r.start, DateTime(2026, 10, 3, 19, 40));
      expect(r.end, DateTime(2026, 10, 7, 9));
      expect(HealthImport.rangeOf([ended(1, 9, minutes: 0)]), isNull);
    });

    test('a workout at a time when Health has one is left out, of any app', () {
      final morning = ended(5, 9); // 8:40–9:00
      final evening = ended(5, 20); // 19:40–20:00
      final plan = HealthImport.plan(
        [morning, evening],
        [span(5, 8, 50, 9, 30)], // a watch's workout over the end of it
        checkedFrom: DateTime(2026, 10, 1),
      );
      expect(plan.toWrite, [evening]);
      expect(plan.unchecked, 0);
    });

    test('a workout just before or after one in Health is written', () {
      final w = ended(5, 9); // 8:40–9:00
      final plan = HealthImport.plan(
        [w],
        [span(5, 9, 0, 9, 30), span(5, 8, 0, 8, 40)],
        checkedFrom: DateTime(2026, 10, 1),
      );
      expect(plan.toWrite, [w]);
    });

    test('a workout inside or around one in Health is left out', () {
      expect(
          HealthImport.plan([ended(5, 9)], [span(5, 8, 45, 8, 50)],
                  checkedFrom: DateTime(2026, 10, 1))
              .toWrite,
          isEmpty);
      expect(
          HealthImport.plan([ended(5, 9)], [span(5, 8, 0, 10, 0)],
                  checkedFrom: DateTime(2026, 10, 1))
              .toWrite,
          isEmpty);
    });

    test('workouts older than the store lets the app check are left out', () {
      final old = ended(2, 9);
      final recent = ended(20, 9);
      final plan = HealthImport.plan([old, recent], const [],
          checkedFrom: DateTime(2026, 10, 10));
      expect(plan.toWrite, [recent]);
      expect(plan.unchecked, 1);
    });
  });

  group('HealthWorkoutKind', () {
    test('by course: yoga, flexibility, strength', () {
      expect(HealthWorkoutKind.of(CourseId.yoga), HealthWorkoutKind.yoga);
      for (final c in [
        CourseId.healthyBody,
        CourseId.eveningStretch,
        CourseId.morningRoutine,
      ]) {
        expect(HealthWorkoutKind.of(c), HealthWorkoutKind.flexibility,
            reason: c.name);
      }
      expect(HealthWorkoutKind.of(CourseId.calisthenics),
          HealthWorkoutKind.strength);
      // An own course or routine.
      expect(HealthWorkoutKind.of(null), HealthWorkoutKind.strength);
    });

    test('yoga and stretching burn less than strength', () {
      expect(HealthWorkoutKind.strength.met, WorkoutEnergy.strengthMet);
      expect(HealthWorkoutKind.yoga.met, lessThan(WorkoutEnergy.strengthMet));
      expect(HealthWorkoutKind.flexibility.met,
          lessThan(WorkoutEnergy.strengthMet));
    });

    test('the title names the course in every language', () {
      for (final l10n in allTranslations) {
        expect(healthWorkoutTitle(CourseId.yoga, l10n),
            'TreniDay · ${CourseId.yoga.localizedName(l10n)}');
        expect(healthWorkoutTitle(null, l10n), 'TreniDay');
      }
    });
  });
}
