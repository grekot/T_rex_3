// Powiadomienia bez Cloud Functions (plan Spark): WorkManager co ~15 min czyta stan termostatów
// z chmury i pokazuje lokalne powiadomienie o awarii czujnika albo braku kontaktu.

import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../data/cloud_access.dart';
import '../data/cloud_store.dart';
import '../data/firmware_catalog.dart';
import '../data/notifications.dart';
import '../firebase_options.dart';
import 'alerts.dart';
import 'update_check.dart';

const _taskName = 'termostat-alerts';
const _enabledKey = 'alerts_enabled';
const _memoryKey = 'alerts_memory';

const _channel = AndroidNotificationDetails(
  'alerts',
  'Alarmy termostatu',
  channelDescription: 'Awaria czujnika i brak kontaktu z termostatem',
  importance: Importance.high,
  priority: Priority.high,
);

/// Na razie tylko Android (iOS wymaga osobnej konfiguracji BGTaskScheduler).
bool get alertsSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android && firebaseConfigured;

@pragma('vm:entry-point')
void alertCallbackDispatcher() {
  Workmanager().executeTask((task, input) async {
    try {
      await runAlertCheck();
    } on Object catch (e) {
      debugPrint('Alarmy termostatu: $e');
    }
    // true także po błędzie - następna próba i tak za 15 min.
    return true;
  });
}

/// Jedno sprawdzenie (w tle albo ręcznie).
Future<void> runAlertCheck() async {
  if (!firebaseConfigured) return;
  WidgetsFlutterBinding.ensureInitialized();
  if (Firebase.apps.isEmpty) await Firebase.initializeApp(options: firebaseOptions);
  final access = FirebaseCloudAccess(firebaseOptions);
  if (!access.available) return;

  final prefs = SharedPreferencesAsync();
  if (await prefs.getBool(_enabledKey) == false) return;
  final raw = await prefs.getString(_memoryKey);
  final previous = AlertMemory.fromJson(raw == null ? null : jsonDecode(raw));

  final result = evaluateAlerts(await collectHealth(access), previous, DateTime.now().millisecondsSinceEpoch);

  final plugin = await _notifications();
  for (final a in result.newAlerts) {
    await plugin.show(
      id: a.notificationId,
      title: a.title,
      body: a.body,
      notificationDetails: const NotificationDetails(android: _channel),
    );
  }
  for (final (id, kind) in result.resolved) {
    await plugin.cancel(id: alertNotificationId(id, kind));
  }
  await prefs.setString(_memoryKey, jsonEncode(result.memory.toJson()));
  await _hubNotifications(access, prefs, plugin);
  await _firmwareUpdates(access, prefs, plugin);
}

const _updatesChannel = AndroidNotificationDetails(
  'updates',
  'Aktualizacje firmware',
  channelDescription: 'Nowe wersje oprogramowania urządzeń do zatwierdzenia',
  importance: Importance.defaultImportance,
);

/// Raz dziennie: manifest wydań (pkt 3e) porównany z urządzeniami domów, których jestem właścicielem.
Future<void> _firmwareUpdates(
  FirebaseCloudAccess access,
  SharedPreferencesAsync prefs,
  FlutterLocalNotificationsPlugin plugin,
) async {
  final uid = access.uid;
  if (uid == null) return;
  final now = DateTime.now().millisecondsSinceEpoch;
  final last = await prefs.getInt('fw_check_at');
  if (last != null && now - last < const Duration(hours: 23).inMilliseconds) return;
  await prefs.setInt('fw_check_at', now);
  final available = await collectUpdates(access.store, uid, await FirmwareCatalog().load());
  final seen = {...?await prefs.getStringList('fw_notified')};
  final notice = updateNotice(available, seen);
  if (notice != null) {
    await plugin.show(
      id: 0x46570000,
      title: notice.title,
      body: notice.body,
      notificationDetails: const NotificationDetails(android: _updatesChannel),
    );
  }
  // Pamiętamy tylko bieżące - po aktualizacji wpis znika, a nowa wersja znów da powiadomienie.
  await prefs.setStringList('fw_notified', [for (final a in available) a.key]);
}

const _hubChannel = AndroidNotificationDetails(
  'hub',
  'Powiadomienia z domu',
  channelDescription: 'Powiadomienia z automatyk huba',
  importance: Importance.high,
  priority: Priority.high,
);

/// Powiadomienia z automatyk huba (`homes/{h}/notifications`, pkt 11) - nowe od ostatniego sprawdzenia.
Future<void> _hubNotifications(
  FirebaseCloudAccess access,
  SharedPreferencesAsync prefs,
  FlutterLocalNotificationsPlugin plugin,
) async {
  final uid = access.uid;
  if (uid == null) return;
  final homes = toJsonObject(await access.store.read('users/$uid/homes').catchError((_) => null))?.keys ?? const [];
  final now = DateTime.now().millisecondsSinceEpoch;
  for (final h in homes) {
    final key = 'notif_shown_$h';
    final all = parseNotifications(await access.store.read('homes/$h/notifications').catchError((_) => null));
    final fresh = newNotifications(all, await prefs.getInt(key), now);
    for (final n in fresh) {
      await plugin.show(
        id: n.key.hashCode & 0x7fffffff,
        title: switch (n.level) {
          'alarm' => 'Alarm w domu',
          'warning' => 'Uwaga',
          _ => 'Dom',
        },
        body: n.text,
        notificationDetails: const NotificationDetails(android: _hubChannel),
      );
    }
    if (all.isNotEmpty) await prefs.setInt(key, all.first.ts > now ? now : all.first.ts);
  }
}

Future<FlutterLocalNotificationsPlugin> _notifications() async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
  );
  return plugin;
}

/// Sterowanie z aplikacji: włączanie/wyłączanie i rejestracja zadania.
class AlertScheduler {
  static Future<void> init() async {
    if (!alertsSupported) return;
    await Workmanager().initialize(alertCallbackDispatcher);
  }

  static Future<bool> isEnabled() async => await SharedPreferencesAsync().getBool(_enabledKey) ?? true;

  static Future<void> setEnabled(bool on, {required bool loggedIn}) async {
    await SharedPreferencesAsync().setBool(_enabledKey, on);
    await sync(loggedIn: loggedIn);
  }

  /// Wołane po zalogowaniu/wylogowaniu i przy starcie.
  static Future<void> sync({required bool loggedIn}) async {
    if (!alertsSupported) return;
    if (loggedIn && await isEnabled()) {
      final plugin = await _notifications();
      await plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } else {
      await Workmanager().cancelByUniqueName(_taskName);
      await SharedPreferencesAsync().remove(_memoryKey);
    }
  }
}
