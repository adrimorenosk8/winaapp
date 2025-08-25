import 'dart:async'; // runZonedGuarded
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'dart:ui'; // PlatformDispatcher
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import 'firebase_options.dart';
import 'auth_gate.dart';

/// Logging seguro (no hace nada en release). Recorta mensajes muy largos.
void safeLog(String message) {
  if (kReleaseMode) return; // No logs verbosos en producción
  const max = 1000;
  if (message.length > max) {
    debugPrint("${message.substring(0, max)}…");
  } else {
    debugPrint(message);
  }
}

Future<void> _initFirebase() async {
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  safeLog("✅ Firebase inicializado");

  // --- Firebase App Check: protege el backend de abusos y clients falsos ---
  // Requiere habilitar App Check en la consola de Firebase:
  // - Android: Play Integrity
  // - iOS: App Attest (o DeviceCheck si tu target no soporta App Attest)
  // - Web: ReCaptcha v3 / Enterprise (añade tu site key)
  if (kIsWeb) {
    // ⛳️ TODO: Sustituye por tu Site Key real
    await FirebaseAppCheck.instance.activate(
      webProvider: ReCaptchaV3Provider('RECAPTCHA_V3_SITE_KEY'),
      // Si usas Enterprise: ReCaptchaEnterpriseProvider('RECAPTCHA_ENTERPRISE_SITE_KEY')
    );
    safeLog("🛡️ App Check activado (Web: reCAPTCHA v3)");
  } else {
    await FirebaseAppCheck.instance.activate(
      androidProvider: AndroidProvider.playIntegrity,
      appleProvider: AppleProvider.appAttest, // si no soporta App Attest, usa .deviceCheck
    );
    safeLog("🛡️ App Check activado (Android/iOS)");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Captura errores de Flutter y los reenvía a la zona (incluye async)
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Zone.current.handleUncaughtError(
      details.exception,
      details.stack ?? StackTrace.empty,
    );
  };

  // Captura errores a nivel de engine (animaciones, timers, etc.)
  PlatformDispatcher.instance.onError = (error, stack) {
    safeLog("🔥 Platform error: $error\n$stack");
    return true; // ya lo gestionamos
  };

  await runZonedGuarded<Future<void>>(() async {
    try {
      await _initFirebase();
    } catch (e, st) {
      safeLog("❌ Error en init Firebase/App Check: $e\n$st");
    }

    runApp(const MyApp());
  }, (error, stack) {
    // Aquí puedes enviar a Crashlytics/Sentry si lo integras
    safeLog("🔥 Uncaught zone error: $error\n$stack");
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WINA APP',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: Colors.greenAccent[400],
          secondary: Colors.greenAccent[400],
        ),
      ),
      home: const AuthGate(),
    );
  }
}
