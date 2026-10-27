import 'dart:async';

import '../models/light.dart';
import '../models/set_values.dart';
import 'device_controller.dart';

/// Włącznik / ściemniacz (kontrakt pkt 10): wł./wył. od razu w UI, jasność wysyłana po chwili.
class LightController extends DeviceController<LightState, LightConfig> {
  LightController({
    required super.device,
    required super.manager,
    this.levelDebounce = const Duration(milliseconds: 300),
  }) : super(codec: lightCodec);

  final Duration levelDebounce;

  bool? _pendingOn;
  int? _pendingLevel;
  Timer? _levelTimer;

  /// Stan do pokazania: właśnie przełączony albo ten z urządzenia.
  bool? get displayOn => _pendingOn ?? state?.on;

  int? get displayLevel => _pendingLevel ?? state?.level;

  @override
  void onState(LightState state) {
    if (_pendingOn != null && state.on == _pendingOn) _pendingOn = null;
    if (_pendingLevel != null && _levelTimer == null && state.level == _pendingLevel) _pendingLevel = null;
  }

  Future<SetResult> setOn(bool on) async {
    _pendingOn = on;
    notifyChanged();
    final r = await sendJson(LightSet(on: on).toJson());
    if (!r.ok || state?.on == on) {
      _pendingOn = null;
      notifyChanged();
    }
    return r;
  }

  Future<SetResult> toggle() => setOn(!(displayOn ?? false));

  /// Jeden kanał przełącznika wielokanałowego (pkt 10.1, `onN`).
  Future<SetResult> setChannel(int channel, bool on) => sendJson(LightSet(channelOn: {channel: on}).toJson());

  /// Suwak: pokazujemy od razu, wysyłamy po [levelDebounce] bez ruchu.
  void setLevel(int level) {
    _pendingLevel = level.clamp(0, 100);
    _levelTimer?.cancel();
    _levelTimer = Timer(levelDebounce, () async {
      _levelTimer = null;
      final l = _pendingLevel;
      if (l == null) return;
      final r = await sendJson(LightSet(level: l).toJson());
      if (!r.ok || state?.level == l) {
        _pendingLevel = null;
        notifyChanged();
      }
    });
    notifyChanged();
  }

  Future<SetResult> send(LightSet values) => sendJson(values.toJson());

  @override
  void dispose() {
    _levelTimer?.cancel();
    super.dispose();
  }
}
