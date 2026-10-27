import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/discovery.dart';
import '../data/errors.dart';
import '../data/local_endpoint.dart';
import '../models/device_info.dart';
import '../models/device_type.dart';
import '../services.dart';
import 'format.dart';

/// Parowanie: wybór termostatu (mDNS albo adres ręcznie) → kod z ekranu termostatu → token.
/// Zwraca sparowane urządzenie przez `Navigator.pop`.
class PairingScreen extends StatefulWidget {
  const PairingScreen({super.key, this.initialEndpoint});

  /// Przy ponownym parowaniu znanego urządzenia: od razu ten adres.
  final LocalEndpoint? initialEndpoint;

  @override
  State<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends State<PairingScreen> {
  StreamSubscription<List<DiscoveredDevice>>? _discoverySub;
  List<DiscoveredDevice> _found = const [];
  String? _discoveryError;

  LocalEndpoint? _endpoint;
  DeviceInfo? _info;
  bool _busy = false;
  String? _error;

  /// Z kontem: urządzenie najpierw daje `view`, potem poziom z uprawnień domu (pkt 2).
  String? _accessNote;

  // Etap kodu.
  DateTime? _expires;
  Timer? _ticker;
  final _code = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_discoverySub == null) {
      _discoverySub = Services.of(context).discovery.watch().listen(
        (l) => setState(() => _found = l),
        onError: (Object e) => setState(() => _discoveryError = 'Wyszukiwanie w sieci nie działa: $e'),
      );
      final initial = widget.initialEndpoint;
      if (initial != null) scheduleMicrotask(() => _select(initial));
    }
  }

  @override
  void dispose() {
    _discoverySub?.cancel();
    _ticker?.cancel();
    _code.dispose();
    super.dispose();
  }

  Future<void> _select(LocalEndpoint endpoint) async {
    final pairing = Services.of(context).pairing;
    setState(() {
      _busy = true;
      _error = null;
      _endpoint = endpoint;
    });
    try {
      final info = await pairing.probe(endpoint);
      final validity = await pairing.start(endpoint);
      _code.clear();
      setState(() {
        _info = info;
        _expires = DateTime.now().add(validity);
      });
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    } on ThermostatException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Urządzenie bez ekranu: kodem jest PoP z naklejki (8 znaków, pkt 2).
  bool get _popCode => _info?.pair == PairMethod.pop;
  int get _codeLength => _popCode ? 8 : 6;

  Future<void> _confirm() async {
    final code = _popCode ? _code.text.trim().toLowerCase() : _code.text.trim();
    if (code.length != _codeLength) {
      setState(() => _error = _popCode ? 'Kod z naklejki ma 8 znaków.' : 'Kod ma 6 cyfr.');
      return;
    }
    final pairing = Services.of(context).pairing;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final device = await pairing.confirm(
        _endpoint!,
        _info!,
        code,
        onAccess: (level) {
          if (mounted) setState(() => _accessNote = 'Sparowano (${level.label}). Sprawdzanie uprawnień konta…');
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(device);
    } on PairingException catch (e) {
      setState(() {
        _error = e.message;
        // Po wygaśnięciu albo 3 złych próbach trzeba zacząć od nowa.
        if (e.mustRestart) _expires = DateTime.now();
      });
      _code.clear();
    } on ThermostatException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    _ticker?.cancel();
    setState(() {
      _info = null;
      _endpoint = null;
      _expires = null;
      _error = null;
    });
  }

  Future<void> _manual() async {
    final controller = TextEditingController();
    final result = await showDialog<LocalEndpoint>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setLocal) {
            void submit() {
              final e = LocalEndpoint.tryParse(controller.text);
              if (e == null) {
                setLocal(() => error = 'Podaj adres, np. 192.168.1.20 albo 192.168.1.20:8080');
              } else if (!isLocalNetworkHost(e.host)) {
                setLocal(() => error = 'To nie jest adres sieci lokalnej.');
              } else {
                Navigator.pop(ctx, e);
              }
            }

            return AlertDialog(
              title: const Text('Adres urządzenia'),
              content: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.url,
                decoration: InputDecoration(
                  hintText: '192.168.1.20',
                  helperText: 'Adres IP z ekranu urządzenia albo z routera',
                  errorText: error,
                ),
                onSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Anuluj')),
                FilledButton(onPressed: submit, child: const Text('Połącz')),
              ],
            );
          },
        );
      },
    );
    // Bez dispose(): okno jeszcze się animuje i używa kontrolera (zwolni go GC).
    if (result != null) await _select(result);
  }

  @override
  Widget build(BuildContext context) {
    final inCodeStep = _info != null;
    return PopScope(
      canPop: !inCodeStep,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Parowanie kodem')),
        body: inCodeStep ? _codeStep(context) : _chooseStep(context),
      ),
    );
  }

  Widget _chooseStep(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Telefon musi być w tej samej sieci Wi-Fi co urządzenie. Wybierz je z listy - '
            'na jego ekranie pojawi się kod do przepisania.',
            style: t.bodyMedium,
          ),
        ),
        ListTile(
          leading: _found.isEmpty && !kIsWeb
              ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.wifi_find),
          title: Text(
            kIsWeb
                ? 'Wyszukiwanie w sieci niedostępne w przeglądarce'
                : _found.isEmpty
                ? 'Szukam urządzeń w sieci…'
                : 'Znalezione w sieci',
          ),
          subtitle: _discoveryError == null ? null : Text(_discoveryError!),
        ),
        for (final d in _found)
          ListTile(
            leading: CircleAvatar(
              child: Icon(d.type == DeviceType.thermostat ? Icons.thermostat : Icons.lightbulb_outline),
            ),
            title: Text(d.id),
            subtitle: Text([d.endpoint.display, if (d.fw != null) 'fw ${d.fw}'].join(' · ')),
            trailing: _busy && _endpoint == d.endpoint
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            enabled: !_busy,
            onTap: () => _select(d.endpoint),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('Wpisz adres ręcznie'),
          subtitle: const Text('Gdy urządzenia nie widać na liście'),
          enabled: !_busy,
          onTap: _manual,
        ),
        if (_busy && !_found.any((d) => d.endpoint == _endpoint))
          const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
        if (_error != null) _ErrorText(_error!),
      ],
    );
  }

  Widget _codeStep(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final left = _expires!.difference(DateTime.now());
    final expired = left.isNegative || left == Duration.zero;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Icon(Icons.pin, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 16),
        Text('Przepisz kod z urządzenia', style: t.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(
          _popCode
              ? 'Urządzenie „${_info!.name}” (${_info!.id}) nie ma ekranu - wpisz 8 znaków kodu z jego naklejki '
                    '(ten sam co przy dodawaniu).'
              : 'Na ekranie urządzenia „${_info!.name}” (${_info!.id}) widać napis PAROWANIE i 6 cyfr.',
          style: t.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _code,
          autofocus: true,
          enabled: !expired && !_busy,
          key: const Key('pairCode'),
          keyboardType: _popCode ? TextInputType.visiblePassword : TextInputType.number,
          autocorrect: false,
          enableSuggestions: false,
          textAlign: TextAlign.center,
          maxLength: _codeLength,
          style: t.headlineMedium?.copyWith(
            letterSpacing: _popCode ? 6 : 12,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
          inputFormatters: [
            _popCode ? FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')) : FilteringTextInputFormatter.digitsOnly,
          ],
          decoration: InputDecoration(
            hintText: _popCode ? 'ab12cd34' : '000000',
            counterText: '',
            border: const OutlineInputBorder(),
          ),
          onChanged: (v) {
            if (v.length == _codeLength) _confirm();
          },
          onSubmitted: (_) => _confirm(),
        ),
        const SizedBox(height: 8),
        Text(
          expired ? 'Kod wygasł.' : 'Kod ważny jeszcze ${fmtDuration(left)}',
          textAlign: TextAlign.center,
          style: t.bodySmall,
        ),
        if (_error != null) _ErrorText(_error!),
        const SizedBox(height: 16),
        if (expired)
          FilledButton.icon(
            onPressed: _busy ? null : () => _select(_endpoint!),
            icon: const Icon(Icons.refresh),
            label: const Text('Pokaż nowy kod'),
          )
        else
          FilledButton(
            onPressed: _busy ? null : _confirm,
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sparuj'),
          ),
        if (_busy && _accessNote != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_accessNote!, key: const Key('accessNote'), textAlign: TextAlign.center),
          ),
        TextButton(onPressed: _busy ? null : _back, child: const Text('Wybierz inne urządzenie')),
      ],
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: c.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(text, style: TextStyle(color: c.error)),
          ),
        ],
      ),
    );
  }
}
