import 'dart:async';
import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData; // 👈 para copiar token
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';

// 👇 nuevo: para loguear el token
import 'package:firebase_messaging/firebase_messaging.dart';

import 'firebase_options.dart';
import 'auth_gate.dart';

// 👇 Push notifications (nuevo)
import 'push_notifications.dart';
import 'tipster_channel_page.dart'; // para la ruta '/canal'

/// Logging seguro (silencio en release) + recorte.
void safeLog(String message) {
  if (kReleaseMode) return;
  const max = 1000;
  debugPrint(message.length > max ? "${message.substring(0, max)}…" : message);
}

/// Lee la site key desde variable de entorno (--dart-define) o usa un placeholder.
const String kRecaptchaSiteKey =
    String.fromEnvironment('RECAPTCHA_V3_SITE_KEY', defaultValue: 'RECAPTCHA_V3_SITE_KEY');

// 👇 Navigator global para abrir pantallas desde una notificación
final navigatorKey = GlobalKey<NavigatorState>();

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
      // 👇 Inicializa FCM + notificaciones locales (abre pantallas vía navigatorKey)
      await initPushNotifications(navKey: navigatorKey);

      // 🔑 Log del token (sólo para depurar)
      try {
        final token = await FirebaseMessaging.instance.getToken();
        debugPrint("🔑 FCM token (main): $token");
      } catch (e) {
        debugPrint("⚠️ No pude obtener el token FCM: $e");
      }
    } catch (e, st) {
      safeLog("❌ Error en init Firebase/App Check/Push: $e\n$st");
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
      navigatorKey: navigatorKey, // 👈 necesario para abrir canales al tocar notificaciones
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

      // ✅ Overlay con botón flotante para ver/copiar el token FCM
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            // Muestra el botón sólo en dispositivos móviles (no web/desktop)
            if (!kIsWeb)
              Positioned(
                right: 16,
                bottom: 16,
                child: _FcmTokenFab(),
              ),
          ],
        );
      },

      // 👇 ruta profunda para abrir un canal desde una notificación (payload tipsterId)
      onGenerateRoute: (settings) {
        if (settings.name == '/canal') {
          final tipsterId = settings.arguments as String;
          return MaterialPageRoute(
            builder: (_) => TipsterChannelPage(tipsterId: tipsterId),
          );
        }
        return null;
      },
      home: const AuthGate(),
    );
  }
}

/// FAB que abre un diálogo con el token FCM y opción de copiar.
class _FcmTokenFab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FloatingActionButton.extended(
      heroTag: 'fcm_fab',
      onPressed: () => _showFcmTokenDialog(context),
      icon: const Icon(Icons.vpn_key),
      label: const Text('Token FCM'),
    );
  }
}

Future<void> _showFcmTokenDialog(BuildContext context) async {
  final token = await FirebaseMessaging.instance.getToken();
  // También intentamos APNs (iOS) para diagnóstico
  String? apns;
  try {
    apns = await FirebaseMessaging.instance.getAPNSToken();
  } catch (_) {}

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return AlertDialog(
        title: const Text('Token FCM'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                token ?? 'Aún no hay token.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              if (apns != null) ...[
                const Text('APNs token (iOS):', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SelectableText(apns, style: const TextStyle(fontSize: 13)),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: (token == null || token.isEmpty)
                ? null
                : () async {
                    await Clipboard.setData(ClipboardData(text: token));
                    Navigator.of(ctx).pop();
                    ScaffoldMessenger.of(navigatorKey.currentContext ?? context).showSnackBar(
                      const SnackBar(content: Text('Token copiado al portapapeles')),
                    );
                  },
            child: const Text('Copiar'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      );
    },
  );
}
