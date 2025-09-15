import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'tipster_channel_page.dart';
import 'mi_perfil.dart';
import 'buscar_page.dart';
import 'widgets/user_name.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  bool _esPronostico(dynamic typeField) {
    if (typeField == null) return false;
    final val = typeField.toString().trim().toLowerCase();
    return val == "pronostico";
  }

  // ---- visor imagen + helper sin recortes ----
  void _openImageViewer(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 5,
          child: Center(child: Image.network(url, fit: BoxFit.contain)),
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
          fit: BoxFit.fitWidth,
          errorBuilder: (_, __, ___) => const SizedBox(
            height: 160,
            child: Center(child: Text('⚠️ Imagen no disponible', style: TextStyle(color: Colors.white70))),
          ),
        ),
      ),
    );
  }

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    _pages = [
      // ----------- Pestaña 1: Pronósticos abiertos -----------
      StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collectionGroup('posts')
            .where('status', isEqualTo: 'open')
            .orderBy('postedAt', descending: true)
            .limit(200)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasError) {
            debugPrint("❌ Firestore (posts abiertos): ${snapshot.error}");
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Error cargando pronósticos.',
                  style: TextStyle(color: Colors.redAccent),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'No hay pronósticos abiertos.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          // Nos quedamos solo con type == pronostico
          final posts = snapshot.data!.docs.where((doc) {
            final data = doc.data() as Map<String, dynamic>? ?? {};
            return _esPronostico(data['type']);
          }).toList();

          if (posts.isEmpty) {
            return const Center(
              child: Text(
                'No hay pronósticos abiertos.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          return Column(
            children: [
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
              Expanded(
                child: ListView.builder(
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final p = posts[index].data() as Map<String, dynamic>? ?? {};
                    final tipsterId = p['tipsterId']?.toString() ?? "";
                    if (tipsterId.isEmpty) return const SizedBox();

                    return FutureBuilder<DocumentSnapshot>(
                      future: FirebaseFirestore.instance
                          .collection('canales')
                          .doc(tipsterId)
                          .get(),
                      builder: (context, canalSnap) {
                        if (canalSnap.hasError) return const SizedBox();
                        if (!canalSnap.hasData || !canalSnap.data!.exists) {
                          return const SizedBox();
                        }

                        final canal = canalSnap.data!.data() as Map<String, dynamic>? ?? {};
                        final nombreCanal = (canal['nombre_canal'] ?? 'Canal').toString();
                        final fotoCanal = (canal['foto_canal'] ?? canal['foto'])?.toString();
                        final role = canal['role']?.toString() ?? '';

                        return _buildPronosticoCard(
                          context,
                          p,
                          tipsterId,
                          nombreCanal,
                          fotoCanal,
                          role,
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),

      // ----------- Pestaña 2: Canales que sigues -----------
      Builder(
        builder: (context) {
          final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
          if (uid.isEmpty) {
            return const Center(
              child: Text(
                'Usuario no autenticado.',
                style: TextStyle(color: Colors.white70),
              ),
            );
          }

          final stream = FirebaseFirestore.instance
              .collection('canales')
              .where('seguidores', arrayContains: uid)
              .snapshots();

          return StreamBuilder<QuerySnapshot>(
            stream: stream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                debugPrint("❌ Firestore (canales seguidos): ${snapshot.error}");
                return const Center(
                  child: Text(
                    'No se pudieron cargar tus canales.',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                );
              }

              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return const Center(
                  child: Text(
                    'No sigues ningún canal.',
                    style: TextStyle(color: Colors.white70),
                  ),
                );
              }

              final canales = snapshot.data!.docs;

              return ListView.builder(
                itemCount: canales.length,
                itemBuilder: (context, index) {
                  final c = canales[index].data() as Map<String, dynamic>? ?? {};
                  final tipsterId = canales[index].id;
                  final nombreCanal = (c['nombre_canal'] ?? 'Canal').toString();
                  final fotoCanal = (c['foto_canal'] ?? c['foto'])?.toString();
                  final role = c['role']?.toString() ?? '';

                  return ListTile(
                    tileColor: const Color(0xFF1E1E1E),
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundImage: (fotoCanal != null && fotoCanal.isNotEmpty)
                          ? NetworkImage(fotoCanal)
                          : null,
                      child: (fotoCanal == null || fotoCanal.isEmpty)
                          ? const Icon(Icons.person, size: 28, color: Colors.white70)
                          : null,
                    ),
                    title: UserName(name: nombreCanal, role: role),
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
        },
      ),

      // ----------- Pestaña 3: Buscar -----------
      const BuscarPage(),
    ];
  }

  // 🔹 Tarjeta de pronóstico
  Widget _buildPronosticoCard(
    BuildContext context,
    Map<String, dynamic> p,
    String tipsterId,
    String nombreCanal,
    String? fotoCanal,
    String role,
  ) {
    final stake = (p['stake'] is num)
        ? (p['stake'] as num).toDouble()
        : double.tryParse(p['stake']?.toString() ?? "") ?? 0.0;

    return Card(
      color: const Color(0xFF1E1E1E),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                      backgroundImage:
                          (fotoCanal != null && fotoCanal.isNotEmpty) ? NetworkImage(fotoCanal) : null,
                      child: (fotoCanal == null || fotoCanal.isEmpty)
                          ? const Icon(Icons.person, size: 22, color: Colors.white70)
                          : null,
                    ),
                    const SizedBox(width: 8),
                    UserName(name: nombreCanal, role: role),
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
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => TipsterChannelPage(tipsterId: tipsterId),
                      ),
                    );
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
                Text("${p['evento'] ?? ''} (${p['sport'] ?? ''})",
                    style: const TextStyle(fontSize: 14, color: Colors.white70)),
                const SizedBox(height: 8),
                Text(
                  "${p['seleccion'] ?? ''}",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                if (p['imageUrl'] != null && (p['imageUrl'] as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _postImage(p['imageUrl']),
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
                            "Stake ${p['stake'] ?? '-'}",
                            style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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
                              (stake >= 6 && stake <= 10)
                                  ? "Máxima"
                                  : (stake >= 3 && stake <= 5)
                                      ? "Alta"
                                      : (stake >= 1 && stake <= 2)
                                          ? "Media"
                                          : "Baja",
                              style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
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
                              "${p['cuota'] ?? '-'}",
                              style: const TextStyle(
                                fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
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
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        elevation: 0,
        centerTitle: true,
        title: Image.asset("assets/images/logo.png", height: 40),
        actions: [
          IconButton(
            icon: Icon(Icons.person, color: Colors.greenAccent[400]),
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const MiPerfilPage()));
            },
          ),
        ],
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: Colors.greenAccent[400],
        unselectedItemColor: Colors.greenAccent[400]!.withOpacity(0.5),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.sports_soccer), label: 'Pronósticos'),
          BottomNavigationBarItem(icon: Icon(Icons.campaign), label: 'Canales que sigo'),
          BottomNavigationBarItem(icon: Icon(Icons.search), label: 'Buscar'),
        ],
      ),
    );
  }
}
