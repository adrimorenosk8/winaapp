import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'tipster_channel_page.dart';
import 'widgets/user_name.dart'; // 👈 usamos también el widget global

class TipsterFeedPage extends StatelessWidget {
  const TipsterFeedPage({super.key});

  Future<List<Map<String, dynamic>>> _getPronosticos() async {
    final List<Map<String, dynamic>> pronosticos = [];

    final canalesSnap =
        await FirebaseFirestore.instance.collection('canales').get();

    for (final canalDoc in canalesSnap.docs) {
      final canalId = canalDoc.id;
      final canalData = canalDoc.data();

      final canalNombre = canalData['nombre_canal'] ?? 'Canal sin nombre';
      final canalFoto = canalData['foto_canal'];
      final role = canalData['role'] ?? ''; // 👈 añadimos role

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
        data['role'] = role;
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
        children: [
          // 🔹 Encabezado estilo HomePage
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: Column(
                children: [
                  const Text(
                    "📌 PRONÓSTICOS DEL DÍA",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 180,
                    height: 2,
                    color: Colors.greenAccent[400],
                  ),
                ],
              ),
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
                    child: Text(
                      "Error: ${snapshot.error}",
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  );
                }
                final pronosticos = snapshot.data ?? [];

                if (pronosticos.isEmpty) {
                  return const Center(
                    child: Text(
                      "No hay pronósticos abiertos.",
                      style: TextStyle(color: Colors.white70),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: pronosticos.length,
                  itemBuilder: (context, index) {
                    final p = pronosticos[index];
                    final evento = p['evento'] ?? 'Evento desconocido';
                    final cuota = p['cuota']?.toString() ?? '-';
                    final stakeVal = p['stake'];
                    final stake = stakeVal != null ? stakeVal.toString() : '-';
                    final seleccion = p['seleccion'] ?? '-';
                    final canalNombre = p['canalNombre'] ?? 'Canal';
                    final canalFoto = p['canalFoto'];
                    final role = p['role'] ?? '';
                    final imageUrl = p['imageUrl'];

                    // 🔹 Calcular confianza como en HomePage
                    double stakeNum = 0;
                    if (stakeVal is num) {
                      stakeNum = stakeVal.toDouble();
                    } else {
                      stakeNum = double.tryParse(stakeVal.toString()) ?? 0;
                    }
                    String confianza = "Baja";
                    if (stakeNum >= 1 && stakeNum <= 2) {
                      confianza = "Media";
                    } else if (stakeNum >= 3 && stakeNum <= 5) {
                      confianza = "Alta";
                    } else if (stakeNum >= 6 && stakeNum <= 10) {
                      confianza = "Máxima";
                    }

                    return Card(
                      color: const Color(0xFF1E1E1E),
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 🔹 Encabezado Canal
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundImage: canalFoto != null
                                          ? NetworkImage(canalFoto)
                                          : null,
                                      child: canalFoto == null
                                          ? const Icon(Icons.person,
                                              size: 22, color: Colors.white70)
                                          : null,
                                    ),
                                    const SizedBox(width: 8),
                                    UserName(
                                      name: canalNombre,
                                      role: role,
                                    ),
                                  ],
                                ),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 6),
                                    side: BorderSide(
                                        color: Colors.greenAccent[400]!),
                                    foregroundColor: Colors.greenAccent[400],
                                    textStyle: const TextStyle(fontSize: 13),
                                  ),
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => TipsterChannelPage(
                                            tipsterId: p['canalId']),
                                      ),
                                    );
                                  },
                                  child: const Text("Visitar"),
                                ),
                              ],
                            ),
                          ),

                          // 🔹 Bloque principal
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "$evento",
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: Colors.white70,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  seleccion,
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (imageUrl != null &&
                                    (imageUrl as String).isNotEmpty)
                                  Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 14),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        imageUrl,
                                        height: 160,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        height: 60,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.withOpacity(0.25),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Center(
                                          child: Text(
                                            "Stake $stake",
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Container(
                                        height: 60,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withOpacity(0.25),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Text(
                                              "Confianza",
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.white70,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              confianza,
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: Container(
                                        height: 60,
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 4),
                                        decoration: BoxDecoration(
                                          color:
                                              Colors.green.withOpacity(0.25),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Column(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            const Text(
                                              "Cuota",
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.white70,
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              cuota,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
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
