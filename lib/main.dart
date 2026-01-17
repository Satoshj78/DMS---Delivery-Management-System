import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'core/routing/root_gate.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Necessario per notifiche ricevute a app chiusa (mobile)
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // ✅ App Check (fondamentale se hai enforcement su Storage/Firestore)
  await FirebaseAppCheck.instance.activate(
    androidProvider: kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
    appleProvider: kReleaseMode
        ? AppleProvider.appAttestWithDeviceCheckFallback
        : AppleProvider.debug,
    webProvider: ReCaptchaV3Provider('6Lc8sDssAAAAADu_Jy3C0gnqGt18ofdsxOXucpsT'), // ✅ la tua site key
  );


  if (!kIsWeb) {
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }



  // ✅ Barre di sistema fuori dall'app (no edge-to-edge)
  SystemChrome.setEnabledSystemUIMode(
    SystemUiMode.manual,
    overlays: SystemUiOverlay.values, // top + bottom
  );



  runApp(const DmsApp());
}

class DmsApp extends StatelessWidget {
  const DmsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DMS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        scaffoldBackgroundColor: const Color(0xFFF6F4F8),
        useMaterial3: true,
      ),
      home: const RootGate(),
    );
  }
}
