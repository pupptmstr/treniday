import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:health/health.dart';

import '../../domain/services/health_import.dart';
import '../../domain/services/health_workout.dart';
import '../../domain/services/workout_energy.dart';
import '../utils/calendar_days.dart';

/// Wraps the `health` package for writing workout sessions and active energy
/// to Apple Health (iOS) or Google Health Connect (Android).
class HealthService {
  HealthService._();
  static final instance = HealthService._();

  final _health = Health();

  /// Our own reader of Health Connect's exercise sessions
  /// (`MainActivity.kt`): the plugin reads a workout together with its
  /// distance, energy and steps, and without a read permission for those the
  /// whole read comes back empty — as if there were no workouts.
  static const _android = MethodChannel('treniday/health');

  bool get _isAndroid => defaultTargetPlatform == TargetPlatform.android;

  Future<void> configure() async {
    try {
      await _health.configure().timeout(const Duration(seconds: 5));
    } catch (_) {
      // Ignore timeout or errors — app continues without Health integration
    }
  }

  /// What TreniDay asks of Apple Health / Health Connect: writing workouts
  /// and their energy always, reading the body weight when [readWeight],
  /// reading workouts when [readWorkouts] (a progress file is checked against
  /// them).
  ///
  /// Every request asks for all of it: HealthKit keeps for a type only what
  /// the latest request asked for. A request to read workouts alone took their
  /// write permission away (0.9.11, found on the iOS simulator: "not write
  /// authorized" right after it), so the file's workouts could not be saved.
  @visibleForTesting
  static ({List<HealthDataType> types, List<HealthDataAccess> access})
      permissionsFor({required bool readWeight, required bool readWorkouts}) =>
          (
            types: [
              HealthDataType.WORKOUT,
              HealthDataType.TOTAL_CALORIES_BURNED,
              if (readWeight) HealthDataType.WEIGHT,
            ],
            access: [
              readWorkouts
                  ? HealthDataAccess.READ_WRITE
                  : HealthDataAccess.WRITE,
              HealthDataAccess.WRITE,
              if (readWeight) HealthDataAccess.READ,
            ],
          );

  /// Requests [permissionsFor]. Returns true if all were granted (on iOS:
  /// the sheet was answered; HealthKit never tells whether reading was).
  Future<bool> requestPermissions({
    bool readWeight = false,
    bool readWorkouts = false,
  }) async {
    final p = permissionsFor(readWeight: readWeight, readWorkouts: readWorkouts);
    try {
      return await _health.requestAuthorization(p.types, permissions: p.access);
    } catch (_) {
      return false;
    }
  }

  /// When the workouts of every app between [start] and [end] took place;
  /// null when they could not be read (then nothing may be added, or it could
  /// be added twice).
  Future<List<TimeSpan>?> workoutSpans(DateTime start, DateTime end) async {
    try {
      if (_isAndroid) {
        final spans = await _android.invokeListMethod<List<Object?>>(
          'exerciseSessions',
          {
            'start': start.millisecondsSinceEpoch,
            'end': end.millisecondsSinceEpoch,
          },
        );
        return spans
            ?.map((s) => (
                  start: DateTime.fromMillisecondsSinceEpoch(s[0] as int),
                  end: DateTime.fromMillisecondsSinceEpoch(s[1] as int),
                ))
            .toList();
      }
      final points = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WORKOUT],
        startTime: start,
        endTime: end,
      );
      return [for (final p in points) (start: p.dateFrom, end: p.dateTo)];
    } catch (_) {
      return null;
    }
  }

  /// Writes a workout session of [kind] with calorie data; [title] names it
  /// in Health Connect (Apple Health shows no names).
  Future<bool> writeWorkout({
    required DateTime start,
    required DateTime end,
    required double calories,
    required HealthWorkoutKind kind,
    String? title,
  }) async {
    try {
      return await _health.writeWorkoutData(
        activityType: _activityType(kind),
        title: title,
        start: start,
        end: end,
        totalEnergyBurned: calories.round(),
        totalEnergyBurnedUnit: HealthDataUnit.KILOCALORIE,
      );
    } catch (_) {
      return false;
    }
  }

  /// Each platform's type for [kind]. Until 0.9.11 every workout was
  /// "traditional strength training", which only iOS has: on Android the
  /// plugin refused it, and no workout ever reached Health Connect.
  HealthWorkoutActivityType _activityType(HealthWorkoutKind kind) => _isAndroid
      ? switch (kind) {
          HealthWorkoutKind.yoga => HealthWorkoutActivityType.YOGA,
          HealthWorkoutKind.strength ||
          HealthWorkoutKind.flexibility =>
            HealthWorkoutActivityType.CALISTHENICS,
        }
      : switch (kind) {
          HealthWorkoutKind.strength =>
            HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
          HealthWorkoutKind.flexibility => HealthWorkoutActivityType.FLEXIBILITY,
          HealthWorkoutKind.yoga => HealthWorkoutActivityType.YOGA,
        };

  /// Reads the most recent body-weight measurement (within last 90 days).
  /// Returns null if no data is available or permission is not granted.
  /// Which sample wins is [WorkoutEnergy.latestWeightKg]'s call.
  Future<double?> readBodyWeight() async {
    try {
      final now = DateTime.now();
      final data = await _health.getHealthDataFromTypes(
        startTime: addCalendarDays(now, -90),
        endTime: now,
        types: [HealthDataType.WEIGHT],
      );
      return WorkoutEnergy.latestWeightKg(data.map((p) {
        final v = p.value;
        return (
          at: p.dateFrom,
          kg: v is NumericHealthValue ? v.numericValue.toDouble() : null,
        );
      }));
    } catch (_) {
      return null;
    }
  }
}
