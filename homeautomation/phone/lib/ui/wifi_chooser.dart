import 'package:flutter/material.dart';

import '../provisioning/messages.dart';

/// Wybór sieci WiFi przy konfiguracji urządzenia (pkt 9.2): sieci widziane przez urządzenie albo nazwa wpisana
/// ręcznie (ukryta / urządzenie bez skanu) i hasło. [network] null = sieć wpisana w [ssid].
class WifiChooser extends StatefulWidget {
  const WifiChooser({
    super.key,
    required this.networks,
    required this.network,
    required this.onNetwork,
    required this.ssid,
    required this.password,
    required this.onSubmit,
    this.canScan = true,
  });

  final List<WifiNetwork> networks;
  final WifiNetwork? network;
  final ValueChanged<WifiNetwork?> onNetwork;
  final TextEditingController ssid;
  final TextEditingController password;
  final VoidCallback onSubmit;
  final bool canScan;

  @override
  State<WifiChooser> createState() => _WifiChooserState();
}

class _WifiChooserState extends State<WifiChooser> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    final net = widget.network;
    final custom = net == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final n in widget.networks)
          ListTile(
            key: Key('wifi-${n.ssid}'),
            selected: net?.ssid == n.ssid,
            onTap: () => widget.onNetwork(n),
            leading: Icon(net?.ssid == n.ssid ? Icons.radio_button_checked : Icons.radio_button_unchecked),
            title: Text(n.ssid),
            subtitle: Text('${n.rssi} dBm${n.secured ? '' : ' · otwarta'}'),
            trailing: Icon(n.secured ? Icons.wifi_lock : Icons.wifi),
          ),
        ListTile(
          key: const Key('wifi-custom'),
          selected: custom,
          onTap: () => widget.onNetwork(null),
          leading: Icon(custom ? Icons.radio_button_checked : Icons.radio_button_unchecked),
          title: Text(widget.canScan ? 'Inna sieć (ukryta)' : 'Nazwa sieci'),
        ),
        if (custom)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              key: const Key('ssid'),
              controller: widget.ssid,
              decoration: const InputDecoration(labelText: 'Nazwa sieci (SSID)'),
            ),
          ),
        if (custom || net.secured)
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              key: const Key('wifiPassword'),
              controller: widget.password,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Hasło WiFi',
                suffixIcon: IconButton(
                  icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showPassword = !_showPassword),
                ),
              ),
              onSubmitted: (_) => widget.onSubmit(),
            ),
          ),
      ],
    );
  }
}
