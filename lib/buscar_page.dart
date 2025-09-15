import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:rxdart/rxdart.dart';
import 'package:string_similarity/string_similarity.dart';
import 'tipster_channel_page.dart';

class BuscarPage extends StatefulWidget {
  const BuscarPage({super.key});

  @override
  State<BuscarPage> createState() => _BuscarPageState();
}

class _BuscarPageState extends State<BuscarPage> {
  String _query = "";

  @override
  Widget build(BuildContext context) {
    final queryLower = _sanitizeInput(_query);

    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 🔎 Barra de búsqueda
          TextField(
            style: const TextStyle(color: Colors.white),
            onChanged: (val) => setState(() => _query = val.trim()),
            decoration: InputDecoration(
              hintText: "Buscar canal...",
              hintStyle: const TextStyle(color: Colors.white54),
              filled: true,
              fillColor: const Color(0xFF1E1E1E),
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          const SizedBox(height: 20),

          Expanded(
            child: queryLower.isEmpty
                ? const Center(
                    child: Text("Escribe el nombre de un canal...",
                        style: TextStyle(color: Colors.white54)),
                  )
                : StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
                    stream: _searchStream(queryLower),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        debugPrint("❌ Error en búsqueda: ${snapshot.error}");
                        return const Center(
                          child: Text("Error en la búsqueda",
                              style: TextStyle(color: Colors.white54)),
                        );
                      }

                      final docs = snapshot.data ?? const [];
                      if (docs.isEmpty) {
                        return const Center(
                          child: Text("No se encontraron canales.",
                              style: TextStyle(color: Colors.white54)),
                        );
                      }

                      // Filtrado + ranking por similitud (en memoria)
                      final scored = <(_Canal, double)>[];
                      for (final d in docs) {
                        final data = d.data();
                        final nombre = (data['nombre_canal'] ?? '').toString().trim();
                        final nombreLower =
                            (data['nombre_canal_lower'] ?? nombre.toLowerCase())
                                .toString()
                                .trim();
                        if (nombreLower.isEmpty) continue;

                        final score = nombreLower.similarityTo(queryLower);
                        final matches = nombreLower.contains(queryLower) || score >= 0.45;
                        if (matches) {
                          scored.add((
                            _Canal(
                              id: d.id,
                              nombre: nombre.isEmpty ? 'Canal' : nombre,
                              foto: (data['foto_canal'] ?? data['foto'])?.toString() ?? '',
                            ),
                            score
                          ));
                        }
                      }

                      if (scored.isEmpty) {
                        return const Center(
                          child: Text("No se encontraron resultados similares.",
                              style: TextStyle(color: Colors.white54)),
                        );
                      }

                      scored.sort((a, b) => b.$2.compareTo(a.$2)); // mayor similitud primero
                      final canales = scored.map((e) => e.$1).toList();

                      return ListView.builder(
                        itemCount: canales.length,
                        itemBuilder: (context, index) {
                          final c = canales[index];
                          return ListTile(
                            tileColor: const Color(0xFF1E1E1E),
                            leading: CircleAvatar(
                              radius: 24,
                              backgroundImage: c.foto.isNotEmpty ? NetworkImage(c.foto) : null,
                              child: c.foto.isEmpty
                                  ? const Icon(Icons.person, size: 28, color: Colors.white70)
                                  : null,
                            ),
                            title: Text(
                              c.nombre,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => TipsterChannelPage(tipsterId: c.id),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 🔎 Stream seguro: unimos públicos + los que sigues (evita permisos/índices)
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _searchStream(String input) {
    final db = FirebaseFirestore.instance;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    final pubStream = db
        .collection('canales')
        .where('isPublic', isEqualTo: true)
        .limit(100)
        .snapshots()
        .map((s) => s.docs)
        .onErrorReturnWith((_, __) => <QueryDocumentSnapshot<Map<String, dynamic>>>[]);

    final followedStream = (uid == null || uid.isEmpty)
        ? Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>.value(const [])
        : db
            .collection('canales')
            .where('seguidores', arrayContains: uid)
            .limit(100)
            .snapshots()
            .map((s) => s.docs)
            .onErrorReturnWith((_, __) => <QueryDocumentSnapshot<Map<String, dynamic>>>[]);

    return Rx.combineLatest2(pubStream, followedStream,
        (List<QueryDocumentSnapshot<Map<String, dynamic>>> a,
            List<QueryDocumentSnapshot<Map<String, dynamic>>> b) {
      final map = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
      for (final d in a) map[d.id] = d;
      for (final d in b) map[d.id] = d;
      return map.values.toList();
    });
  }

  static String _sanitizeInput(String input) {
    final trimmed = input.trim().toLowerCase();
    final regex = RegExp(r'^[a-z0-9áéíóúüñ\s\-_.,]{0,50}$');
    return regex.hasMatch(trimmed) ? trimmed : '';
  }
}

class _Canal {
  final String id;
  final String nombre;
  final String foto;
  _Canal({required this.id, required this.nombre, required this.foto});
}
