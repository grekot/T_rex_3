import 'package:flutter/material.dart';

import '../data/device_store.dart';
import '../services.dart';
import 'ble_setup_screen.dart';
import 'pairing_screen.dart';

/// „Dodaj urządzenie”: nowe przez Bluetooth (konfiguracja WiFi + parowanie, pkt 9), nowe bez Bluetooth
/// przez jego sieć WiFi `HA_*` (pkt 9.4) albo już działające w sieci domowej kodem (kolejne telefony, pkt 2).
class AddDeviceScreen extends StatelessWidget {
  const AddDeviceScreen({super.key});

  Future<void> _go(BuildContext context, Widget screen) async {
    final navigator = Navigator.of(context);
    final device = await navigator.push<PairedDevice>(MaterialPageRoute(builder: (_) => screen));
    if (device != null) navigator.pop(device);
  }

  @override
  Widget build(BuildContext context) {
    final ble = Services.of(context).provisioning.supported;
    return Scaffold(
      appBar: AppBar(title: const Text('Dodaj urządzenie')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Option(
            key: const Key('addBle'),
            icon: Icons.bluetooth,
            title: 'Nowe urządzenie',
            text: ble
                ? 'Pierwsze uruchomienie albo po resecie: telefon łączy się z urządzeniem przez Bluetooth, '
                      'przekazuje mu sieć WiFi i od razu je paruje. Potrzebny kod z ekranu urządzenia.'
                : 'Konfiguracja przez Bluetooth działa tylko w aplikacji na telefonie.',
            onTap: ble ? () => _go(context, const BleSetupScreen()) : null,
          ),
          const SizedBox(height: 12),
          _Option(
            key: const Key('addSoftAp'),
            icon: Icons.wifi_tethering,
            title: 'Nowe urządzenie bez Bluetootha',
            text:
                'Np. przełącznik światła bez ekranu: telefon łączy się na chwilę z jego siecią WiFi HA_… '
                '(hasło = kod z naklejki), przekazuje mu sieć domową i od razu je paruje.',
            onTap: () => _go(context, const BleSetupScreen(softAp: true)),
          ),
          const SizedBox(height: 12),
          _Option(
            key: const Key('addCode'),
            icon: Icons.pin,
            title: 'Urządzenie już działa w sieci domowej',
            text:
                'Na przykład dla kolejnego telefonu w domu. Telefon w tej samej sieci WiFi, '
                'potem 6-cyfrowy kod z ekranu urządzenia (bez ekranu - kod z naklejki).',
            onTap: () => _go(context, const PairingScreen()),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option({super.key, required this.icon, required this.title, required this.text, this.onTap});

  final IconData icon;
  final String title;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 40, color: onTap == null ? Theme.of(context).disabledColor : null),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: t.titleMedium),
                    const SizedBox(height: 4),
                    Text(text, style: t.bodyMedium),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
