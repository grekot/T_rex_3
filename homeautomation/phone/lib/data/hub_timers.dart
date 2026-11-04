import '../controllers/device_controller.dart';
import '../models/hub_timer.dart';
import '../models/json_utils.dart';
import 'errors.dart';
import 'hub_api.dart';

/// Odliczanie w hubie (pkt 11): w domu `POST /api/timers` / `DELETE /api/timers/{id}`, poza domem Set huba
/// `timerAdd` / `timerCancel` przez chmurę. Hub sprawdza mój poziom dla urządzenia (najwyżej `control`).
class HubTimers {
  HubTimers(this.hub, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// Kontroler huba (lokalnie albo przez chmurę).
  final DeviceController<Object?, Object?> hub;
  final DateTime Function() _clock;

  /// Hub ma timery (pole `timers` w State) - inaczej opcji nie pokazujemy.
  bool get supported => hubTimers(hub.stateJson) != null;

  /// Timery z State huba (posortowane po czasie); pusta lista, gdy hub ich nie obsługuje.
  List<HubTimer> get all => hubTimers(hub.stateJson) ?? const [];

  List<HubTimer> forDevice(String device) => [
    for (final t in all)
      if (t.device == device) t,
  ];

  /// Set [values] urządzenia [device] za [after]; zwraca przewidywaną chwilę wykonania.
  /// Rzuca [ThermostatException] (także [HubTimerException] z kodem błędu huba).
  Future<DateTime> add(String device, Json values, Duration after) async {
    final local = hub.localApi;
    if (local != null) return (await HubApi(local).addTimer(device, values, after.inSeconds)).at ?? _clock().add(after);
    final r = await hub.sendJson({
      'timerAdd': {'device': device, 'set': values, 'in': after.inSeconds},
    });
    _check(r.errors, 'timerAdd');
    return _clock().add(after);
  }

  Future<void> cancel(String id) async {
    final local = hub.localApi;
    if (local != null) return HubApi(local).cancelTimer(id);
    final r = await hub.sendJson({'timerCancel': id});
    _check(r.errors, 'timerCancel');
  }

  static void _check(Map<String, String> errors, String field) {
    final code = errors[field];
    if (code != null) throw HubTimerException(code);
    if (errors.isNotEmpty) throw ThermostatException(errors.values.first);
  }
}
