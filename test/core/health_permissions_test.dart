import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:treniday/core/services/health_service.dart';

void main() {
  // HealthKit keeps for a type only what the latest request asked for: a
  // request to read workouts alone took their write permission away (0.9.11).
  test('every request keeps writing workouts and their energy', () {
    for (final readWeight in [false, true]) {
      for (final readWorkouts in [false, true]) {
        final p = HealthService.permissionsFor(
            readWeight: readWeight, readWorkouts: readWorkouts);
        expect(p.types, hasLength(p.access.length));
        final workout = p.access[p.types.indexOf(HealthDataType.WORKOUT)];
        expect(workout,
            readWorkouts ? HealthDataAccess.READ_WRITE : HealthDataAccess.WRITE,
            reason: 'readWorkouts: $readWorkouts');
        expect(p.access[p.types.indexOf(HealthDataType.TOTAL_CALORIES_BURNED)],
            HealthDataAccess.WRITE);
        expect(p.types.contains(HealthDataType.WEIGHT), readWeight);
        if (readWeight) {
          expect(p.access[p.types.indexOf(HealthDataType.WEIGHT)],
              HealthDataAccess.READ);
        }
      }
    }
  });
}
