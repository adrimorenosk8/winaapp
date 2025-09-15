import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'widgets/user_name.dart';
import 'tipster_channel_page.dart';

// ---------- Helpers de sanitización ----------
String sanitizeString(dynamic value, {String defaultValue = ''}) {
  if (value == null) return defaultValue;
  if (value is! String) return defaultValue;
  return value.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
}

double sanitizeDouble(dynamic value, {double defaultValue = 0}) {
  if (value == null) return defaultValue;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? defaultValue;
}

bool _isValidHttpUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final u = Uri.tryParse(url);
  return u != null && (u.scheme == 'http' || u.scheme == 'https');
}

bool _isPronostico(dynamic typeField) {
  if (typeField == null) return false;
  final v = typeField.toString().trim().toLowerCase();
  return v == 'pronostico';
}

class TipsterFeedPage extends StatefulWidget {
  const TipsterFeedPage({super.key});

  @override
  State<TipsterFeedPage> createState() => _TipsterFeedPageState();
}

class _TipsterFeedPageState extends State<TipsterFeedPage> {
  // Caché de canales para evitar lecturas repetidas
  final Map<String, Future<DocumentSnapshot<Map<String, dynamic>>>> _canalCache = {};

  // ❌ Sin "type == pronostico" en la query → evitamos índice compuesto
  Stream<QuerySnapshot<Map<String, dynamic>>> _postsStream() {
    return FirebaseFirestore.instance
        .collectionGroup('posts')
        .where('status', isEqualTo: 'open')
        .orderBy('postedAt', descending: true)
        .limit(200)
        .snapshots();
  }

