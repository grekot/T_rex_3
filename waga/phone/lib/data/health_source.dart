import 'package:flutter/foundation.dart';
import 'package:health/health.dart';

import 'activity.dart';

enum HealthState { checking, unavailable, needsInstall, needsPermission, ready }

/// Odczyt z Health Connect (tylko odczyt; dane zapisuje tam aplikacja Zepp:
/// Profil → Połącz z innymi aplikacjami → Health Connect).
class HealthSource {
  final Health _health = Health();
  bool _configured = false;

  // DISTANCE_DELTA jest potrzebne, bo plugin czyta dystans każdego treningu
  static const types = [
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.STEPS,
    HealthDataType.WORKOUT,
    HealthDataType.DISTANCE_DELTA,
  ];

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<HealthState> state() async {
    if (defaultTargetPlatform != TargetPlatform.android) return HealthState.unavailable;
    try {
      await _configure();
      final status = await _health.getHealthConnectSdkStatus();
      if (status == HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired) return HealthState.needsInstall;
      if (status != HealthConnectSdkStatus.sdkAvailable) return HealthState.needsInstall;
      final ok = await _health.hasPermissions(types) ?? false;
      return ok ? HealthState.ready : HealthState.needsPermission;
    } catch (e) {
      debugPrint('Health Connect: $e');
      return HealthState.unavailable;
    }
  }

  Future<void> install() => _health.installHealthConnect();

  /// Prośba o dostęp (+ do historii starszej niż 30 dni). true gdy dostęp jest.
  Future<bool> requestAccess() async {
    await _configure();
    final ok = await _health.requestAuthorization(types);
    if (!ok) return false;
    try {
      if (!await _health.isHealthDataHistoryAuthorized()) {
        await _health.requestHealthDataHistoryAuthorization();
      }
    } catch (_) {}
    return true;
  }

  Future<List<HealthDataPoint>> _read(HealthDataType type, DateTime from, DateTime to) async {
    try {
      return await _health.getHealthDataFromTypes(types: [type], startTime: from, endTime: to);
    } catch (e) {
      debugPrint('Health Connect $type: $e');
      return const [];
    }
  }

  List<Sample> _samples(List<HealthDataPoint> points) => [
        for (final p in points)
          if (p.value is NumericHealthValue)
            Sample(p.dateFrom, (p.value as NumericHealthValue).numericValue.toDouble(), p.sourceName),
      ];

  Future<ActivityData> load(DateTime from, DateTime to) async {
    await _configure();
    final results = await Future.wait([
      _read(HealthDataType.TOTAL_CALORIES_BURNED, from, to),
      _read(HealthDataType.ACTIVE_ENERGY_BURNED, from, to),
      _read(HealthDataType.STEPS, from, to),
      _read(HealthDataType.WORKOUT, from, to),
    ]);
    final workouts = <Workout>[];
    for (final p in results[3]) {
      final v = p.value;
      if (v is! WorkoutHealthValue) continue;
      workouts.add(Workout(
        start: p.dateFrom,
        end: p.dateTo,
        type: v.workoutActivityType.name,
        kcal: v.totalEnergyBurned?.toDouble(),
        distanceM: v.totalDistance?.toDouble(),
        steps: v.totalSteps?.toDouble(),
        source: p.sourceName,
      ));
    }
    return ActivityData.build(
      total: _samples(results[0]),
      active: _samples(results[1]),
      steps: _samples(results[2]),
      workouts: workouts,
    );
  }
}
