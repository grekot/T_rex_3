import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../provisioning/prov_qr.dart';
import 'widgets.dart';

/// Skanowanie kodu QR: domyślnie naklejka urządzenia (kontrakt pkt 9.1, zwraca [ProvQr]), z [parse] - inny
/// kod (np. komputera, pkt 2a). Zły kod - komunikat i skanowanie dalej. Treść kodu można też wkleić
/// (np. z logu urządzenia `WiFi: QR {...}`).
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({
    super.key,
    this.camera = true,
    this.parse = ProvQr.parse,
    this.title = 'Kod QR urządzenia',
    this.hint = 'Skieruj aparat na kod QR z naklejki albo z ekranu urządzenia. Aplikacja połączy się z nim sama.',
  });

  /// false w testach (bez aparatu).
  final bool camera;

  /// Rzuca [FormatException] z komunikatem dla użytkownika.
  final Object Function(String raw) parse;
  final String title;
  final String hint;

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  bool _done = false;
  String? _error;
  String? _lastBad;

  void _accept(String raw) {
    if (_done) return;
    try {
      final qr = widget.parse(raw);
      _done = true;
      Navigator.of(context).pop(qr);
    } on FormatException catch (e) {
      if (raw == _lastBad) return; // ten sam zły kod w kolejnych klatkach
      _lastBad = raw;
      setState(() => _error = e.message);
    }
  }

  Future<void> _paste() async {
    final text = await showTextInputDialog(
      context,
      title: 'Treść kodu QR',
      hint: '{"ver":"v1", …}',
      fieldKey: const Key('qrText'),
    );
    if (text != null) _accept(text);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          IconButton(
            key: const Key('qrPaste'),
            tooltip: 'Wpisz treść kodu',
            icon: const Icon(Icons.keyboard_outlined),
            onPressed: _paste,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: widget.camera
                ? MobileScanner(
                    onDetect: (capture) {
                      for (final b in capture.barcodes) {
                        final raw = b.rawValue;
                        if (raw != null) _accept(raw);
                      }
                    },
                    errorBuilder: (context, error) => Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          error.errorCode == MobileScannerErrorCode.permissionDenied
                              ? 'Brak zgody na aparat. Włącz ją w ustawieniach telefonu albo wpisz treść kodu (ikona klawiatury).'
                              : 'Aparat niedostępny (${error.errorCode.name}). Wpisz treść kodu (ikona klawiatury).',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Text(widget.hint, textAlign: TextAlign.center),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, key: const Key('qrError'), style: TextStyle(color: cs.error)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
