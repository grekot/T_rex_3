import 'package:flutter/material.dart';

import '../controllers/thermostat_controller.dart';
import '../models/schedule.dart';
import '../models/set_values.dart';
import '../models/thermostat_config.dart';
import 'device_admin_section.dart';
import 'format.dart';
import 'widgets.dart';

/// Ustawienia: nazwa, histerezy, ekran, próg ciemności, pogoda.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.controller});

  final ThermostatController controller;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  ThermostatController get c => widget.controller;

  late ThermostatConfig _base;
  final _name = TextEditingController();
  final _apiKey = TextEditingController();
  final _lat = TextEditingController();
  final _lon = TextEditingController();
  late double _hystLow;
  late double _hystHigh;
  late ScreenMode _screenMode;
  late int _timeoutMin;
  late bool _nightOn;
  late DayTime _nightStart;
  late DayTime _nightEnd;
  late int _darkLux;

  /// `frost.temp`: 0 = wyłączona.
  late double _frostTemp;

  /// `frost.faultDutyMin`: 0 = przy awarii piec stoi.
  late int _faultDuty;
  bool _showKey = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  @override
  void initState() {
    super.initState();
    _reset(c.config!);
    for (final t in [_name, _apiKey, _lat, _lon]) {
      t.addListener(() => setState(() {}));
    }
    c.addListener(_onController);
  }

  @override
  void dispose() {
    c.removeListener(_onController);
    for (final t in [_name, _apiKey, _lat, _lon]) {
      t.dispose();
    }
    super.dispose();
  }

  void _onController() {
    final cfg = c.config;
    if (cfg == null || cfg == _base) return;
    setState(() {
      if (_dirty) {
        _base = cfg;
      } else {
        _reset(cfg);
      }
    });
  }

  void _reset(ThermostatConfig cfg) {
    _base = cfg;
    _name.text = cfg.name;
    _apiKey.text = '';
    _lat.text = cfg.weather.lat;
    _lon.text = cfg.weather.lon;
    _hystLow = cfg.hystLow;
    _hystHigh = cfg.hystHigh;
    _screenMode = cfg.screen.mode;
    _timeoutMin = cfg.screen.timeoutMin;
    _darkLux = cfg.light.darkLux;
    _frostTemp = cfg.frost.temp;
    _faultDuty = cfg.frost.faultDutyMin;
    TimePeriod? night;
    try {
      night = NightPeriod.parse(cfg.screen.night);
    } on FormatException {
      night = null;
    }
    _nightOn = night != null;
    _nightStart = night?.start ?? DayTime.hm(23, 0);
    _nightEnd = night?.end ?? DayTime.hm(6, 0);
  }

  String get _nightText => _nightOn ? TimePeriod(_nightStart, _nightEnd).format() : '-';

  String get _baseNightText {
    try {
      return NightPeriod.format(NightPeriod.parse(_base.screen.night));
    } on FormatException {
      return _base.screen.night;
    }
  }

  static bool _same(double a, double b) => (a - b).abs() < 1e-6;

  SetValues get _changes {
    final name = _name.text.trim();
    final lat = _lat.text.trim();
    final lon = _lon.text.trim();
    final key = _apiKey.text.trim();
    return SetValues(
      name: name != _base.name ? name : null,
      hystLow: _same(_hystLow, _base.hystLow) ? null : _hystLow,
      hystHigh: _same(_hystHigh, _base.hystHigh) ? null : _hystHigh,
      screen: ScreenPatch(
        mode: _screenMode != _base.screen.mode ? _screenMode : null,
        timeoutMin: _timeoutMin != _base.screen.timeoutMin ? _timeoutMin : null,
        night: _nightText != _baseNightText ? _nightText : null,
      ),
      darkLux: _darkLux != _base.light.darkLux ? _darkLux : null,
      frostTemp: _same(_frostTemp, _base.frost.temp) ? null : _frostTemp,
      frostFaultDutyMin: _faultDuty != _base.frost.faultDutyMin ? _faultDuty : null,
      weather: WeatherPatch(
        apiKey: key.isEmpty ? null : key,
        lat: lat != _base.weather.lat ? lat : null,
        lon: lon != _base.weather.lon ? lon : null,
      ),
    );
  }

  bool get _dirty => !_changes.isEmpty;

  /// Walidacja po stronie telefonu; ostateczne słowo ma termostat (`errors`).
  Map<String, String> get _localErrors {
    final e = <String, String>{};
    final name = _name.text.trim();
    if (name.isEmpty) e['name'] = 'Podaj nazwę';
    if (name.length > maxNameLength) e['name'] = 'Najwyżej $maxNameLength znaki';
    String? coord(String text, int limit) {
      final t = text.trim();
      if (t.isEmpty) return null;
      final v = double.tryParse(t);
      if (v == null || v.abs() > limit || t.length > 12) return 'Liczba od −$limit do $limit, najwyżej 12 znaków';
      return null;
    }

    final latErr = coord(_lat.text, 90);
    if (latErr != null) e['weather.lat'] = latErr;
    final lonErr = coord(_lon.text, 180);
    if (lonErr != null) e['weather.lon'] = lonErr;
    if (_apiKey.text.trim().length > 64) e['weather.apiKey'] = 'Najwyżej 64 znaki';
    if (_nightOn && _nightStart == _nightEnd) e['screen.night'] = 'Początek i koniec muszą się różnić';
    return e;
  }

  String? _err(String key) {
    final local = _localErrors[key];
    if (local != null) return local;
    final remote = _errors[key];
    return remote == null ? null : 'Termostat: ${describeErrorCode(remote)}';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final r = await c.send(_changes);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _errors = r.errors;
      if (r.errors.isEmpty && c.config != null) _reset(c.config!);
    });
    showSaveResult(context, r.errors, describeErrors);
  }

  Future<void> _pickNight(bool start) async {
    final t = await pickDayTime(
      context,
      start ? _nightStart : _nightEnd,
      help: start ? 'Początek pory nocnej' : 'Koniec pory nocnej',
    );
    if (t == null) return;
    setState(() {
      if (start) {
        _nightStart = DayTime(t.minutes % 1440);
      } else {
        _nightEnd = DayTime(t.minutes % 1440);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canSave = _dirty && _localErrors.isEmpty && !_saving;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ustawienia'),
        actions: [
          TextButton(
            key: const Key('saveSettings'),
            onPressed: canSave ? _save : null,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Zapisz'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextField(
              key: const Key('name'),
              controller: _name,
              maxLength: maxNameLength,
              decoration: InputDecoration(labelText: 'Nazwa termostatu', errorText: _err('name')),
            ),
          ),

          const SectionHeader('Histereza'),
          _slider(
            label: 'Dolna',
            help: 'Grzanie włącza się poniżej nastawy minus ta wartość',
            value: _hystLow,
            errorKey: 'hystLow',
            onChanged: (v) => setState(() => _hystLow = v),
          ),
          _slider(
            label: 'Górna',
            help: 'Grzanie wyłącza się powyżej nastawy plus ta wartość',
            value: _hystHigh,
            errorKey: 'hystHigh',
            onChanged: (v) => setState(() => _hystHigh = v),
          ),

          const SectionHeader('Ekran'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<ScreenMode>(
              segments: const [
                ButtonSegment(value: ScreenMode.always, label: Text('Zawsze włączony')),
                ButtonSegment(value: ScreenMode.motion, label: Text('Po wykryciu ruchu')),
              ],
              selected: {_screenMode},
              onSelectionChanged: (s) => setState(() => _screenMode = s.single),
            ),
          ),
          if (_err('screen.mode') != null) _errorLine(_err('screen.mode')!, cs),
          StepperTile(
            label: 'Wygaszanie po',
            subtitle: _screenMode == ScreenMode.motion
                ? 'Minuty bez ruchu do zgaszenia ekranu'
                : 'Działa w trybie „po wykryciu ruchu”',
            value: _timeoutMin.toDouble(),
            min: 1,
            max: maxScreenTimeoutMin.toDouble(),
            step: 1,
            format: (v) => '${v.round()} min',
            errorText: _err('screen.timeoutMin'),
            onChanged: (v) => setState(() => _timeoutMin = v.round()),
          ),
          SwitchListTile(
            title: const Text('Pora nocna'),
            subtitle: const Text('Przyciemniony ekran w nocy'),
            value: _nightOn,
            onChanged: (v) => setState(() => _nightOn = v),
          ),
          if (_nightOn)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(onPressed: () => _pickNight(true), child: Text('Od ${_nightStart.format()}')),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton(onPressed: () => _pickNight(false), child: Text('Do ${_nightEnd.format()}')),
                  ),
                ],
              ),
            ),
          if (_err('screen.night') != null) _errorLine(_err('screen.night')!, cs),

          const SectionHeader('Czujnik światła'),
          ListTile(
            title: const Text('Próg ciemności'),
            subtitle: const Text('Poniżej tej jasności pomieszczenie uznawane jest za ciemne'),
            trailing: Text('$_darkLux lx', style: Theme.of(context).textTheme.titleMedium),
          ),
          Slider(
            value: _darkLux.toDouble(),
            min: 1,
            max: 50,
            divisions: 49,
            label: '$_darkLux lx',
            onChanged: (v) => setState(() => _darkLux = v.round()),
          ),
          if (_err('light.darkLux') != null) _errorLine(_err('light.darkLux')!, cs),

          const SectionHeader('Ochrona przed zamarzaniem'),
          SwitchListTile(
            key: const Key('frostOn'),
            title: const Text('Pilnuj najniższej temperatury'),
            subtitle: const Text(
              'Zawsze, także gdy system jest wyłączony (OFF) albo nastawa jest niższa - chroni instalację przed mrozem.',
            ),
            value: _frostTemp > 0,
            onChanged: (on) => setState(() => _frostTemp = on ? (_base.frost.temp > 0 ? _base.frost.temp : 7) : 0),
          ),
          if (_frostTemp > 0) ...[
            ListTile(
              title: const Text('Najniższa temperatura'),
              trailing: Text(fmtTemp(_frostTemp), style: Theme.of(context).textTheme.titleMedium),
            ),
            Slider(
              key: const Key('frostTemp'),
              value: _frostTemp.clamp(4, 12),
              min: 4,
              max: 12,
              divisions: 16,
              label: fmtTemp(_frostTemp),
              onChanged: (v) => setState(() => _frostTemp = (v * 2).round() / 2),
            ),
          ],
          if (_err('frost.temp') != null) _errorLine(_err('frost.temp')!, cs),
          SwitchListTile(
            key: const Key('faultDutyOn'),
            title: const Text('Grzej cyklicznie przy awarii czujnika'),
            subtitle: const Text(
              'Bez czujnika termostat nie zna temperatury. Gdy na zewnątrz jest poniżej 5 °C (albo brak pogody), '
              'grzeje wtedy co godzinę przez ustawiony czas. Wyłączone: przy awarii piec stoi.',
            ),
            value: _faultDuty > 0,
            onChanged: (on) => setState(() => _faultDuty = on ? (_base.frost.faultDutyMin > 0 ? _base.frost.faultDutyMin : 10) : 0),
          ),
          if (_faultDuty > 0) ...[
            ListTile(
              title: const Text('Grzanie na godzinę'),
              trailing: Text('$_faultDuty min', style: Theme.of(context).textTheme.titleMedium),
            ),
            Slider(
              key: const Key('faultDuty'),
              value: _faultDuty.clamp(5, 20).toDouble(),
              min: 5,
              max: 20,
              divisions: 15,
              label: '$_faultDuty min',
              onChanged: (v) => setState(() => _faultDuty = v.round()),
            ),
          ],
          if (_err('frost.faultDutyMin') != null) _errorLine(_err('frost.faultDutyMin')!, cs),

          const SectionHeader('Pogoda (OpenWeatherMap)'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                TextField(
                  controller: _apiKey,
                  obscureText: !_showKey,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Klucz API',
                    helperText: _base.weather.apiKeySet
                        ? 'Klucz jest zapisany w termostacie. Zostaw puste, aby go nie zmieniać.'
                        : 'Brak klucza - pogoda nie działa.',
                    helperMaxLines: 2,
                    errorText: _err('weather.apiKey'),
                    suffixIcon: IconButton(
                      icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _showKey = !_showKey),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _lat,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: InputDecoration(labelText: 'Szerokość (lat)', errorText: _err('weather.lat')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _lon,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        decoration: InputDecoration(labelText: 'Długość (lon)', errorText: _err('weather.lon')),
                      ),
                    ),
                  ],
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('Stopnie dziesiętne z kropką, np. 50.06 i 19.94'),
                  ),
                ),
              ],
            ),
          ),

          DeviceAdminSection(controller: c, cloudLinked: c.state?.cloud ?? false, uptime: c.state?.uptime),
        ],
      ),
    );
  }

  Widget _slider({
    required String label,
    required String help,
    required double value,
    required String errorKey,
    required ValueChanged<double> onChanged,
  }) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          title: Text(label),
          subtitle: Text(help),
          trailing: Text('${fmtNumber(value)} °C', style: Theme.of(context).textTheme.titleMedium),
        ),
        Slider(
          value: value.clamp(0, 1),
          min: 0,
          max: 1,
          divisions: 10,
          label: '${fmtNumber(value)} °C',
          onChanged: (v) => onChanged((v * 10).round() / 10),
        ),
        if (_err(errorKey) != null) _errorLine(_err(errorKey)!, cs),
      ],
    );
  }

  Widget _errorLine(String text, ColorScheme cs) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: Text(text, style: TextStyle(color: cs.error)),
  );
}
