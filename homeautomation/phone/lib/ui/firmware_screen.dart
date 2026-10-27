import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../data/errors.dart';
import '../data/local_api.dart';

/// Etapy aktualizacji widoczne na ekranie.
enum _Phase { idle, uploading, restarting, done, failed }

/// „Aktualizacja firmware” (pkt 3a kontraktu): plik `.bin` z telefonu → `POST /api/ota`,
/// postęp z `GET /api/ota`, potem restart urządzenia i ponowne połączenie. Tylko lokalnie.
class FirmwareScreen extends StatefulWidget {
  const FirmwareScreen({super.key, required this.controller, this.pickFile});

  final DeviceController<Object?, Object?> controller;

  /// Do testów: zamiast systemowego wyboru pliku.
  final Future<({String name, Uint8List bytes})?> Function()? pickFile;

  @override
  State<FirmwareScreen> createState() => _FirmwareScreenState();
}

class _FirmwareScreenState extends State<FirmwareScreen> {
  DeviceController<Object?, Object?> get c => widget.controller;

  String? _currentFw;
  String? _fileName;
  Uint8List? _image;
  _Phase _phase = _Phase.idle;
  double _progress = 0;
  String? _message;
  String? _error;
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await c.localApi?.info();
      if (mounted) setState(() => _currentFw = info?.fw);
    } on ThermostatException {
      // Wersja jest tylko informacją.
    }
  }

  Future<({String name, Uint8List bytes})?> _systemPick() async {
    final f = await FilePicker.pickFile(dialogTitle: 'Plik firmware (.bin)');
    if (f == null) return null;
    return (name: f.name, bytes: await f.readAsBytes());
  }

  Future<void> _choose() async {
    setState(() => _error = null);
    final picked = await (widget.pickFile ?? _systemPick)();
    if (picked == null || !mounted) return;
    setState(() {
      _fileName = picked.name;
      _image = picked.bytes;
      _phase = _Phase.idle;
      _error = validateFirmwareImage(picked.name, picked.bytes);
    });
  }

  Future<void> _upload() async {
    final api = c.localApi;
    final image = _image;
    if (api == null || image == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Wgrać nowe oprogramowanie?'),
        content: Text(
          'Plik $_fileName (${(image.length / 1024).round()} KB). Urządzenie na chwilę przestanie działać '
          'i uruchomi się ponownie. Nie wyłączaj zasilania w trakcie.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Wgraj')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() {
      _phase = _Phase.uploading;
      _progress = 0;
      _error = null;
      _message = 'Wysyłanie pliku…';
    });
    // Postęp zapisu w termostacie; gdy GET nie odpowiada w trakcie, zostaje postęp wysyłania.
    _poll = Timer.periodic(const Duration(milliseconds: 700), (_) async {
      try {
        final s = await api.otaStatus(timeout: const Duration(seconds: 2));
        if (mounted && _phase == _Phase.uploading && s.state == 'running') {
          setState(() {
            _progress = s.progress / 100;
            _message = 'Zapisywanie w termostacie… ${s.progress} %';
          });
        }
      } on Object {
        // Urządzenie zajęte odbiorem - spróbujemy za chwilę.
      }
    });

    try {
      final restartIn = await api.uploadFirmware(
        image,
        onSent: (sent, total) {
          if (!mounted) return;
          final f = sent / total;
          if (f > _progress) setState(() => _progress = f);
        },
      );
      _poll?.cancel();
      if (!mounted) return;
      setState(() {
        _phase = _Phase.restarting;
        _progress = 1;
        _message = 'Urządzenie uruchamia się ponownie…';
      });
      await _waitForRestart(api, restartIn);
    } on ThermostatException catch (e) {
      _poll?.cancel();
      if (mounted) {
        setState(() {
          _phase = _Phase.failed;
          _error = e.message;
          _message = null;
        });
      }
    }
  }

  /// Czekamy na restart (`restartIn` + start Wi-Fi), potem pytamy `/api/info` o nową wersję
  /// i łączymy się ponownie.
  Future<void> _waitForRestart(LocalApi api, int restartIn) async {
    final previous = _currentFw;
    await Future<void>.delayed(Duration(seconds: restartIn + 2));
    final deadline = DateTime.now().add(const Duration(seconds: 90));
    String? fw;
    while (mounted && DateTime.now().isBefore(deadline)) {
      try {
        fw = (await api.info(timeout: const Duration(seconds: 2))).fw;
        break;
      } on ThermostatException {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
    if (!mounted) return;
    if (fw == null) {
      setState(() {
        _phase = _Phase.failed;
        _error = 'Urządzenie nie odezwało się po aktualizacji. Sprawdź jego ekran i spróbuj połączyć się ponownie.';
        _message = null;
      });
      return;
    }
    setState(() {
      _currentFw = fw;
      _phase = _Phase.done;
      _message = fw == previous
          ? 'Urządzenie działa, ale zgłasza tę samą wersję ($fw). Sprawdź, czy wgrałeś właściwy plik.'
          : 'Gotowe. Nowa wersja: $fw';
    });
    unawaited(c.connect());
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final busy = _phase == _Phase.uploading || _phase == _Phase.restarting;
    return PopScope(
      canPop: !busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('Aktualizacja firmware')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.memory),
              title: const Text('Obecna wersja'),
              trailing: Text(_currentFw ?? '—', key: const Key('fwVersion'), style: t.titleMedium),
            ),
            const SizedBox(height: 8),
            Text(
              'Wybierz plik firmware.bin (z kompilacji: .pio/build/esp32s3_n16r8/firmware.bin). '
              'Urządzenie sprawdza obraz przed przełączeniem, więc zły plik niczego nie zepsuje.',
              style: t.bodyMedium,
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('chooseFirmware'),
              onPressed: busy ? null : _choose,
              icon: const Icon(Icons.folder_open),
              label: Text(_fileName ?? 'Wybierz plik .bin'),
            ),
            if (_image != null && _error == null && _phase == _Phase.idle)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('${(_image!.length / 1024).round()} KB', style: t.bodySmall),
              ),
            const SizedBox(height: 16),
            if (busy || _phase == _Phase.done) ...[
              LinearProgressIndicator(value: _phase == _Phase.restarting ? null : _progress),
              const SizedBox(height: 8),
            ],
            if (_message != null) Text(_message!, key: const Key('otaMessage')),
            if (_error != null) Text(_error!, style: TextStyle(color: cs.error)),
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const Key('uploadFirmware'),
              onPressed: busy || _image == null || validateFirmwareImage(_fileName ?? '', _image!) != null
                  ? null
                  : _upload,
              icon: const Icon(Icons.system_update_alt),
              label: const Text('Wgraj do urządzenia'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Wstępna kontrola pliku przed wysłaniem: rozszerzenie, rozmiar, bajt 0xE9 obrazu ESP32.
String? validateFirmwareImage(String name, Uint8List bytes) {
  if (!name.toLowerCase().endsWith('.bin')) return 'Wybierz plik z rozszerzeniem .bin.';
  if (bytes.length < 1024) return 'Plik jest za mały na firmware.';
  if (bytes.length > 8 * 1024 * 1024) return 'Plik jest za duży (ponad 8 MB).';
  if (bytes[0] != 0xE9) return 'To nie jest obraz aplikacji ESP32 (powinien zaczynać się bajtem 0xE9).';
  return null;
}