  // ---- Visor de imagen a pantalla completa ----
  void _openImageViewer(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Center(
            child: Image.network(
              url,
              fit: BoxFit.contain,
              errorBuilder: (_, __, ___) => const Padding(
                padding: EdgeInsets.all(24),
                child: Text('⚠️ Imagen no disponible', style: TextStyle(color: Colors.white70)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _postImage(String url) {
    return GestureDetector(
      onTap: () => _openImageViewer(url),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(
          url,
          width: double.infinity,
          fit: BoxFit.fitWidth, // 👈 sin recortes
          errorBuilder: (_, __, ___) => const SizedBox(
            height: 160,
            child: Center(
              child: Text('⚠️ Imagen no disponible', style: TextStyle(color: Colors.white70)),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF121212),
      child: Column(
        children: [
          // Encabezado
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
                  Container(width: 180, height: 2, color: Colors.greenAccent[400]),
                ],
              ),
            ),
          ),

          // Lista de pronósticos (stream en tiempo real)
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _postsStream(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: Colors.greenAccent));
                }
                if (snapshot.hasError) {
                  // Si ves esto, suele ser por índices/permiso. Con esta query no debería pedirse índice.
                  return const Center(
                    child: Text("Error al cargar datos.", style: TextStyle(color: Colors.redAccent)),
                  );
                }

                // Filtramos type == pronostico en memoria (evita índice)
                final allDocs = snapshot.data?.docs ?? const [];
                final docs = allDocs.where((d) => _isPronostico(d.data()['type'])).toList();
                if (docs.isEmpty) {
                  return const Center(
                    child: Text("No hay pronósticos abiertos.", style: TextStyle(color: Colors.white70)),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data();

                    // Campos del post (sanitizados)
                    final tipsterId = sanitizeString(data['tipsterId']);
                    if (tipsterId.isEmpty) return const SizedBox.shrink();

                    final evento = sanitizeString(data['evento'], defaultValue: 'Evento desconocido');
                    final seleccion = sanitizeString(data['seleccion'], defaultValue: '-');
                    final cuotaNum = sanitizeDouble(data['cuota']);
                    final cuota = cuotaNum > 0 ? cuotaNum.toString() : '-';
                    final stakeNum = sanitizeDouble(data['stake']);
                    final stake = stakeNum > 0 ? stakeNum.toString() : '-';
                    final imageUrl = _isValidHttpUrl(data['imageUrl'] is String ? data['imageUrl'] as String : null)
                        ? data['imageUrl'] as String
                        : null;

                    // Confianza según stake
                    String confianza = "Baja";
                    if (stakeNum >= 1 && stakeNum <= 2) {
                      confianza = "Media";
                    } else if (stakeNum >= 3 && stakeNum <= 5) {
                      confianza = "Alta";
                    } else if (stakeNum >= 6 && stakeNum <= 10) {
                      confianza = "Máxima";
                    }

                    // Traer info del canal (una vez por tipsterId)
                    final future = _canalCache.putIfAbsent(
                      tipsterId,
                      () => FirebaseFirestore.instance.collection('canales').doc(tipsterId).get(),
                    );

                    return FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      future: future,
                      builder: (context, canalSnap) {
                        String canalNombre = 'Canal';
                        String? canalFoto;
                        String role = '';

                        // Si canal privado / sin permisos -> omitimos avatar/role (pero mostramos el post)
                        if (canalSnap.hasData && (canalSnap.data?.exists ?? false)) {
                          final canal = canalSnap.data!.data() ?? {};
                          canalNombre = sanitizeString(canal['nombre_canal'], defaultValue: 'Canal');
                          final foto = sanitizeString(canal['foto_canal'] ?? canal['foto']);
                          canalFoto = _isValidHttpUrl(foto) ? foto : null;
                          role = sanitizeString(canal['role']);
                        }

                        return Card(
                          color: const Color(0xFF1E1E1E),
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Encabezado Canal
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          radius: 18,
                                          backgroundImage: (canalFoto != null) ? NetworkImage(canalFoto) : null,
                                          child: (canalFoto == null)
                                              ? const Icon(Icons.person, size: 22, color: Colors.white70)
                                              : null,
                                        ),
                                        const SizedBox(width: 8),
                                        UserName(name: canalNombre, role: role),
                                      ],
                                    ),
                                    OutlinedButton(
                                      style: OutlinedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                        side: BorderSide(color: Colors.greenAccent[400]!),
                                        foregroundColor: Colors.greenAccent[400],
                                        textStyle: const TextStyle(fontSize: 13),
                                      ),
                                      onPressed: () {
                                        if (tipsterId.isNotEmpty) {
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) => TipsterChannelPage(tipsterId: tipsterId),
                                            ),
                                          );
                                        }
                                      },
                                      child: const Text("Visitar"),
                                    ),
                                  ],
                                ),
                              ),

                              // Bloque principal
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
                                    Text(evento, style: const TextStyle(fontSize: 14, color: Colors.white70)),
                                    const SizedBox(height: 8),
                                    Text(
                                      seleccion,
                                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                    const SizedBox(height: 12),
                                    if (imageUrl != null)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 14),
                                        child: _postImage(imageUrl), // 👈 sin recortes + visor
                                      ),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Container(
                                            height: 60,
                                            margin: const EdgeInsets.symmetric(horizontal: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.withOpacity(0.25),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Center(
                                              child: Text(
                                                "Stake $stake",
                                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                              ),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Container(
                                            height: 60,
                                            margin: const EdgeInsets.symmetric(horizontal: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withOpacity(0.25),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Text("Confianza", style: TextStyle(fontSize: 12, color: Colors.white70)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  (stakeNum >= 6 && stakeNum <= 10)
                                                      ? "Máxima"
                                                      : (stakeNum >= 3 && stakeNum <= 5)
                                                          ? "Alta"
                                                          : (stakeNum >= 1 && stakeNum <= 2)
                                                              ? "Media"
                                                              : "Baja",
                                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: Container(
                                            height: 60,
                                            margin: const EdgeInsets.symmetric(horizontal: 4),
                                            decoration: BoxDecoration(
                                              color: Colors.green.withOpacity(0.25),
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Column(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                const Text("Cuota", style: TextStyle(fontSize: 12, color: Colors.white70)),
                                                const SizedBox(height: 2),
                                                Text(
                                                  cuota,
                                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
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
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
