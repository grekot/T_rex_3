import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/cloud_store.dart';
import '../data/notifications.dart';
import '../models/hub.dart';

/// Ostatnio przeczytane powiadomienie domu (`ts`, ms) - do znaczka na ikonie.
Future<int> notificationsSeen(String homeId) async {
  try {
    return await SharedPreferencesAsync().getInt('notif_seen_$homeId') ?? 0;
  } on Object {
    return 0;
  }
}

Future<void> _markSeen(String homeId, int ts) async {
  try {
    await SharedPreferencesAsync().setInt('notif_seen_$homeId', ts);
  } on Object {
    // tylko znaczek
  }
}

/// Ikona z liczbą nieprzeczytanych powiadomień z huba; otwiera [NotificationsScreen].
class NotificationsButton extends StatefulWidget {
  const NotificationsButton({super.key, required this.store, required this.homeId});

  final CloudStore store;
  final String homeId;

  @override
  State<NotificationsButton> createState() => _NotificationsButtonState();
}

class _NotificationsButtonState extends State<NotificationsButton> {
  StreamSubscription<List<HubNotification>>? _sub;
  List<HubNotification> _all = const [];
  int _seen = 0;

  @override
  void initState() {
    super.initState();
    notificationsSeen(widget.homeId).then((s) {
      if (mounted) setState(() => _seen = s);
    });
    _sub = watchNotifications(widget.store, widget.homeId).listen((l) {
      if (mounted) setState(() => _all = l);
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unseen = _all.where((n) => n.ts > _seen).length;
    return IconButton(
      key: const Key('notifications'),
      tooltip: 'Powiadomienia z domu',
      icon: Badge(
        isLabelVisible: unseen > 0,
        label: Text('$unseen'),
        child: const Icon(Icons.notifications_outlined),
      ),
      onPressed: () async {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => NotificationsScreen(items: _all)),
        );
        final latest = _all.isEmpty ? 0 : _all.first.ts;
        await _markSeen(widget.homeId, latest);
        if (mounted) setState(() => _seen = latest);
      },
    );
  }
}

/// Lista powiadomień z automatyk huba (najnowsze pierwsze).
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.items});

  final List<HubNotification> items;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    String two(int x) => x.toString().padLeft(2, '0');
    return Scaffold(
      appBar: AppBar(title: const Text('Powiadomienia z domu')),
      body: items.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Brak powiadomień. Wysyłają je automatyki huba (akcja „Powiadomienie”).'),
              ),
            )
          : ListView(
              children: [
                for (final n in items)
                  ListTile(
                    leading: Icon(
                      switch (n.level) {
                        'alarm' => Icons.error,
                        'warning' => Icons.warning_amber_rounded,
                        _ => Icons.info_outline,
                      },
                      color: n.level == 'info' ? null : cs.error,
                    ),
                    title: Text(n.text),
                    subtitle: Text(() {
                      final d = DateTime.fromMillisecondsSinceEpoch(n.ts);
                      return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
                    }()),
                  ),
              ],
            ),
    );
  }
}
