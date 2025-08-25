// auth_gate.dart
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
          return const _LoadingScaffold();
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

class _UserRoleGate extends StatefulWidget {
  final String uid;
  const _UserRoleGate({super.key, required this.uid});

  @override
  State<_UserRoleGate> createState() => _UserRoleGateState();
}

class _UserRoleGateState extends State<_UserRoleGate> {
  late final DocumentReference<Map<String, dynamic>> _userRef;

  @override
  void initState() {
    super.initState();
    _userRef = FirebaseFirestore.instance.collection('users').doc(widget.uid);
  }

  /// Crea users/{uid} si no existe, con role: "user".
  /// Compatible con las reglas: no permite elevar rol.
  Future<void> _ensureUserDoc() async {
    try {
      final snap = await _userRef.get();
      if (!snap.exists) {
        final email = FirebaseAuth.instance.currentUser?.email;
        debugPrint("🧾 users/${widget.uid} no existe. Creando con role='user'…");
        await _userRef.set({
          'role': 'user',
          'email': email,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        debugPrint("✅ users/${widget.uid} creado.");
      }
    } on FirebaseException catch (e) {
      debugPrint("❌ Error asegurando users/${widget.uid}: ${e.code} - ${e.message}");
      rethrow;
    } catch (e) {
      debugPrint("❌ Error inesperado asegurando users/${widget.uid}: $e");
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    // 1) Asegurar que el doc existe (una sola vez)
    return FutureBuilder<void>(
      future: _ensureUserDoc(),
      builder: (context, ensureSnap) {
        if (ensureSnap.connectionState == ConnectionState.waiting) {
          return const _LoadingScaffold();
        }
        if (ensureSnap.hasError) {
          final err = ensureSnap.error;
          return _ErrorScaffold(
            title: "No se puede preparar tu perfil",
            message: _friendlyError(err),
            action: _SignOutButton(onDone: () async {
              try {
                await FirebaseAuth.instance.signOut();
              } catch (_) {}
            }),
          );
        }

        // 2) Escuchar el doc para reaccionar a cambios de rol en caliente
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _userRef.snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingScaffold();
            }

            if (userSnapshot.hasError) {
              return _ErrorScaffold(
                title: "No se puede leer tu perfil",
                message: _friendlyError(userSnapshot.error),
                action: _SignOutButton(onDone: () async {
                  try {
                    await FirebaseAuth.instance.signOut();
                  } catch (_) {}
                }),
              );
            }

            if (!userSnapshot.hasData || !userSnapshot.data!.exists) {
              debugPrint("⚠️ No existe users/${widget.uid} (borrado) → LoginPage");
              return const LoginPage();
            }

            // 🔎 Datos del usuario
            final data = userSnapshot.data!.data() ?? {};
            debugPrint("📩 users/${widget.uid} leído: $data");

            final roleRaw = data['role'];
            final role = (roleRaw ?? 'user').toString().toLowerCase().trim();

            // Seguridad defensiva: solo roles conocidos
            const allowedRoles = {'user', 'tipster'};
            final effectiveRole = allowedRoles.contains(role) ? role : 'user';

            debugPrint("🎭 role raw: $roleRaw → efectivo: '$effectiveRole'");

            // 👑 Caso tipster
            if (effectiveRole == 'tipster') {
              return _TipsterGate(uid: widget.uid);
            }

            // 👤 Usuario normal
            debugPrint("➡️ Entrando a HomePage (usuario normal)");
            return const HomePage();
          },
        );
      },
    );
  }
}

class _TipsterGate extends StatelessWidget {
  final String uid;
  const _TipsterGate({super.key, required this.uid});

  @override
  Widget build(BuildContext context) {
    final canalRef = FirebaseFirestore.instance.collection('canales').doc(uid);

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: canalRef.snapshots(),
      builder: (context, canalSnapshot) {
        if (canalSnapshot.connectionState == ConnectionState.waiting) {
          return const _LoadingScaffold();
        }

        if (canalSnapshot.hasError) {
          return _ErrorScaffold(
            title: "No se puede acceder a tu canal",
            message: _friendlyError(canalSnapshot.error),
            action: _SignOutButton(onDone: () async {
              try {
                await FirebaseAuth.instance.signOut();
              } catch (_) {}
            }),
          );
        }

        final hasChannel = canalSnapshot.hasData && canalSnapshot.data!.exists;

        if (hasChannel) {
          debugPrint("📡 Canal encontrado en 'canales/$uid' → TipsterMainPage");
          return const TipsterMainPage();
        } else {
          debugPrint("🆕 No existe canal en 'canales/$uid' → CreateChannelPage");
          // CreateChannelPage debe crear canales/{uid} con: { idTipster: uid, ... }
          return CreateChannelPage(
            uid: uid,
            email: FirebaseAuth.instance.currentUser?.email ?? '',
          );
        }
      },
    );
  }
}

class _LoadingScaffold extends StatelessWidget {
  const _LoadingScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: const Center(
        child: CircularProgressIndicator(color: Colors.greenAccent),
      ),
    );
  }
}

class _ErrorScaffold extends StatelessWidget {
  final String title;
  final String message;
  final Widget? action;

  const _ErrorScaffold({
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            color: const Color(0xFF1E1E1E),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 48, color: Colors.white70),
                  const SizedBox(height: 16),
                  Text(title,
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 8),
                  Text(message, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  if (action != null) SizedBox(width: double.infinity, child: action!),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignOutButton extends StatelessWidget {
  final VoidCallback onDone;
  const _SignOutButton({required this.onDone});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      onPressed: onDone,
      icon: const Icon(Icons.logout),
      label: const Text("Cerrar sesión"),
    );
  }
}

String _friendlyError(Object? err) {
  if (err is FirebaseException) {
    if (err.code == 'permission-denied') {
      return "Tu cuenta no tiene permisos para esta acción según las reglas de seguridad.";
    }
    if (err.code == 'not-found') {
      return "El recurso solicitado no existe.";
    }
    return "Error de Firebase (${err.code}): ${err.message ?? 'Sin detalles'}";
  }
  return "Ha ocurrido un error inesperado. Inténtalo de nuevo.";
}
