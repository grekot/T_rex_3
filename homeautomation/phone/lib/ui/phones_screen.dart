import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/device_controller.dart';
import '../data/errors.dart';
import '../data/local_api.dart';
import '../models/home.dart';
import 'widgets.dart';

/// „Telefony” urządzenia (pkt 2-3): każdy sparowany telefon ma własny token i poziom.
/// Usunięcie sprawia, że jego token przestaje działać; poziom można zmienić ręcznie (`PATCH`),
/// a dla huba albo skryptu wystawić token bez parowania (`POST`). Wymaga `config`, działa w domu.
class PhonesScreen extends StatefulWidget {
  const PhonesScreen({super.key, required this.controller});

  final DeviceController<Object?, Object?> controller;

  @override
  State<PhonesScreen> createState() => _PhonesScreenState();
}

class _PhonesScreenState extends State<PhonesScreen> {
  late Future<(List<PhoneClient>, String?)> _load = _fetch();

  Future<(List<PhoneClient>, String?)> _fetch() async {
    final c = widget.controller;
    final me = await c.localApi?.me().catchError((_) => const MeInfo(id: '', uid: '', access: AccessLevel.none));
    return (await c.phones(), me?.id);
  }

  Future<void> _remove(PhoneClient p, bool self) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Usunąć „${p.name}”?'),
        content: Text(
          self
              ? 'To ten telefon. Po usunięciu straci dostęp do urządzenia w sieci domowej, '
                    'dopóki znów go nie sparujesz.'
              : 'Token tego telefonu przestanie działać. Dostęp przez chmurę zależy od uprawnień w domu.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Usuń')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.controller.removePhone(p.id);
      setState(() {
        _load = _fetch();
      });
    } on ThermostatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _changeLevel(PhoneClient p, bool self) async {
    final level = await showDialog<AccessLevel>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Poziom: ${p.name}'),
        children: [
          if (p.uid.isNotEmpty && p.verified)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('Przy połączonej chmurze urządzenie i tak bierze poziom tej osoby z uprawnień domu.'),
            ),
          if (self)
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('To ten telefon - poniżej „pełny dostęp” stracisz dostęp do tego ekranu.'),
            ),
          for (final l in AccessLevel.grantable)
            SimpleDialogOption(
              key: Key('level-${l.wire}'),
              onPressed: () => Navigator.pop(ctx, l),
              child: Text(l == p.access ? '${l.label} (teraz)' : l.label),
            ),
        ],
      ),
    );
    if (level == null || level == p.access || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.controller.setPhoneAccess(p.id, level);
      setState(() {
        _load = _fetch();
      });
    } on ThermostatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Token bez parowania - dla huba (pkt 11) albo własnego skryptu.
  Future<void> _newToken() async {
    final name = await showTextInputDialog(
      context,
      title: 'Nowy token (hub, skrypt)',
      initial: 'hub',
      maxLength: 24,
      fieldKey: const Key('tokenName'),
    );
    if (name == null || !mounted) return;
    final level = await showDialog<AccessLevel>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Poziom tokenu'),
        children: [
          for (final l in AccessLevel.grantable)
            SimpleDialogOption(onPressed: () => Navigator.pop(ctx, l), child: Text(l.label)),
        ],
      ),
    );
    if (level == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final t = await widget.controller.createToken(name, level);
      setState(() {
        _load = _fetch();
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Token'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Skopiuj go teraz - urządzenie nie pokaże go ponownie.'),
              const SizedBox(height: 12),
              SelectableText(
                t.token,
                key: const Key('newToken'),
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: t.token)),
              child: const Text('Kopiuj'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Gotowe')),
          ],
        ),
      );
    } on ThermostatException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('Telefony · ${widget.controller.device.name}')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('newToken'),
        onPressed: _newToken,
        icon: const Icon(Icons.key),
        label: const Text('Token'),
      ),
      body: FutureBuilder<(List<PhoneClient>, String?)>(
        future: _load,
        builder: (context, snap) {
          if (snap.hasError) {
            final e = snap.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(e is ThermostatException ? e.message : '$e', style: TextStyle(color: cs.error)),
              ),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final (phones, myId) = snap.data!;
          return RefreshIndicator(
            onRefresh: () async => setState(() {
              _load = _fetch();
            }),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Text(
                    'Urządzenie pamięta do 16 telefonów. Telefon dodany przez Bluetooth ma pełny dostęp; '
                    'sparowany kodem dostaje poziom z uprawnień domu po sprawdzeniu konta. Dotknij telefonu, '
                    'aby zmienić poziom ręcznie (np. bez chmury).',
                  ),
                ),
                for (final p in phones)
                  ListTile(
                    key: Key('phone-${p.id}'),
                    onTap: () => _changeLevel(p, p.id == myId),
                    leading: Icon(p.id == myId ? Icons.smartphone : Icons.phone_android),
                    title: Text(p.id == myId ? '${p.name} (ten telefon)' : p.name),
                    subtitle: Text(
                      [
                        p.access.label,
                        if (!p.verified) 'konto niepotwierdzone',
                        if (p.uid.isNotEmpty) p.uid,
                      ].join(' · '),
                    ),
                    trailing: IconButton(
                      tooltip: 'Usuń',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _remove(p, p.id == myId),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
