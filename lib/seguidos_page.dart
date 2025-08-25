import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tipster_channel_page.dart';

class SeguidosPage extends StatelessWidget {
  const SeguidosPage({super.key});

  String _safeString(dynamic v) {
    if (v == null) return "";
    try {
      return v.toString().replaceAll(RegExp(r'[<>]'), '').trim();
    } catch (_) {
      return "";
    }
  }

  String _safeHttps(dynamic v) {
    final s = _safeString(v);
    if (s.isEmpty) return "";
    final uri = Uri.tryParse(s);
    return (uri != null && uri.hasScheme && uri.scheme == 'https') ? s : "";
    // (si usas http en dev, cambia a uri.scheme == 'http' || 'https')
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";

    if (uid.isEmpty) {
      return const Center(
        child: Text(
          'Inicia sesión para ver tus canales.',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    final stream = FirebaseFirestore.instance
        .collection('canales')
        .where('seguidores', arrayContains: uid)
        .limit(100)
        .snapshots();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snap.hasError) {
          // Si alguna doc falla por permisos, Firestore cancela la query completa
          // Mostramos mensaje claro y no exponemos detalles internos.
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'No se pudieron cargar tus canales (permisos).',
                style: TextStyle(color: Colors.redAccent),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }

        final docs = snap.data?.docs ?? const [];
        if (docs.isEmpty) {
          return const Center(
            child: Text(
              'No sigues ningún canal.',
              style: TextStyle(color: Colors.white70),
            ),
          );
        }

        return ListView.builder(
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final data = docs[i].data();
            final tipsterId = docs[i].id;
            final nombre = _safeString(data['nombre_canal'].toString().isNotEmpty
                ? data['nombre_canal']
                : data['nombre']);
            final foto = _safeHttps(data['foto_canal'] ?? data['foto']);

            return ListTile(
              tileColor: const Color(0xFF1E1E1E),
              leading: CircleAvatar(
                radius: 24,
                backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                child: foto.isEmpty
                    ? const Icon(Icons.person, size: 28, color: Colors.white70)
                    : null,
              ),
              title: Text(
                nombre.isEmpty ? 'Canal' : nombre,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TipsterChannelPage(tipsterId: tipsterId),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
