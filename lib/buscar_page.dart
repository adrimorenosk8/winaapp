import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:string_similarity/string_similarity.dart'; // 👈 Añadir en pubspec.yaml
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
    final queryLower = _query.toLowerCase();

    return Container(
      color: const Color(0xFF121212),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 🔹 Barra de búsqueda
          TextField(
            style: const TextStyle(color: Colors.white),
            onChanged: (val) {
              setState(() {
                _query = val.trim();
              });
            },
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

          // 🔹 Resultados dinámicos
          Expanded(
            child: _query.isEmpty
                ? const Center(
                    child: Text(
                      "Escribe el nombre de un canal...",
                      style: TextStyle(color: Colors.white54),
                    ),
                  )
                : StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('canales')
                        .where('nombre_canal_lower',
                            isGreaterThanOrEqualTo: queryLower,
                            isLessThanOrEqualTo: '$queryLower\uf8ff')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState ==
                          ConnectionState.waiting) {
                        return const Center(
                            child: CircularProgressIndicator());
                      }

                      if (!snapshot.hasData ||
                          snapshot.data!.docs.isEmpty) {
                        return const Center(
                          child: Text(
                            "No se encontraron canales.",
                            style: TextStyle(color: Colors.white54),
                          ),
                        );
                      }

                      final canales = snapshot.data!.docs.where((doc) {
                        final canalData =
                            doc.data() as Map<String, dynamic>;
                        final nombreLower =
                            (canalData['nombre_canal'] ?? '')
                                .toString()
                                .toLowerCase();

                        // 🔹 Coincidencia aproximada: aceptamos si similitud > 0.4
                        final score = nombreLower.similarityTo(queryLower);
                        return score > 0.4;
                      }).toList();

                      if (canales.isEmpty) {
                        return const Center(
                          child: Text(
                            "No se encontraron resultados similares.",
                            style: TextStyle(color: Colors.white54),
                          ),
                        );
                      }

                      return ListView.builder(
                        itemCount: canales.length,
                        itemBuilder: (context, index) {
                          final canalData =
                              canales[index].data() as Map<String, dynamic>;
                          final tipsterId = canales[index].id;
                          final nombreCanal =
                              canalData['nombre_canal'] ?? 'Canal';
                          final fotoCanal = canalData['foto_canal'];

                          return ListTile(
                            tileColor: const Color(0xFF1E1E1E),
                            leading: CircleAvatar(
                              radius: 24,
                              backgroundImage: fotoCanal != null
                                  ? NetworkImage(fotoCanal)
                                  : null,
                              child: fotoCanal == null
                                  ? const Icon(Icons.person,
                                      size: 28, color: Colors.white70)
                                  : null,
                            ),
                            title: Text(
                              nombreCanal,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      TipsterChannelPage(tipsterId: tipsterId),
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
}
