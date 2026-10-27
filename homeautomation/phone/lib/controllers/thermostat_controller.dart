import 'dart:async';

import '../models/set_values.dart';
import '../models/thermostat_config.dart';
import '../models/thermostat_state.dart';
import 'device_controller.dart';

export 'device_controller.dart' show ConnectPhase, DeviceController;
export 'field_errors.dart';

/// Zakres i krok nastawy wg kontraktu (pkt 7).
const targetMin = 15.0;
const targetMax = 30.0;
const targetStep = 0.5;

/// Limity z firmware (src/Control.cpp).
const maxNameLength = 24;
const maxScreenTimeoutMin = 30;

/// Termostat: wspólna obsługa urządzenia + nastawa ±0,5 °C z łączeniem kliknięć.
class ThermostatController extends DeviceController<ThermostatState, ThermostatConfig> {
  ThermostatController({
    required super.device,
    required super.manager,
    this.targetDebounce = const Duration(milliseconds: 600),
  }) : super(codec: thermostatCodec);

  final Duration targetDebounce;

  double? _pendingTarget;
  Timer? _targetTimer;

  /// Nastawa do pokazania: ta zmieniana właśnie przyciskami albo ta z termostatu.
  double? get displayTarget => _pendingTarget ?? state?.target;
  bool get targetPending => _pendingTarget != null;

  @override
  void onState(ThermostatState state) {
    // Gdy termostat potwierdzi wysłaną nastawę, przestajemy pokazywać lokalną.
    if (_pendingTarget != null && _targetTimer == null && state.target == _pendingTarget) {
      _pendingTarget = null;
    }
  }

  /// +/− 0,5 °C. Kolejne kliknięcia sumują się, wysyłamy po chwili bezczynności.
  void stepTarget(double delta) {
    final current = displayTarget;
    if (current == null) return;
    final next = ((current + delta) / targetStep).round() * targetStep;
    _pendingTarget = next.clamp(targetMin, targetMax);
    _targetTimer?.cancel();
    _targetTimer = Timer(targetDebounce, _flushTarget);
    notifyChanged();
  }

  Future<void> _flushTarget() async {
    _targetTimer = null;
    final t = _pendingTarget;
    if (t == null) return;
    final result = await send(SetValues(target: t));
    if (!result.ok || result.errors.isNotEmpty || state?.target == t) {
      _pendingTarget = null;
      notifyChanged();
    }
  }

  Future<SetResult> setMode(ThermostatMode mode) => send(SetValues(mode: mode));

  Future<SetResult> setPower(bool on) => send(SetValues(power: on));

  /// Wysyła dowolną zmianę termostatu. Nie rzuca - błąd łącza wraca jako `ok:false` z `errors['_']`.
  Future<SetResult> send(SetValues values) => sendJson(values.toJson());

  @override
  void dispose() {
    _targetTimer?.cancel();
    super.dispose();
  }
}
