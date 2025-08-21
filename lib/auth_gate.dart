import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_page.dart';
import 'login_page.dart';
import 'tipster_main.dart';
import 'create_channel_page.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 🚪 No logueado
        if (!snapshot.hasData) {
          debugPrint("🚪 No hay sesión activa → LoginPage");
          return const LoginPage();
        }

        final uid = snapshot.data!.uid;
        final email = snapshot.data!.email;
        debugPrint("🔑 Usuario logueado con UID: $uid | Email: $email");

        return _UserRoleGate(uid: uid, key: ValueKey(uid));
      },
    );
  }
}

class _UserRoleGate extends StatelessWidget {
  final String uid;

  const _UserRoleGate({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (context, userSnapshot) {
        if (userSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
          debugPrint("⚠️ No existe documento en Firestore para UID: $uid");
          return const LoginPage();
        }

        // 🔎 Datos del usuario
        final data = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
        debugPrint("📩 Documento Firestore leído para UID $uid: $data");

        final roleRaw = data['role'];
        final role = (roleRaw ?? 'user').toString().toLowerCase().trim();

        debugPrint("🎭 Campo role en Firestore: $roleRaw");
        debugPrint("🎭 Rol detectado tras normalizar+trim: '$role' (len=${role.length})");

        // 👑 Caso tipster
        if (role == 'tipster') {
          return _TipsterGate(uid: uid);
        }

        // 👤 Usuario normal
        debugPrint("➡️ Entrando a HomePage (usuario normal)");
        return const HomePage();
      },
    );
  }
}

class _TipsterGate extends StatelessWidget {
  final String uid;

  const _TipsterGate({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance.collection('canales').doc(uid).snapshots(),
      builder: (context, canalSnapshot) {
        if (canalSnapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final hasChannel = canalSnapshot.hasData && canalSnapshot.data!.exists;

        if (hasChannel) {
          debugPrint("📡 Canal encontrado en 'canales/$uid' → TipsterMainPage");
          return const TipsterMainPage();
        } else {
          debugPrint("🆕 No existe canal en 'canales/$uid' → CreateChannelPage");
          return CreateChannelPage(
            uid: uid,
            email: FirebaseAuth.instance.currentUser?.email ?? '',
          );
        }
      },
    );
  }
}
