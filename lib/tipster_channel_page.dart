import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:wina/tipster_channel_info.dart';

class TipsterChannelPage extends StatefulWidget {
  final String tipsterId;
  const TipsterChannelPage({super.key, required this.tipsterId});

  @override
  State<TipsterChannelPage> createState() => _TipsterChannelPageState();
}

class _TipsterChannelPageState extends State<TipsterChannelPage> {
  final Set<String> _alreadyMarked = {};
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Scroll al final al entrar
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      Future.delayed(const Duration(milliseconds: 200), () {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 60, // margen extra abajo
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      return DateFormat.Hm().format(dt);
    } else if (dt.year == now.year) {
      return DateFormat("d MMM").format(dt);
    } else {
      return DateFormat("d MMM y").format(dt);
    }
  }

  Future<void> _markAsViewed(String postId, List viewedBy) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    if (viewedBy.contains(uid) || _alreadyMarked.contains(postId)) return;

    _alreadyMarked.add(postId);

    final ref = FirebaseFirestore.instance
        .collection("canales")
        .doc(widget.tipsterId)
        .collection("posts")
        .doc(postId);

    try {
      await ref.set({
        "viewedBy": FieldValue.arrayUnion([uid]),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint("❌ Error al actualizar views en Firestore: $e");
    }
  }

  Future<void> _followChannel(List seguidores, bool isFollowing) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final ref =
        FirebaseFirestore.instance.collection("canales").doc(widget.tipsterId);

    try {
      if (!isFollowing) {
        if (!seguidores.contains(uid)) {
          await ref.update({
            "seguidores": FieldValue.arrayUnion([uid]),
            "numero_seguidores": FieldValue.increment(1),
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Ahora sigues este canal 🎉"),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      } else {
        if (seguidores.contains(uid)) {
          await ref.update({
            "seguidores": FieldValue.arrayRemove([uid]),
            "numero_seguidores": FieldValue.increment(-1),
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Has dejado de seguir este canal ❌"),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _statusLabel(String status) {
    Color bg;
    String text;
    if (status == 'won') {
      bg = Colors.green;
      text = "GANADA ✅";
    } else if (status == 'lost') {
      bg = Colors.red;
      text = "PERDIDA ❌";
    } else {
      bg = Colors.orange;
      text = "EN JUEGO 🟡";
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }

  Widget _apuestaResueltaCard(Map<String, dynamic> data) {
    final resolucion = (data['resolucion'] ?? 0).toDouble();
    final fecha = (data['fecha'] as Timestamp?)?.toDate();
    final esPositiva = resolucion > 0;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border:
            Border.all(color: esPositiva ? Colors.green : Colors.red, width: 2),
        borderRadius: BorderRadius.circular(10),
        color: Colors.grey[900],
      ),
      child: Row(
        children: [
          Icon(
            esPositiva ? Icons.trending_up : Icons.trending_down,
            color: esPositiva ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "${esPositiva ? '+' : '-'}${resolucion.abs().toStringAsFixed(2)} Unidades",
              style: TextStyle(
                color: esPositiva ? Colors.green : Colors.red,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (fecha != null)
            Text(
              _formatDate(fecha),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('canales')
              .doc(widget.tipsterId)
              .snapshots(),
          builder: (ctx, snap) {
            if (!snap.hasData) return const Text("Cargando...");
            final data = snap.data!.data() as Map<String, dynamic>? ?? {};
            final nombre = data['nombre_canal'] ?? "Canal del Tipster";
            return Text(nombre);
          },
        ),
      ),
      body: Column(
        children: [
          // 🔹 Info canal
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance
                .collection('canales')
                .doc(widget.tipsterId)
                .snapshots(),
            builder: (ctx, snap) {
              if (!snap.hasData) return const SizedBox();
              final canal = snap.data!.data() as Map<String, dynamic>? ?? {};
              final seguidores = (canal['seguidores'] ?? []) as List;
              final isFollowing = seguidores.contains(uid);
              final numeroSeguidores = canal['numero_seguidores'] ?? 0;

              final descripcion =
                  canal['descripcion_canal'] ?? canal['descripcion'] ?? "";
              final foto = canal['foto'] ?? canal['foto_canal'] ?? "";

              return InkWell(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TipsterChannelInfo(
                        nombre: canal['nombre_canal'] ?? "Canal",
                        descripcion: descripcion,
                        foto: foto,
                        tipsterId: widget.tipsterId,
                        canalId: snap.data!.id,
                      ),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.grey[900],
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundImage:
                            foto.isNotEmpty ? NetworkImage(foto) : null,
                        child: foto.isEmpty
                            ? const Icon(Icons.person,
                                size: 32, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              canal['nombre_canal'] ?? "Canal",
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              "$numeroSeguidores seguidores",
                              style: const TextStyle(color: Colors.white70),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              descripcion,
                              style: const TextStyle(color: Colors.white54),
                            ),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              isFollowing ? Colors.redAccent : Colors.green,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () =>
                            _followChannel(seguidores, isFollowing),
                        child: Text(
                          isFollowing ? "Dejar de seguir" : "Seguir",
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const Divider(height: 0),

          // 🔹 Posts + apuestas
          Expanded(
            child: ListView(
              controller: _scrollController,
              children: [
                // Posts
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection("canales")
                      .doc(widget.tipsterId)
                      .collection("posts")
                      .orderBy("postedAt", descending: false)
                      .snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) {
                      return const Center(
                          child: Text("Este tipster aún no tiene publicaciones"));
                    }

                    String? lastDate;
                    return Column(
                      children: docs.map((doc) {
                        final p = doc.data()! as Map<String, dynamic>;
                        final ts = (p['postedAt'] as Timestamp?)?.toDate();
                        final fecha = ts != null ? _formatDate(ts) : '';
                        final thisDateKey =
                            ts != null ? "${ts.year}-${ts.month}-${ts.day}" : '';

                        List<Widget> children = [];

                        if (thisDateKey != lastDate && ts != null) {
                          final now = DateTime.now();
                          final isToday = ts.year == now.year &&
                              ts.month == now.month &&
                              ts.day == now.day;

                          children.add(
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[300],
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    isToday
                                        ? "Hoy"
                                        : DateFormat.yMMMd().format(ts),
                                    style: const TextStyle(
                                        fontSize: 12, color: Colors.black87),
                                  ),
                                ),
                              ),
                            ),
                          );
                          lastDate = thisDateKey;
                        }

                        final viewedBy = (p['viewedBy'] ?? []) as List;
                        _markAsViewed(doc.id, viewedBy);
                        final shownViews = viewedBy.length;

                        if (p['type'] == 'texto') {
                          children.add(
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.symmetric(
                                    vertical: 4, horizontal: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.green[200],
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p['content'] ?? '',
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 14,
                                      ),
                                    ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        if (fecha.isNotEmpty)
                                          Text(
                                            fecha,
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.black54),
                                          ),
                                        Row(
                                          children: [
                                            const Icon(Icons.remove_red_eye,
                                                size: 14, color: Colors.black54),
                                            const SizedBox(width: 4),
                                            Text(
                                              "$shownViews",
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.black54),
                                            ),
                                          ],
                                        )
                                      ],
                                    )
                                  ],
                                ),
                              ),
                            ),
                          );
                        } else if (p['type'] == 'pronostico') {
                          final status = p['status'] ?? 'open';

                          children.add(
                            Card(
                              color: Colors.grey[850],
                              margin: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 8),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    _statusLabel(status),
                                    const SizedBox(height: 8),
                                    Text(
                                      p['evento'] ?? '',
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      "Selección: ${p['seleccion']}",
                                      style: const TextStyle(
                                          color: Colors.white70),
                                    ),
                                    Text(
                                      "Cuota: ${p['cuota']} | Stake: ${p['stake']}",
                                      style: const TextStyle(
                                          color: Colors.white70),
                                    ),
                                    if (p['imageUrl'] != null &&
                                        (p['imageUrl'] as String).isNotEmpty)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 8),
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Image.network(
                                            p['imageUrl'],
                                            height: 150,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                      ),
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        if (fecha.isNotEmpty)
                                          Text(
                                            fecha,
                                            style: const TextStyle(
                                                fontSize: 10,
                                                color: Colors.white54),
                                          ),
                                        Row(
                                          children: [
                                            const Icon(Icons.remove_red_eye,
                                                size: 14,
                                                color: Colors.white54),
                                            const SizedBox(width: 4),
                                            Text(
                                              "$shownViews",
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.white54),
                                            ),
                                          ],
                                        )
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: children,
                        );
                      }).toList(),
                    );
                  },
                ),

                // Apuestas resueltas
                StreamBuilder<QuerySnapshot>(
                  stream: FirebaseFirestore.instance
                      .collection("apuesta_resuelta")
                      .where("uid", isEqualTo: widget.tipsterId)
                      .snapshots(),
                  builder: (context, snap) {
                    if (!snap.hasData) return const SizedBox();
                    final docs = snap.data!.docs;
                    if (docs.isEmpty) return const SizedBox();
                    return Column(
                      children: docs.map((d) {
                        final data = d.data()! as Map<String, dynamic>;
                        return _apuestaResueltaCard(data);
                      }).toList(),
                    );
                  },
                ),

                const SizedBox(height: 60), // 👈 margen final
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('canales')
            .doc(widget.tipsterId)
            .snapshots(),
        builder: (ctx, snap) {
          if (!snap.hasData) return const SizedBox.shrink();

          final canal = snap.data!.data() as Map<String, dynamic>? ?? {};
          final seguidores = (canal['seguidores'] ?? []) as List;
          final isFollowing = seguidores.contains(uid);

          if (isFollowing) return const SizedBox.shrink();

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  backgroundColor: Colors.green,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => _followChannel(seguidores, isFollowing),
                child: const Text(
                  "Seguir",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
