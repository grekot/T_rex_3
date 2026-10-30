import 'dart:async';
import 'dart:ui';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../controllers/device_hub.dart';
import '../data/cloud_access.dart';
import '../data/connection_manager.dart';
import '../data/device_store.dart';
import '../data/discovery.dart';
import '../data/home_repository.dart';
import '../data/home_widget_store.dart';
import '../data/scene_store.dart';
import '../firebase_options.dart';
import '../models/home.dart';
import '../models/home_widget.dart';
import 'widget_runtime.dart';

const _channel = MethodChannel('pl.grekot.homeautomation/widgets');

/// Dostęp do chmury i hub domu widżetu - osobne, bo [CloudAccess.homeId] wskazuje jeden dom.
DeviceHub widgetHub(HomeWidgetConfig config, Set<String> Function() wanted) {
  final CloudAccess cloud = firebaseConfigured ? FirebaseCloudAccess(firebaseOptions) : NoCloudAccess();
  final local = config.homeId == HomeWidgetConfig.localHome;
  final home = local ? null : Home(id: config.homeId, name: config.homeName, ownerUid: config.ownerUid);
  cloud
    ..homeId = home?.id
    ..homeOwnerUid = home?.ownerUid;
  final store = SecureDeviceStore();
  final uid = cloud.uid;
  return DeviceHub(
    store: store,
    manager: ConnectionManager(store: store, discovery: NsdThermostatDiscovery(), cloud: cloud),
    cloud: cloud,
    home: home,
    repo: home == null || uid == null
        ? null
        : HomeRepository(store: cloud.store, uid: uid, email: cloud.email ?? '', name: cloud.displayName ?? ''),
    sceneStore: AccountSceneStore(cloud),
    wanted: wanted,
  );
}

/// Uruchamiane przez LiveWidgetService.kt w osobnym silniku Fluttera, bez ekranu.
Future<void> runHomeWidgetService() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  if (firebaseConfigured && Firebase.apps.isEmpty) await Firebase.initializeApp(options: firebaseOptions);

  final store = HomeWidgetStore();
  final runtime = WidgetRuntime(
    hubFactory: widgetHub,
    render: (json) => unawaited(_channel.invokeMethod<void>('render', json).catchError((_) {})),
  );

  Future<void> reload() async {
    final ids = (await _channel.invokeListMethod<int>('widgetIds') ?? const <int>[]).toSet();
    await store.retain(ids);
    runtime.update(await store.load());
  }

  _channel.setMethodCallHandler((call) async {
    switch (call.method) {
      case 'reload':
        await reload();
      case 'pause':
        runtime.pause();
      case 'resume':
        runtime.resume();
      case 'network':
        runtime.networkChanged();
      case 'tap':
        final args = (call.arguments as Map).cast<String, int>();
        await runtime.tap(args['id']!, args['index']!);
    }
  });

  if (firebaseConfigured) {
    FirebaseAuth.instance.authStateChanges().listen((user) {
      runtime.showMessage(user == null ? 'Zaloguj się w aplikacji' : null);
      unawaited(reload());
    });
    await FirebaseAuth.instance.authStateChanges().first;
  } else {
    await reload();
  }
  await _channel.invokeMethod<void>('ready');
}
