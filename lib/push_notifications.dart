// lib/push_notifications.dart

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ---------------- Local notifications ----------------
final FlutterLocalNotificationsPlugin _fln = FlutterLocalNotificationsPlugin();

const AndroidNotificationChannel _androidChannel = AndroidNotificationChannel(
  'wina_general_channel',
  'WINA Notificaciones',
  description: 'Notificaciones generales y de canales',
  importance: Importance.high,
  playSound: true,
);

// --------------- Background handler (top-level) ---------------
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  // Lógica mínima; no navegues aquí.
}

// --------------- Init principal ---------------
Future<void> initPushNotifications({required GlobalKey<NavigatorState> navKey}) async {
  final fm = FirebaseMessaging.instance;

  // Habilita auto-init (por si se desactivó)
  await fm.setAutoInitEnabled(true);

  // iOS: permisos
  final settings = await fm.requestPermission(alert: true, badge: true, sound: true);
  debugPrint("🔔 Permisos iOS: ${settings.authorizationStatus}"); // 👈 Nuevo log

  // iOS: mostrar banners en foreground
  await fm.setForegroundNotificationPresentationOptions(
    alert: true, badge: true, sound: true,
  );

  // Init de notificaciones locales
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosInit = DarwinInitializationSettings();
  await _fln.initialize(
    const InitializationSettings(android: androidInit, iOS: iosInit),
    onDidReceiveNotificationResponse: (resp) {
      if (resp.payload != null && resp.payload!.isNotEmpty) {
        try {
          final map = jsonDecode(resp.payload!) as Map<String, dynamic>;
          final tipsterId = (map['tipsterId'] as String?) ?? '';
          if (tipsterId.isNotEmpty) {
            navKey.currentState?.pushNamed('/canal', arguments: tipsterId);
          }
        } catch (_) {
          final tipsterId = resp.payload!;
          if (tipsterId.isNotEmpty) {
            navKey.currentState?.pushNamed('/canal', arguments: tipsterId);
          }
        }
      }
    },
  );

  // Crear canal en Android
  await _fln
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_androidChannel);

  // Registrar BG handler
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  // --------- Mensajes en FOREGROUND ----------
  FirebaseMessaging.onMessage.listen((msg) async {
    final n = msg.notification;
    final data = msg.data;

    // ANDROID: mostrar local en foreground
    if (Platform.isAndroid && n != null) {
      await _fln.show(
        n.hashCode,
        n.title,
        n.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            priority: Priority.high,
            importance: Importance.high,
            icon: msg.notification?.android?.smallIcon ?? '@mipmap/ic_launcher',
          ),
        ),
        payload: jsonEncode(data.isNotEmpty ? data : {'tipsterId': data['tipsterId']}),
      );
      return;
    }

    // iOS fallback para data-only con title/body en data
    if (Platform.isIOS && n == null && (data['title'] != null || data['body'] != null)) {
      await _fln.show(
        msg.hashCode,
        data['title'] as String?,
        data['body'] as String?,
        const NotificationDetails(
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: jsonEncode(data),
      );
    }
  });

  // --------- App en background → usuario toca notificación ----------
  FirebaseMessaging.onMessageOpenedApp.listen((msg) {
    _handleNavigation(navKey, msg.data);
  });

  // --------- App terminada → lanzada desde notificación ----------
  final initial = await fm.getInitialMessage();
  if (initial != null) {
    _handleNavigation(navKey, initial.data);
  }

  // Guarda token (haya o no usuario logueado)
  await saveFcmTokenToFirestore();

  // Actualiza en rotación
  FirebaseMessaging.instance.onTokenRefresh.listen((_) => saveFcmTokenToFirestore());

  // Log útil
  final token = await fm.getToken();
  debugPrint('🔑 FCM token (init): $token');
}

void _handleNavigation(GlobalKey<NavigatorState> navKey, Map<String, dynamic> data) {
  final tipsterId = data['tipsterId']?.toString() ?? '';
  if (tipsterId.isNotEmpty) {
    navKey.currentState?.pushNamed('/canal', arguments: tipsterId);
  }
}

// ---------- Utilidades de token ----------
Future<String?> getFcmToken() => FirebaseMessaging.instance.getToken();

/// Botón rápido para copiar el token y ver si existe en ese dispositivo.
class CopyFcmTokenButton extends StatelessWidget {
  const CopyFcmTokenButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.vpn_key),
      onPressed: () async {
        final t = await getFcmToken();
        if (t == null || t.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Aún no hay token FCM (revisa permisos/APNs)')),
          );
          return;
        }
        await Clipboard.setData(ClipboardData(text: t));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Token copiado: ${t.substring(0, 8)}…')),
        );
        if (kDebugMode) debugPrint('🔑 (copied) $t');
      },
      tooltip: 'Copiar token FCM',
    );
  }
}

// ---------- Guardado del token (ahora SIEMPRE guarda) ----------
Future<void> saveFcmTokenToFirestore() async {
  final fcmToken = await FirebaseMessaging.instance.getToken();
  if (fcmToken == null || fcmToken.isEmpty) return;

  // iOS: intenta capturar el APNs token (para diagnosticar)
  String? apnsToken;
  if (Platform.isIOS) {
    try {
      apnsToken = await FirebaseMessaging.instance.getAPNSToken();
    } catch (_) {}
  }

  final uid = FirebaseAuth.instance.currentUser?.uid;

  final now = FieldValue.serverTimestamp();
  final base = {
    'token': fcmToken,
    'platform': Platform.isIOS ? 'ios' : 'android',
    'uid': uid,
    'updatedAt': now,
    if (apnsToken != null) 'apnsToken': apnsToken,
  };

  final db = FirebaseFirestore.instance;

  // A) Colección global por dispositivo (siempre)
  await db.collection('deviceFcmTokens').doc(fcmToken).set(base, SetOptions(merge: true));

  // B) Si hay usuario, mantenemos tu estructura por usuario (opcional)
  if (uid != null) {
    await db.collection('users').doc(uid).set({
      'lastFcmToken': fcmToken,
      'lastFcmTokenUpdatedAt': now,
      if (apnsToken != null) 'apnsToken': apnsToken,
    }, SetOptions(merge: true));

    await db.collection('users').doc(uid).collection('fcmTokens').doc(fcmToken).set({
      'createdAt': now,
      'platform': Platform.operatingSystem,
      'appVersion': '1.0.0',
      if (apnsToken != null) 'apnsToken': apnsToken,
    }, SetOptions(merge: true));
  }
}

// ---- Suscripción a topics por canal ----
Future<void> subscribeCanalTopic(String tipsterId) async =>
    FirebaseMessaging.instance.subscribeToTopic('canal_$tipsterId');

Future<void> unsubscribeCanalTopic(String tipsterId) async =>
    FirebaseMessaging.instance.unsubscribeFromTopic('canal_$tipsterId');
