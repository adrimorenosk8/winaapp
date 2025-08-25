import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

import 'firebase_options.dart';
import 'auth_gate.dart';

/// Logging seguro (silencio en release) + recorte.
void safeLog(String message) {
  if (kReleaseMode) return;
  const max = 1000;
  debugPrint(message.length > max ? "${message.substring(0, max)}…" : message);
}

/// Lee la site key desde variable de entorno (--dart-define) o usa un placeholder.
const String kRecaptchaSiteKey =
    String.fromEnvironment('RECAPTCHA_V3_SITE_KEY', defaultValue: 'RECAPTCHA_V3_SITE_KEY');

Future<void> _initFirebase() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  safeLog("✅ Firebase inicializado");

  // App Check
  try {
    // Refrescar tokens automáticamente
    await FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);

    if (kIsWeb) {
      // En Web, usa reCAPTCHA v3 (pon tu site key real por --dart-define)
      await FirebaseAppCheck.instance.activate(
        webProvider: ReCaptchaV3Provider(kRecaptchaSiteKey),
      );
      safeLog("🛡️ App Check (Web: reCAPTCHA v3)");
    } else {
      // En mobile: en debug usa providers de depuración; en release, reales
      final androidProv = kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug;
      // Intentamos App Attest; si falla, probamos DeviceCheck
      try {
        await FirebaseAppCheck.instance.activate(
          androidProvider: androidProv,
          appleProvider: kReleaseMode ? AppleProvider.appAttest : AppleProvider.debug,
        );
        safeLog("🛡️ App Check (Android/iOS con App Attest)");
      } catch (e) {
        // Fallback a DeviceCheck (iOS antiguo o simulador)
        await FirebaseAppCheck.instance.activate(
          androidProvider: androidProv,
          appleProvider: AppleProvider.deviceCheck,
        );
        safeLog("🛡️ App Check fallback a DeviceCheck");
      }
    }
  } catch (e) {
    safeLog("⚠️ App Check no pudo activarse: $e");
    // No abortamos app: mejor degradar que crashear
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Captura errores de Flutter y reenvía a zona.
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    Zone.current.handleUncaughtError(details.exception, details.stack ?? StackTrace.empty);
  };

  // Captura errores a nivel engine (animaciones/timers/etc.)
  PlatformDispatcher.instance.onError = (error, stack) {
    safeLog("🔥 Platform error: $error\n$stack");
    return true;
  };

  // Pantalla de error amigable (en lugar de "Red screen of death")
  ErrorWidget.builder = (FlutterErrorDetails details) {
    final isRelease = kReleaseMode;
    return Material(
      color: const Color(0xFF121212),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Card(
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: DefaultTextStyle(
                style: const TextStyle(color: Colors.white),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.orange),
                    const SizedBox(height: 12),
                    const Text("Algo salió mal", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(
                      isRelease ? "Por favor, reinicia la app." : details.exceptionAsString(),
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  };

  await runZonedGuarded<Future<void>>(() async {
    try {
      await _initFirebase();
    } catch (e, st) {
      safeLog("❌ Error en init Firebase/App Check: $e\n$st");
    }
    runApp(const MyApp());
  }, (error, stack) {
    safeLog("🔥 Uncaught zone error: $error\n$stack");
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final accent = Colors.greenAccent[400];
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'WINA APP',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF121212),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF1E1E1E),
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
        ),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: accent,
          secondary: accent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF1E1E1E),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: accent!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: accent, width: 2),
          ),
          labelStyle: const TextStyle(color: Colors.white70),
        ),
      ),
      home: const AuthGate(),
    );
  }
}
