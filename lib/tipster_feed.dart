import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'tipster_channel_page.dart';

class TipsterFeedPage extends StatelessWidget {
  const TipsterFeedPage({super.key});

  Future<List<Map<String, dynamic>>> _getPronosticos() async {
    final List<Map<String, dynamic>> pronosticos = [];

    final canalesSnap = await FirebaseFirestore.instance.collection('canales').get();

    for (final canalDoc in canalesSnap.docs) {
      final canalId = canalDoc.id;
      final canalData = canalDoc.data();

      final canalNombre = canalData['nombre_canal'] ?? 'Canal sin nombre';
      final canalFoto = canalData['foto_canal'];

      final postsSnap = await FirebaseFirestore.instance
          .collection('canales')
          .doc(canalId)
          .collection('posts')
          .where('type', isEqualTo: 'pronostico')
          .where('status', isEqualTo: 'open')
          .get();

      for (final postDoc in postsSnap.docs) {
        final data = postDoc.data();
        data['canalId'] = canalId;
        data['canalNombre'] = canalNombre;
        data['canalFoto'] = canalFoto;
        pronosticos.add(data);
      }
    }

    return pronosticos;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF121212),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔹 Encabezado PRONÓSTICOS estilizado
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 4,
                  height: 24,
                  decoration: BoxDecoration(
                    color: Colors.greenAccent[400],
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  "PRONÓSTICOS",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),

          // 🔹 Lista de pronósticos
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _getPronosticos(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.greenAccent),
                  );
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text("Error: ${snapshot.error}",
                        style: const TextStyle(color: Colors.redAccent)),
                  );
                }
                final pronosticos = snapshot.data ?? [];

                if (pronosticos.isEmpty) {
                  return const Center(
                    child: Text(
                      "No hay pronósticos abiertos",
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: pronosticos.length,
                  itemBuilder: (context, index) {
                    final p = pronosticos[index];
                    final evento = p['evento'] ?? 'Evento desconocido';
                    final cuota = p['cuota']?.toString() ?? '-';
                    final stake = p['stake']?.toString() ?? '-';
                    final seleccion = p['seleccion'] ?? '-';
                    final canalNombre = p['canalNombre'] ?? 'Canal';
                    final canalFoto = p['canalFoto'];
                    final imageUrl = p['imageUrl']; // 👈 recogemos la foto

                    return Card(
                      color: const Color(0xFF1E1E1E),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                      margin: const EdgeInsets.symmetric(vertical: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Evento (texto normal)
                            Text(
                              evento,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                                fontWeight: FontWeight.normal,
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Selección (en negrita)
                            Text(
                              seleccion,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 12),

                            // Cuota + Stake con iconos
                            Row(
                              children: [
                                Icon(Icons.trending_up,
                                    size: 18, color: Colors.greenAccent[400]),
                                const SizedBox(width: 6),
                                Text(
                                  "Cuota $cuota",
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 14),
                                ),
                                const SizedBox(width: 20),
                                Icon(Icons.shield,
                                    size: 18, color: Colors.blueAccent),
                                const SizedBox(width: 6),
                                Text(
                                  "Stake $stake",
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 14),
                                ),
                              ],
                            ),

                            // Imagen de la apuesta (si existe)
                            if (imageUrl != null &&
                                (imageUrl as String).isNotEmpty) ...[
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  imageUrl,
                                  width: double.infinity,
                                  fit: BoxFit.contain, // 🔹 muestra la foto completa
                                ),
                              ),
                            ],

                            const SizedBox(height: 20),

                            // Botón Visitar canal
                            Center(
                              child: ElevatedButton.icon(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.greenAccent[400],
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 24, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                onPressed: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => TipsterChannelPage(
                                        tipsterId: p['canalId'],
                                      ),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.arrow_forward, size: 20),
                                label: const Text(
                                  "Visitar canal",
                                  style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            // Nombre del canal
                            Align(
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 12,
                                    backgroundImage: canalFoto != null
                                        ? NetworkImage(canalFoto)
                                        : null,
                                    backgroundColor: Colors.grey[700],
                                    child: canalFoto == null
                                        ? const Icon(Icons.person,
                                            size: 14, color: Colors.white70)
                                        : null,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    canalNombre,
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
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
