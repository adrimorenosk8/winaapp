import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'home_page.dart';
import 'login_page.dart';
import 'tipster_main.dart'; // aquí está TipsterMainPage

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
        debugPrint("🔑 Usuario logueado con UID: $uid");

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

        final data = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
        final role = (data['role'] ?? 'user').toString().toLowerCase();

        debugPrint("✅ Firestore leído UID: $uid");
        debugPrint("📩 Datos: $data");
        debugPrint("🎭 Rol detectado: $role");

        if (role == 'tipster') {
          debugPrint("➡️ Entrando a TipsterMainPage");
          return const TipsterMainPage(); // 👈 tu clase
        } else {
          debugPrint("➡️ Entrando a HomePage (usuario normal)");
          return const HomePage();
        }
      },
    );
  }
}
