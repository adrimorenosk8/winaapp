import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:rxdart/rxdart.dart';

import 'tipster_channel_info.dart';

class TipsterChannelPage extends StatefulWidget {
  final String tipsterId;
  const TipsterChannelPage({super.key, required this.tipsterId});

  @override
  State<TipsterChannelPage> createState() => _TipsterChannelPageState();
}

class _TipsterChannelPageState extends State<TipsterChannelPage> {
  final Set<String> _alreadyMarked = {};
  final ScrollController _scrollController = ScrollController();
  bool _didInitialScroll = false;

  // ---------- Helpers ----------
  double _toDouble(dynamic v) {
    try {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0.0;
    } catch (_) {}
    return 0.0;
  }

  String _toSafeString(dynamic v) {
    if (v == null) return "";
    try {
      return v.toString().replaceAll(RegExp(r'[<>]'), "").trim();
    } catch (_) {
      return "";
    }
  }

  List _toSafeList(dynamic v) => (v is List) ? v : const [];

  void _scrollToBottom({bool force = false}) {
    if (!_scrollController.hasClients) return;
    Future.delayed(const Duration(milliseconds: 120), () {
      if (!_scrollController.hasClients) return;
      final max = _scrollController.position.maxScrollExtent;
      final cur = _scrollController.offset;
      if (force) {
        _scrollController.jumpTo(max);
      } else if (max - cur < 300) {
        _scrollController.animateTo(
          max + 60,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
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

  /// ✅ sumar 1 vista: añade TU uid a `viewers` 1 sola vez (cumple reglas: sólo cambia 'viewers')
  Future<void> _markAsViewedOnce({
    required String ownerUid,
    required String postId,
    required List viewers,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return;
    if (postId.isEmpty) return;

    if (_alreadyMarked.contains(postId)) return;
    if (viewers.contains(uid)) return;

    _alreadyMarked.add(postId);

    final ref = FirebaseFirestore.instance
        .collection("canales")
        .doc(ownerUid)
        .collection("posts")
        .doc(postId);

    try {
      await ref.update({
        "viewers": FieldValue.arrayUnion([uid]),
      });
    } catch (e) {
      debugPrint("⚠️ markAsViewed error: $e");
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
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  Widget _apuestaResueltaCard(Map<String, dynamic> data) {
    final resolucion = _toDouble(data['resolucion']);
    final fecha = (data['fecha'] is Timestamp) ? (data['fecha'] as Timestamp).toDate() : null;
    final pos = resolucion >= 0;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: pos ? Colors.green : Colors.red, width: 2),
        borderRadius: BorderRadius.circular(10),
        color: Colors.grey[900],
      ),
      child: Row(
        children: [
          Icon(pos ? Icons.trending_up : Icons.trending_down, color: pos ? Colors.green : Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "${pos ? '+' : '-'}${resolucion.abs().toStringAsFixed(2)} Unidades",
              style: TextStyle(
                color: pos ? Colors.green : Colors.red,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          if (fecha != null)
            Text(_formatDate(fecha), style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  /// Stream combinado (ordenamos en memoria):
  /// - Canal público o seguidor/owner: ver TODO.
  /// - apuesta_resuelta: query sin orderBy (evita índice) y se ordena abajo.
  Stream<List<Map<String, dynamic>>> _combinedStream() {
    final db = FirebaseFirestore.instance;
    final canalRef = db.collection("canales").doc(widget.tipsterId);
    final postsCol = canalRef.collection("posts");
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    return canalRef.snapshots().switchMap((canalDoc) {
      final data = (canalDoc.data() as Map<String, dynamic>?) ?? {};
      final seguidores = (data['seguidores'] is List) ? List<String>.from(data['seguidores']) : <String>[];
      final isOwner = currentUid == widget.tipsterId;
      final isFollower = currentUid != null && seguidores.contains(currentUid);

      // Posts: pedimos todos; reglas decidirán qué se puede leer
      final Stream<QuerySnapshot<Map<String, dynamic>>> postsSnapStream =
          postsCol.orderBy('postedAt').snapshots();

      // Resultados del tipster
      final Stream<QuerySnapshot<Map<String, dynamic>>> apuestasSnapStream = db
          .collection("apuesta_resuelta")
          .where("uid", isEqualTo: widget.tipsterId)
          .snapshots();

      final postsListStream = postsSnapStream
          .map((snap) => snap.docs.map((d) {
                final m = d.data();
                m['__type'] = 'post';
                m['__id'] = d.id;
                return m;
              }).toList())
          .onErrorReturnWith((_, __) => <Map<String, dynamic>>[]);

      final apuestasListStream = apuestasSnapStream
          .map((snap) => snap.docs.map((d) {
                final m = d.data();
                m['__type'] = 'apuesta';
                m['__id'] = d.id;
                return m;
              }).toList())
          .onErrorReturnWith((_, __) => <Map<String, dynamic>>[])
          .startWith(const <Map<String, dynamic>>[]);

      return Rx.combineLatest2<List<Map<String, dynamic>>, List<Map<String, dynamic>>, List<Map<String, dynamic>>>(
        postsListStream,
        apuestasListStream,
        (posts, apuestas) {
          final items = <Map<String, dynamic>>[];
          items.addAll(posts);
          items.addAll(apuestas);

          // ordenamos en memoria por postedAt/fecha (ASC)
          items.sort((a, b) {
            DateTime da = DateTime.fromMillisecondsSinceEpoch(0);
            DateTime dbb = DateTime.fromMillisecondsSinceEpoch(0);
            if (a['postedAt'] is Timestamp) da = (a['postedAt'] as Timestamp).toDate();
            if (a['fecha'] is Timestamp) da = (a['fecha'] as Timestamp).toDate();
            if (b['postedAt'] is Timestamp) dbb = (b['postedAt'] as Timestamp).toDate();
            if (b['fecha'] is Timestamp) dbb = (b['fecha'] as Timestamp).toDate();
            return da.compareTo(dbb);
          });

          return items;
        },
      );
    });
  }

  // ---------- Imagen sin recortes (contain) + visor full screen ----------
  Widget _fullWidthContainImage(String url) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          width: constraints.maxWidth,
          constraints: const BoxConstraints(maxHeight: 420), // tope para que no se coma toda la pantalla
          color: Colors.black, // fondo negro para “letterboxing”
          child: GestureDetector(
            onTap: () => _showImageViewer(url),
            child: Image.network(
              url,
              fit: BoxFit.contain,
              alignment: Alignment.center,
              errorBuilder: (ctx, err, st) => const SizedBox(
                height: 140,
                child: Center(
                  child: Text('⚠️ Imagen no disponible', style: TextStyle(color: Colors.white70)),
                ),
              ),
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return SizedBox(
                  height: 180,
                  child: Center(
                    child: CircularProgressIndicator(
                      value: progress.expectedTotalBytes != null
                          ? progress.cumulativeBytesLoaded / (progress.expectedTotalBytes ?? 1)
                          : null,
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  void _showImageViewer(String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.9),
      builder: (_) {
        return GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4,
              child: Image.network(url, fit: BoxFit.contain),
            ),
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom(force: true));
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
    final isOwnerView = uid == widget.tipsterId;

    final Stream<DocumentSnapshot<Map<String, dynamic>>> userRoleStream =
        (uid.isNotEmpty)
            ? FirebaseFirestore.instance.collection('users').doc(uid).snapshots()
            : Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();

    return Scaffold(
      appBar: AppBar(
        title: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('canales').doc(widget.tipsterId).snapshots(),
          builder: (ctx, snap) {
            if (snap.hasError) return const Text("Canal");
            if (!snap.hasData) return const Text("Cargando...");
            final data = snap.data!.data() as Map<String, dynamic>? ?? {};
            final nombre = _toSafeString(data['nombre_canal']);
            return Text(nombre.isEmpty ? "Canal del Tipster" : nombre);
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () async {
              final doc = await FirebaseFirestore.instance.collection('canales').doc(widget.tipsterId).get();
              final data = doc.data() ?? {};
              if (!context.mounted) return;
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => TipsterChannelInfo(
                    nombre: _toSafeString(data['nombre_canal']),
                    descripcion: _toSafeString(
                      (data['descripcion_canal']?.toString().isNotEmpty == true)
                          ? data['descripcion_canal']
                          : data['descripcion'],
                    ),
                    foto: _toSafeString((data['foto_canal'] ?? data['foto'])),
                    tipsterId: widget.tipsterId,
                    canalId: doc.id,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ---- Cabecera canal + botón seguir ----
          StreamBuilder<DocumentSnapshot>(
            stream: FirebaseFirestore.instance.collection('canales').doc(widget.tipsterId).snapshots(),
            builder: (ctx, snap) {
              if (snap.hasError) {
                return Container(
                  padding: const EdgeInsets.all(12),
                  color: Colors.red.withOpacity(0.1),
                  child: const Text("Error cargando canal", style: TextStyle(color: Colors.redAccent)),
                );
              }
              if (!snap.hasData) {
                return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
              }

              final canal = snap.data!.data() as Map<String, dynamic>? ?? {};
              final seguidores = _toSafeList(canal['seguidores']);
              final isFollowing = seguidores.contains(uid);
              final numeroSeguidores =
                  (canal['numero_seguidores'] is num) ? canal['numero_seguidores'] : seguidores.length;
              final descripcion = _toSafeString(
                (canal['descripcion_canal']?.toString().isNotEmpty == true) ? canal['descripcion_canal'] : canal['descripcion'],
              );
              final foto = _toSafeString((canal['foto_canal'] ?? canal['foto']));

              return Container(
                padding: const EdgeInsets.all(16),
                color: Colors.grey[900],
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 32,
                      backgroundImage: foto.isNotEmpty ? NetworkImage(foto) : null,
                      child: foto.isEmpty ? const Icon(Icons.person, size: 32, color: Colors.white) : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_toSafeString(canal['nombre_canal']),
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                          const SizedBox(height: 4),
                          Text("$numeroSeguidores seguidores", style: const TextStyle(color: Colors.white70)),
                          const SizedBox(height: 4),
                          Text(descripcion, style: const TextStyle(color: Colors.white54)),
                        ],
                      ),
                    ),
                    if (!isOwnerView)
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: userRoleStream,
                        builder: (context, roleSnap) {
                          final role = (roleSnap.data?.data() ?? const {})['role']?.toString() ?? '';
                          // 👇 tipster también puede seguir
                          final canFollow = role == 'user' || role == 'tipster' || role == 'admin';
                          return ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isFollowing ? Colors.redAccent : (canFollow ? Colors.green : Colors.grey),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: (!canFollow)
                                ? null
                                : () async {
                                    try {
                                      final ref = FirebaseFirestore.instance.collection("canales").doc(widget.tipsterId);
                                      if (!isFollowing) {
                                        await ref.update({
                                          "seguidores": FieldValue.arrayUnion([uid]),
                                          "numero_seguidores": FieldValue.increment(1),
                                        });
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Ahora sigues este canal 🎉"), backgroundColor: Colors.green),
                                        );
                                      } else {
                                        await ref.update({
                                          "seguidores": FieldValue.arrayRemove([uid]),
                                          "numero_seguidores": FieldValue.increment(-1),
                                        });
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          const SnackBar(content: Text("Has dejado de seguir este canal ❌"), backgroundColor: Colors.red),
                                        );
                                      }
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                                      );
                                    }
                                  },
                            child: Text(
                              isFollowing ? "Dejar de seguir" : (canFollow ? "Seguir" : "No disponible"),
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              );
            },
          ),

          const Divider(height: 0),

          // ---- Feed combinado (orden ASC + autoscroll al fondo) ----
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _combinedStream(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        "No tienes permisos para ver parte del contenido.",
                        style: const TextStyle(color: Colors.white70),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final items = snapshot.data!;
                if (items.isEmpty) {
                  return const Center(
                    child: Text("Este tipster aún no tiene publicaciones visibles",
                        style: TextStyle(color: Colors.white70)),
                  );
                }

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!_didInitialScroll) {
                    _scrollToBottom(force: true);
                    _didInitialScroll = true;
                  } else {
                    _scrollToBottom();
                  }
                });

                String? lastDate;
                return ListView.builder(
                  controller: _scrollController,
                  itemCount: items.length + 1,
                  itemBuilder: (ctx, i) {
                    if (i == items.length) return const SizedBox(height: 80);

                    final p = items[i];
                    DateTime? ts;
                    if (p['postedAt'] is Timestamp) ts = (p['postedAt'] as Timestamp).toDate();
                    if (p['fecha'] is Timestamp) ts = (p['fecha'] as Timestamp).toDate();
                    final fecha = ts != null ? _formatDate(ts) : '';
                    final dateKey = ts != null ? "${ts.year}-${ts.month}-${ts.day}" : '';

                    final List<Widget> children = [];

                    // Header de fecha
                    if (ts != null && dateKey != lastDate) {
                      final now = DateTime.now();
                      final isToday = ts.year == now.year && ts.month == now.month && ts.day == now.day;
                      children.add(
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(20)),
                              child: Text(isToday ? "Hoy" : DateFormat.yMMMd().format(ts),
                                  style: const TextStyle(fontSize: 12, color: Colors.black87)),
                            ),
                          ),
                        ),
                      );
                      lastDate = dateKey;
                    }

                    if (p['__type'] == 'apuesta') {
                      children.add(_apuestaResueltaCard(p));
                    } else if (p['__type'] == 'post') {
                      final viewers = _toSafeList(p['viewers']);
                      final postId = _toSafeString(p['__id']);

                      // +1 vista (solo viewers, cumple reglas)
                      _markAsViewedOnce(
                        ownerUid: widget.tipsterId,
                        postId: postId,
                        viewers: viewers,
                      );

                      final shownViews = viewers.length;

                      if (p['type'] == 'texto') {
                        children.add(
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.green[200], borderRadius: BorderRadius.circular(12)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_toSafeString(p['content']),
                                      style: const TextStyle(color: Colors.black, fontSize: 14)),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      if (fecha.isNotEmpty)
                                        Text(fecha, style: const TextStyle(fontSize: 10, color: Colors.black54)),
                                      Row(
                                        children: [
                                          const Icon(Icons.remove_red_eye, size: 14, color: Colors.black54),
                                          const SizedBox(width: 4),
                                          Text("$shownViews",
                                              style: const TextStyle(fontSize: 10, color: Colors.black54)),
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
                        final status = _toSafeString(p['status']).isEmpty ? 'open' : _toSafeString(p['status']);
                        final cuota = _toDouble(p['cuota']);
                        final stake = _toDouble(p['stake']);
                        final imageUrl = _toSafeString(p['imageUrl']);

                        children.add(
                          Card(
                            color: Colors.grey[850],
                            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _statusLabel(status),
                                  const SizedBox(height: 8),
                                  Text(_toSafeString(p['evento']),
                                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                                  const SizedBox(height: 4),
                                  Text("Selección: ${_toSafeString(p['seleccion'])}",
                                      style: const TextStyle(color: Colors.white70)),
                                  Text(
                                    "Cuota: ${cuota.toStringAsFixed(2)} | Stake: ${stake.toStringAsFixed(2)}",
                                    style: const TextStyle(color: Colors.white70),
                                  ),
                                  if (imageUrl.isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    _fullWidthContainImage(imageUrl), // 👈 sin recortes + tap para zoom
                                  ],
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      if (fecha.isNotEmpty)
                                        Text(fecha, style: const TextStyle(fontSize: 10, color: Colors.white54)),
                                      Row(
                                        children: [
                                          const Icon(Icons.remove_red_eye, size: 14, color: Colors.white54),
                                          const SizedBox(width: 4),
                                          Text("$shownViews",
                                              style: const TextStyle(fontSize: 10, color: Colors.white54)),
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
                    }

                    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
                  },
                );
              },
            ),
          ),
        ],
      ),
      // botón "Seguir" inferior
      bottomNavigationBar: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('canales').doc(widget.tipsterId).snapshots(),
        builder: (ctx, snap) {
          final uid = FirebaseAuth.instance.currentUser?.uid ?? "";
          if (!snap.hasData || snap.hasError) return const SizedBox.shrink();
          final canal = snap.data!.data() as Map<String, dynamic>? ?? {};
          final seguidores = _toSafeList(canal['seguidores']);
          final isFollowing = seguidores.contains(uid);
          final isOwnerView = uid == widget.tipsterId;
          if (isFollowing || isOwnerView) return const SizedBox.shrink();

          final Stream<DocumentSnapshot<Map<String, dynamic>>> userRoleStream =
              (uid.isNotEmpty)
                  ? FirebaseFirestore.instance.collection('users').doc(uid).snapshots()
                  : Stream<DocumentSnapshot<Map<String, dynamic>>>.empty();

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                stream: userRoleStream,
                builder: (context, roleSnap) {
                  final role = (roleSnap.data?.data() ?? const {})['role']?.toString() ?? '';
                  // 👇 también permitir a tipster
                  final canFollow = role == 'user' || role == 'tipster' || role == 'admin';
                  return ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      backgroundColor: canFollow ? Colors.green : Colors.grey,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: canFollow
                        ? () async {
                            try {
                              final ref = FirebaseFirestore.instance.collection("canales").doc(widget.tipsterId);
                              await ref.update({
                                "seguidores": FieldValue.arrayUnion([uid]),
                                "numero_seguidores": FieldValue.increment(1),
                              });
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
                              );
                            }
                          }
                        : null,
                    child: const Text("Seguir",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  );
                },
              ),
            ),
          );
        },
      ),
      backgroundColor: Colors.black,
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
