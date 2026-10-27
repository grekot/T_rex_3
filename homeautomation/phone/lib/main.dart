import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'app.dart';
import 'background/alert_worker.dart';
import 'data/cloud_access.dart';
import 'firebase_options.dart';
import 'services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Bez google-services.json (zaślepka z tools/configure.mjs) aplikacja działa tylko w sieci domowej.
  if (firebaseConfigured) {
    await Firebase.initializeApp(options: firebaseOptions);
    await AlertScheduler.init();
  }
  final cloud = firebaseConfigured ? FirebaseCloudAccess(firebaseOptions) : NoCloudAccess();
  runApp(
    Services.production(
      cloud: cloud,
      child: const TermostatApp(useLogin: firebaseConfigured),
    ),
  );
}
