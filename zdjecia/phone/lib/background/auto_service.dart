// Usługa w tle (Android foreground service, typ specialUse - bez limitu czasu i z uruchomieniem po restarcie):
//  - most 127.0.0.1 dla zegarka działa cały czas, także przy zamkniętej aplikacji,
//  - co [autoRefreshEvery] pula odświeża się sama (nowe zdjęcia, analiza, ocena Gemini, kadry).
// Android wymaga stałego powiadomienia - kanał jest cichy i można go zwinąć w ustawieniach.
import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../bridge/bridge_server.dart';
import '../bridge/format.dart';
import '../bridge/published_source.dart';
import '../pool_controller.dart';
import '../select/store.dart';

const int _serviceId = 8765;

/// Co ile usługa sprawdza, czy pora odświeżyć pulę
const int _checkEveryMs = 15 * 60 * 1000;

const String autoTitle = 'Zdjęcia dla zegarka';

void initAutoService() {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'zdjecia_w_tle',
      channelName: 'Zdjęcia dla zegarka',
      channelDescription: 'Udostępnianie zdjęć zegarkowi i automatyczne odświeżanie puli',
      channelImportance: NotificationChannelImportance.MIN,
      priority: NotificationPriority.MIN,
      onlyAlertOnce: true,
    ),
    iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(_checkEveryMs),
      autoRunOnBoot: true,
      autoRunOnMyPackageReplaced: true,
      // Bez stałej blokady procesora (bateria); odświeżanie dokończy się, gdy telefon się wybudzi
      allowWakeLock: false,
    ),
  );
}

/// Uruchamia usługę (prosi o zgodę na powiadomienie i o wyjątek z oszczędzania baterii).
/// null = działa, inaczej opis błędu.
Future<String?> startAutoService() async {
  if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
    await FlutterForegroundTask.requestNotificationPermission();
  }
  if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
  }
  if (await FlutterForegroundTask.isRunningService) return null;
  final result = await FlutterForegroundTask.startService(
    serviceId: _serviceId,
    serviceTypes: [ForegroundServiceTypes.specialUse],
    notificationTitle: autoTitle,
    notificationText: 'Udostępniam pulę zegarkowi',
    callback: startAutoCallback,
  );
  return result is ServiceRequestFailure ? '${result.error}' : null;
}

Future<void> stopAutoService() async {
  await FlutterForegroundTask.stopService();
}

Future<bool> autoServiceRunning() => FlutterForegroundTask.isRunningService;

/// Prośba do działającej usługi o odświeżenie puli teraz
void requestAutoRefresh() => FlutterForegroundTask.sendDataToTask('refresh');

@pragma('vm:entry-point')
void startAutoCallback() {
  FlutterForegroundTask.setTaskHandler(AutoTaskHandler());
}

/// Tekst powiadomienia ze stanu automatycznego odświeżania
String autoNotificationText(AutoState s) {
  final last = s.lastRun;
  if (last == null) return 'Udostępniam pulę zegarkowi';
  if (!s.ok) return 'Odświeżenie ${formatClock(last).substring(0, 5)} nieudane – spróbuję za godzinę';
  final fresh = s.newPhotos > 0 ? ', nowe: ${s.newPhotos}' : '';
  return 'Pula: ${s.poolSize} zdjęć$fresh · odświeżono ${formatDay(last).substring(0, 5)} ${formatClock(last).substring(0, 5)}';
}

class AutoTaskHandler extends TaskHandler {
  SelectStore? _store;
  BridgeServer? _server;
  StreamSubscription<BridgeRequest>? _requests;
  bool _refreshing = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    final store = await openSelectStore();
    _store = store;
    final server = BridgeServer(source: () => publishedPhotos(store));
    try {
      await server.start();
      _server = server;
      _requests = server.requests.listen((r) => FlutterForegroundTask.sendDataToMain({'type': 'request', ...r.toJson()}));
    } catch (e) {
      FlutterForegroundTask.sendDataToMain({'type': 'error', 'message': 'Most (port $bridgePort): $e'});
    }
    await _showState(await store.loadAuto());
    await _maybeRefresh();
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    _maybeRefresh();
  }

  @override
  void onReceiveData(Object data) {
    if (data == 'refresh') _maybeRefresh(force: true);
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    await _requests?.cancel();
    await _server?.dispose();
  }

  Future<void> _maybeRefresh({bool force = false}) async {
    final store = _store;
    if (store == null || _refreshing) return;
    if (!force && !autoRefreshDue(await store.loadAuto(), DateTime.now())) return;
    _refreshing = true;
    FlutterForegroundTask.sendDataToMain({'type': 'refreshing'});
    final pool = PoolController(headless: true);
    AutoState? state;
    try {
      await pool.init(refreshNow: false);
      await pool.refresh();
      // Gdy aplikacja odświeża akurat sama, nie zapisujemy nic - spróbujemy przy następnym sprawdzeniu
      if (!pool.lockedOut) {
        final ok = pool.phase == PoolPhase.ready;
        state = AutoState(
          lastRun: DateTime.now(),
          ok: ok,
          error: ok ? pool.aiError : (pool.error ?? pool.phase.name),
          poolSize: pool.pool.length,
          newPhotos: pool.lastNewPhotos,
        );
      }
    } catch (e) {
      state = AutoState(lastRun: DateTime.now(), ok: false, error: '$e');
    } finally {
      _refreshing = false;
      pool.dispose();
    }
    if (state != null) {
      await store.saveAuto(state);
      await _showState(state);
    }
    FlutterForegroundTask.sendDataToMain({'type': 'refreshed'});
  }

  Future<void> _showState(AutoState s) async {
    await FlutterForegroundTask.updateService(notificationTitle: autoTitle, notificationText: autoNotificationText(s));
  }
}
