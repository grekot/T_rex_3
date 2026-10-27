import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../background/alert_worker.dart';
import '../controllers/home_session.dart';
import '../data/cloud_access.dart';
import '../services.dart';
import 'onboarding_screen.dart';
import 'widgets.dart';

/// Menu w pasku: wybór domu, nowy dom / dołączenie kodem, powiadomienia, wylogowanie.
/// Bez konta (bez Firebase) nic nie pokazuje.
class AccountMenu extends StatefulWidget {
  const AccountMenu({super.key, this.session});

  final HomeSession? session;

  @override
  State<AccountMenu> createState() => _AccountMenuState();
}

class _AccountMenuState extends State<AccountMenu> {
  bool? _alertsOn;

  @override
  void initState() {
    super.initState();
    if (alertsSupported) {
      AlertScheduler.isEnabled().then((on) {
        if (mounted) setState(() => _alertsOn = on);
      }, onError: (_) {});
    }
  }

  Future<void> _onSelected(String v) async {
    final s = widget.session;
    final cloud = Services.of(context).cloud;
    if (v.startsWith('home:') && s != null) {
      final home = s.homes.firstWhere((h) => h.id == v.substring(5));
      await s.switchTo(home);
    } else if (v == 'new' && s != null) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => OnboardingScreen(session: s)));
    } else if (v == 'rename' && s != null) {
      final name = await showTextInputDialog(context, title: 'Nazwa domu', initial: s.current?.name ?? '');
      if (name != null) await s.rename(name);
    } else if (v == 'leave' && s != null) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Opuścić dom „${s.current?.name ?? ''}”?'),
          content: const Text('Stracisz dostęp do jego urządzeń przez chmurę. Wrócić możesz tylko z nowym zaproszeniem.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Anuluj')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Opuść')),
          ],
        ),
      );
      if (ok == true) await s.leave();
    } else if (v == 'alerts') {
      final on = !(_alertsOn ?? true);
      setState(() => _alertsOn = on);
      await AlertScheduler.setEnabled(on, loggedIn: cloud.uid != null);
    } else if (v == 'signout') {
      await AlertScheduler.sync(loggedIn: false);
      await FirebaseAuth.instance.signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cloud = Services.of(context).cloud;
    if (cloud is NoCloudAccess) return const SizedBox.shrink();
    final s = widget.session;
    return PopupMenuButton<String>(
      key: const Key('accountMenu'),
      tooltip: 'Dom i konto',
      icon: const Icon(Icons.account_circle_outlined),
      onSelected: _onSelected,
      itemBuilder: (_) => [
        PopupMenuItem(enabled: false, child: Text(cloud.email ?? 'Konto')),
        if (s != null) ...[
          const PopupMenuDivider(),
          for (final h in s.homes)
            CheckedPopupMenuItem(value: 'home:${h.id}', checked: h.id == s.current?.id, child: Text(h.name)),
          if (s.isOwner) const PopupMenuItem(value: 'rename', child: Text('Zmień nazwę domu')),
          if (s.current != null && !s.isOwner) const PopupMenuItem(value: 'leave', child: Text('Opuść ten dom')),
          const PopupMenuItem(value: 'new', child: Text('Nowy dom / dołącz kodem')),
        ],
        const PopupMenuDivider(),
        if (_alertsOn != null)
          CheckedPopupMenuItem(value: 'alerts', checked: _alertsOn!, child: const Text('Powiadomienia o awariach')),
        const PopupMenuItem(value: 'signout', child: Text('Wyloguj')),
      ],
    );
  }
}
