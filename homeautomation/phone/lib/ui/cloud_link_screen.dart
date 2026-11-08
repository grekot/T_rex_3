import 'package:flutter/material.dart';

import '../controllers/device_controller.dart';
import '../data/cloud_access.dart';
import '../data/errors.dart';

/// „Połącz z chmurą” (pkt 8.2): urządzenie zakłada sobie anonimowe konto Firebase, a aplikacja
/// właściciela przypisuje je do domu (`homes/{h}/deviceAccounts`). Hasło konta nie opuszcza telefonu.
class CloudLinkScreen extends StatefulWidget {
  const CloudLinkScreen({super.key, required this.controller, required this.cloud});

  final DeviceController<Object?, Object?> controller;
  final CloudAccess cloud;

  @override
  State<CloudLinkScreen> createState() => _CloudLinkScreenState();
}

class _CloudLinkScreenState extends State<CloudLinkScreen> {
  bool _busy = false;
  String? _error;
  String? _progress;

  Future<void> _link() async {
    final cloud = widget.cloud;
    final homeId = cloud.homeId;
    if (homeId == null) {
      setState(() => _error = 'Najpierw wybierz albo załóż dom.');
      return;
    }
    if (!cloud.isHomeOwner) {
      setState(() => _error = 'Z chmurą łączy urządzenia właściciel domu.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _progress = 'Wysyłanie danych do urządzenia…';
    });
    final c = widget.controller;
    try {
      await c.linkCloud(
        apiKey: cloud.apiKey,
        dbUrl: cloud.dbUrl,
        homeId: homeId,
        bind: (deviceUid) async {
          await bindDeviceAccount(cloud.store, homeId, deviceUid, c.device.id);
          await writeDeviceIndex(cloud.store, homeId, c.device.id, c.device.type, c.device.name);
        },
        onStatus: (s) {
          if (!mounted) return;
          setState(
            () => _progress = switch (s.status) {
              'linking' => 'Urządzenie zakłada konto w chmurze…',
              'binding' => 'Przypisywanie urządzenia do domu…',
              _ => _progress,
            },
          );
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Połączono z chmurą. Dane pojawią się w ciągu minuty.')));
      Navigator.of(context).pop(true);
    } on ThermostatException catch (e) {
      setState(() => _error = e.message);
    } on Object catch (e) {
      setState(() => _error = 'Nie udało się przypisać urządzenia do domu: $e');
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Połącz z chmurą')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Icon(Icons.cloud_sync_outlined, size: 56, color: cs.primary),
          const SizedBox(height: 16),
          Text(
            'Urządzenie założy sobie w chmurze własne konto (bez hasła), a aplikacja przypisze je do tego domu. '
            'Twoje hasło nie trafia do urządzenia. Potem domownicy mogą sterować nim spoza domu według '
            'swoich uprawnień.',
            style: t.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Wymaga włączonego logowania anonimowego w konsoli Firebase (Authentication → Sign-in method → Anonymous).',
            style: t.bodySmall,
          ),
          if (_progress != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
                Expanded(child: Text(_progress!, key: const Key('cloudProgress'))),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, key: const Key('cloudError'), style: TextStyle(color: cs.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            key: const Key('cloudLinkGo'),
            onPressed: _busy ? null : _link,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Połącz urządzenie'),
            ),
          ),
        ],
      ),
    );
  }
}
