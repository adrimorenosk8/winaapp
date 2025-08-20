import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:wina/tipster_channel_info.dart';
import 'package:wina/tipster_channel_page.dart';




class TipsterPage extends StatefulWidget {
  const TipsterPage({super.key});

  @override
  State<TipsterPage> createState() => _TipsterPageState();
}

class _TipsterPageState extends State<TipsterPage> {
  final _textoCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();


  // -------- SUBIR TEXTO --------
  Future<void> _enviarTexto() async {
    if (_textoCtrl.text.trim().isEmpty) return;
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final docId = FirebaseFirestore.instance
          .collection('canales')
          .doc(uid)
          .collection('posts')
          .doc()
          .id;

      final data = {
        'type': 'texto',
        'content': _textoCtrl.text.trim(),
        'postedAt': FieldValue.serverTimestamp(),
        'views': 0,
        'viewers': [],
      };

      await FirebaseFirestore.instance
          .collection('canales')
          .doc(uid)
          .collection('posts')
          .doc(docId)
          .set(data);

      _textoCtrl.clear();
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    }
  }

  // -------- FORMULARIO DE PRONOSTICO --------
  final _formKey = GlobalKey<FormState>();
  final _sport = TextEditingController();
  final _evento = TextEditingController();
  final _seleccion = TextEditingController();
  final _cuota = TextEditingController();
  final _stake = TextEditingController();
  XFile? _pickedImage;

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _pickedImage = picked);
    }
  }

  Future<String?> _uploadImage() async {
    if (_pickedImage == null) return null;

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final ref = FirebaseStorage.instance
          .ref()
          .child('posts')
          .child(uid)
          .child('${DateTime.now().millisecondsSinceEpoch}.jpg');

      // 👇 Siempre usamos bytes, evita fallos con Google Drive y otros
      final bytes = await _pickedImage!.readAsBytes();
      await ref.putData(bytes);

      return await ref.getDownloadURL();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text("❌ Error al subir imagen: $e")));
      }
      return null;
    }
  }

  Future<void> _crearPronostico() async {
    if (!_formKey.currentState!.validate()) return;
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final imageUrl = await _uploadImage();

      final docId = FirebaseFirestore.instance
          .collection('canales')
          .doc(uid)
          .collection('posts')
          .doc()
          .id;

      final postData = {
        'type': 'pronostico',
        'sport': _sport.text.trim(),
        'evento': _evento.text.trim(),
        'seleccion': _seleccion.text.trim(),
        'cuota': double.tryParse(_cuota.text.trim()) ?? 0.0,
        'stake': int.tryParse(_stake.text.trim()) ?? 1,
        'imageUrl': imageUrl,
        'postedAt': FieldValue.serverTimestamp(),
        'status': 'open',
        'tipsterId': uid,
        'views': 0,
        'viewers': [],
      };

      await FirebaseFirestore.instance
          .collection('canales')
          .doc(uid)
          .collection('posts')
          .doc(docId)
          .set(postData);

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('✅ Pronóstico creado')));

      _sport.clear();
      _evento.clear();
      _seleccion.clear();
      _cuota.clear();
      _stake.clear();
      setState(() => _pickedImage = null);
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
    }
  }

  void _abrirFormularioPronostico() {
    showModalBottomSheet(
      isScrollControlled: true,
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              children: [
                const Text(
                  "Nuevo Pronóstico",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                TextFormField(
                  controller: _sport,
                  decoration: const InputDecoration(labelText: "Deporte"),
                  validator: (v) => v!.isEmpty ? "Introduce un deporte" : null,
                ),
                TextFormField(
                  controller: _evento,
                  decoration: const InputDecoration(labelText: "Evento"),
                  validator: (v) => v!.isEmpty ? "Introduce un evento" : null,
                ),
                TextFormField(
                  controller: _seleccion,
                  decoration: const InputDecoration(labelText: "Selección"),
                  validator: (v) => v!.isEmpty ? "Introduce selección" : null,
                ),
                TextFormField(
                  controller: _cuota,
                  decoration: const InputDecoration(labelText: "Cuota"),
                  keyboardType: TextInputType.number,
                ),
                TextFormField(
                  controller: _stake,
                  decoration: const InputDecoration(labelText: "Stake"),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (_pickedImage == null)
                      const Text("Sin imagen")
                    else if (kIsWeb)
                      Expanded(
                        child: Image.network(
                          _pickedImage!.path,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      )
                    else
                      Expanded(
                        child: Image.file(
                          File(_pickedImage!.path),
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                    IconButton(
                      onPressed: _pickImage,
                      icon: const Icon(Icons.image),
                    ),
                  ],
                ),
                ElevatedButton(
                  onPressed: _crearPronostico,
                  child: const Text("Aceptar"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------- BORRAR / EDITAR --------
  Future<void> _borrarPost(String postId) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    try {
      final canalRef = FirebaseFirestore.instance
          .collection('canales')
          .doc(uid)
          .collection('posts');

      // 1️⃣ Obtener el documento a borrar para ver su tipo
      final snap = await canalRef.doc(postId).get();
      final data = snap.data();

      if (data == null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('⚠️ Post no encontrado')));
        return;
      }

      final tipo = data['type'];

      // 2️⃣ Borrar el post en la colección del canal
      await canalRef.doc(postId).delete();

      // =======================
      // CASO: RESULTADO
      // =======================
      if (tipo == 'resultado') {
        final originalPostId = data['postId'];

        final apuestaSnap = await FirebaseFirestore.instance
            .collection('apuesta_resuelta')
            .where('uid', isEqualTo: uid) // 👈 añadido
            .where('postId', isEqualTo: originalPostId)
            .get();

        for (var doc in apuestaSnap.docs) {
          final resolucion = (doc['resolucion'] as num?)?.toDouble() ?? 0.0;

          await doc.reference.delete();

          // 🔄 Revertir unidades
          final userRef = FirebaseFirestore.instance
              .collection('users')
              .doc(uid);
          await FirebaseFirestore.instance.runTransaction((tx) async {
            final uSnap = await tx.get(userRef);
            final current = (uSnap.data()?['unidades'] ?? 0).toDouble();

            tx.update(userRef, {"unidades": current - resolucion});
          });
        }
      }
      // =========================
      // CASO: PRONOSTICO
      // =========================
      else if (tipo == 'pronostico') {
        // Eliminar resultados vinculados en el canal
        final resultadoSnap = await canalRef
            .where('type', isEqualTo: 'resultado')
            .where('postId', isEqualTo: postId)
            .get();

        for (var doc in resultadoSnap.docs) {
          await doc.reference.delete();
        }

        // Eliminar apuesta_resuelta vinculada (global)
        final apuestaSnap = await FirebaseFirestore.instance
            .collection('apuesta_resuelta')
            .where('uid', isEqualTo: uid) // 👈 añadido
            .where('postId', isEqualTo: postId)
            .get();

        for (var doc in apuestaSnap.docs) {
          final resolucion = (doc['resolucion'] as num?)?.toDouble() ?? 0.0;

          await doc.reference.delete();

          // 🔄 Revertir unidades
          final userRef = FirebaseFirestore.instance
              .collection('users')
              .doc(uid);
          await FirebaseFirestore.instance.runTransaction((tx) async {
            final uSnap = await tx.get(userRef);
            final current = (uSnap.data()?['unidades'] ?? 0).toDouble();

            tx.update(userRef, {"unidades": current - resolucion});
          });
        }
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('🗑️ Post eliminado')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Error eliminando: $e')));
    }
  }

  Future<void> _editarPost(String postId, Map<String, dynamic> data) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    try {
      await FirebaseFirestore.instance
          .collection('canales')
          .doc(uid)
          .collection('posts')
          .doc(postId)
          .update(data);

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('✏️ Post actualizado')));
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('❌ Error editando: $e')));
    }
  }

  // -------- RESOLVER PRONOSTICO --------
  Future<void> _resolverPronostico(
    String postId,
    Map<String, dynamic> data,
    String status,
  ) async {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    final cuota = (data['cuota'] as num?)?.toDouble() ?? 0.0;
    final stake = (data['stake'] as num?)?.toInt() ?? 0;

    double resolucion = 0;
    if (status == 'won') {
      resolucion = (stake * cuota) - stake;
    } else if (status == 'lost') {
      resolucion = -stake.toDouble();
    }

    final apuestaRef = FirebaseFirestore.instance.collection(
      'apuesta_resuelta',
    );
    final existe = await apuestaRef
        .where('uid', isEqualTo: uid)
        .where('postId', isEqualTo: postId)
        .limit(1)
        .get();

    double? resolucionAnterior;

    if (existe.docs.isNotEmpty) {
      final doc = existe.docs.first;
      resolucionAnterior = (doc['resolucion'] as num?)?.toDouble() ?? 0.0;

      await doc.reference.update({
        'status': status,
        'resolucion': resolucion,
        'fecha': FieldValue.serverTimestamp(),
      });
    } else {
      await apuestaRef.add({
        'uid': uid,
        'postId': postId,
        'fecha': FieldValue.serverTimestamp(),
        'status': status,
        'resolucion': resolucion,
      });
    }

    final canalPosts = FirebaseFirestore.instance
        .collection('canales')
        .doc(uid)
        .collection('posts');

    final resultadoQuery = await canalPosts
        .where('type', isEqualTo: 'resultado')
        .where('postId', isEqualTo: postId)
        .limit(1)
        .get();

    if (resultadoQuery.docs.isNotEmpty) {
      await resultadoQuery.docs.first.reference.update({
        'status': status,
        'resolucion': resolucion,
        'postedAt': FieldValue.serverTimestamp(),
      });
    } else {
      await canalPosts.doc().set({
        'type': 'resultado',
        'postId': postId,
        'status': status,
        'resolucion': resolucion,
        'postedAt': FieldValue.serverTimestamp(),
      });
    }

    // 🔥 Actualizar unidades del usuario (restando anterior + sumando nuevo)
    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final current = (snap.data()?['unidades'] ?? 0).toDouble();

      final nuevoTotal = current - (resolucionAnterior ?? 0) + resolucion;
      tx.update(userRef, {"unidades": nuevoTotal});
    });

    // 🔥 Asegurarse de que también se actualiza el pronóstico original
    await _editarPost(postId, {"status": status});
  }

  // -------- VISITAS ÚNICAS --------
  Future<void> _registrarVisita(String ownerUid, String postId) async {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    final postRef = FirebaseFirestore.instance
        .collection('canales')
        .doc(ownerUid)
        .collection('posts')
        .doc(postId);

    try {
      await FirebaseFirestore.instance.runTransaction((tx) async {
        final snap = await tx.get(postRef);
        if (!snap.exists) return;

        final data = snap.data() as Map<String, dynamic>;
        final viewers = List<String>.from(data['viewers'] ?? []);

        if (!viewers.contains(currentUid)) {
          tx.update(postRef, {
            "views": FieldValue.increment(1),
            "viewers": FieldValue.arrayUnion([currentUid]),
          });
        }
      });
    } catch (e) {
      debugPrint("❌ Error registrando visita: $e");
    }
  }

  // -------- FORMATEAR FECHAS --------
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

  // -------- PERFIL CANAL --------

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.grey[900], // tono gris oscuro
        elevation: 2, // ligera sombra
        title: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('canales')
              .doc(user!.uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Text("Cargando...");
            }
            final data = snapshot.data!.data() as Map<String, dynamic>?;
            final nombre = data?['nombre_canal'] ?? "Mi canal";
            final foto = data?['foto_canal'];
            final desc = data?['descripcion'] ?? "";

            return InkWell(
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TipsterChannelInfo(
          nombre: data?['nombre_canal'] ?? "Sin nombre",
          descripcion: data?['descripcion'] ?? "",
          foto: data?['foto_canal'] ?? "",
          tipsterId: user.uid,
          canalId: snapshot.data!.id,
        ),
      ),
    );
  },
  child: Row(
    children: [
      if (foto != null && foto.isNotEmpty)
        CircleAvatar(backgroundImage: NetworkImage(foto))
      else
        const CircleAvatar(child: Icon(Icons.person)),
      const SizedBox(width: 8),
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nombre,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          Text(
            "${(data?['seguidores'] as List?)?.length ?? 0} seguidores"
, // 👈 aquí se muestra el contador
            style: const TextStyle(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    ],
  ),
);


          },
        ),
      ),

      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('canales')
                  .doc(user.uid)
                  .collection('posts')
                  .orderBy('postedAt', descending: false)
                  .snapshots(),
              builder: (ctx, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(child: Text("❌ Error: ${snapshot.error}"));
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(
                    child: Text("Todavía no has publicado nada."),
                  );
                }

                final posts = snapshot.data!.docs;

                String? lastDate;
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (_scrollController.hasClients) {
                    _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
                  }
                });

                return ListView.builder(
                  controller: _scrollController, // 👈 añadido aquí
                  padding: const EdgeInsets.all(10),
                  itemCount: posts.length,
                  itemBuilder: (ctx, i) {

                    final data = posts[i].data() as Map<String, dynamic>;
                    final postId = posts[i].id;

                    final ts = (data['postedAt'] as Timestamp?)?.toDate();
                    final fecha = ts != null ? _formatDate(ts) : '';

                    final thisDateKey = ts != null
                        ? "${ts.year}-${ts.month}-${ts.day}"
                        : '';

                    List<Widget> children = [];

                    if (thisDateKey != lastDate && ts != null) {
                      children.add(
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.grey[800],
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                DateFormat.yMMMd().format(ts),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                      lastDate = thisDateKey;
                    }

                    _registrarVisita(user.uid, postId);

                    // ========= TIPO TEXTO =========
                    if (data['type'] == 'texto') {
                      children.add(
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2C2C2C),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        data['content'] ?? '',
                                        style: const TextStyle(
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      onSelected: (value) {
                                        if (value == 'delete') {
                                          _borrarPost(postId);
                                        } else if (value == 'edit') {
                                          final ctrl = TextEditingController(
                                            text: data['content'],
                                          );
                                          showDialog(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              backgroundColor: const Color(
                                                0xFF1E1E1E,
                                              ),
                                              title: const Text(
                                                "Editar mensaje",
                                                style: TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              content: TextField(
                                                controller: ctrl,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx),
                                                  child: const Text("Cancelar"),
                                                ),
                                                ElevatedButton(
                                                  onPressed: () {
                                                    _editarPost(postId, {
                                                      "content": ctrl.text,
                                                    });
                                                    Navigator.pop(ctx);
                                                  },
                                                  child: const Text("Guardar"),
                                                ),
                                              ],
                                            ),
                                          );
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Text("✏️ Editar"),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text("🗑️ Eliminar"),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (fecha.isNotEmpty)
                                      Text(
                                        "🗓️ $fecha",
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    Text(
                                      "👀 ${data['views'] ?? 0}",
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.white54,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    // ========= TIPO PRONOSTICO =========
                    else if (data['type'] == 'pronostico') {
                      children.add(
                        Card(
                          color: const Color(0xFF1E1E1E),
                          margin: const EdgeInsets.symmetric(
                            vertical: 8,
                            horizontal: 8,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "Selección: ${data['seleccion'] ?? ''}",
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                    PopupMenuButton<String>(
                                      onSelected: (value) async {
                                        if (value == 'delete') {
                                          _borrarPost(postId);
                                        } else if (value == 'edit') {
                                          _sport.text = data['sport'] ?? '';
                                          _evento.text = data['evento'] ?? '';
                                          _seleccion.text =
                                              data['seleccion'] ?? '';
                                          _cuota.text = data['cuota']
                                              .toString();
                                          _stake.text = data['stake']
                                              .toString();

                                          showModalBottomSheet(
                                            isScrollControlled: true,
                                            context: context,
                                            builder: (ctx) => Padding(
                                              padding: EdgeInsets.only(
                                                left: 16,
                                                right: 16,
                                                top: 20,
                                                bottom:
                                                    MediaQuery.of(
                                                      context,
                                                    ).viewInsets.bottom +
                                                    20,
                                              ),
                                              child: Form(
                                                key: _formKey,
                                                child: SingleChildScrollView(
                                                  child: Column(
                                                    children: [
                                                      const Text(
                                                        "Editar Pronóstico",
                                                        style: TextStyle(
                                                          fontSize: 18,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                        ),
                                                      ),
                                                      TextFormField(
                                                        controller: _sport,
                                                        decoration:
                                                            const InputDecoration(
                                                              labelText:
                                                                  "Deporte",
                                                            ),
                                                      ),
                                                      TextFormField(
                                                        controller: _evento,
                                                        decoration:
                                                            const InputDecoration(
                                                              labelText:
                                                                  "Evento",
                                                            ),
                                                      ),
                                                      TextFormField(
                                                        controller: _seleccion,
                                                        decoration:
                                                            const InputDecoration(
                                                              labelText:
                                                                  "Selección",
                                                            ),
                                                      ),
                                                      TextFormField(
                                                        controller: _cuota,
                                                        decoration:
                                                            const InputDecoration(
                                                              labelText:
                                                                  "Cuota",
                                                            ),
                                                        keyboardType:
                                                            TextInputType
                                                                .number,
                                                      ),
                                                      TextFormField(
                                                        controller: _stake,
                                                        decoration:
                                                            const InputDecoration(
                                                              labelText:
                                                                  "Stake",
                                                            ),
                                                        keyboardType:
                                                            TextInputType
                                                                .number,
                                                      ),
                                                      ElevatedButton(
                                                        onPressed: () {
                                                          _editarPost(postId, {
                                                            'sport': _sport.text
                                                                .trim(),
                                                            'evento': _evento
                                                                .text
                                                                .trim(),
                                                            'seleccion':
                                                                _seleccion.text
                                                                    .trim(),
                                                            'cuota':
                                                                double.tryParse(
                                                                  _cuota.text
                                                                      .trim(),
                                                                ) ??
                                                                0.0,
                                                            'stake':
                                                                int.tryParse(
                                                                  _stake.text
                                                                      .trim(),
                                                                ) ??
                                                                1,
                                                          });
                                                          Navigator.pop(ctx);
                                                        },
                                                        child: const Text(
                                                          "Guardar",
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          );
                                        } else if (value == 'won' ||
                                            value == 'lost') {
                                          await _resolverPronostico(
                                            postId,
                                            data,
                                            value,
                                          );
                                        }
                                      },
                                      itemBuilder: (context) => [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Text("✏️ Editar"),
                                        ),
                                        const PopupMenuItem(
                                          value: 'delete',
                                          child: Text("🗑️ Eliminar"),
                                        ),
                                        const PopupMenuItem(
                                          value: 'won',
                                          child: Text("✅ Acertada"),
                                        ),
                                        const PopupMenuItem(
                                          value: 'lost',
                                          child: Text("❌ Fallada"),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.sports,
                                      color: Colors.white70,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "${data['sport'] ?? ''}",
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.flag,
                                      color: Colors.white70,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "${data['evento'] ?? ''}",
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  children: [
                                    const Icon(
                                      Icons.monetization_on,
                                      color: Colors.greenAccent,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "Cuota: ${data['cuota']}  ",
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                    const Icon(
                                      Icons.casino,
                                      color: Colors.orangeAccent,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      "Stake: ${data['stake']}",
                                      style: const TextStyle(
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                                if (data['imageUrl'] != null &&
                                    (data['imageUrl'] as String).isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        data['imageUrl'],
                                        height: 140,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (fecha.isNotEmpty)
                                      Text(
                                        "🗓️ $fecha",
                                        style: const TextStyle(
                                          fontSize: 10,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    Row(
                                      children: [
                                        if (data['status'] == 'won')
                                          const Text(
                                            "✅ Acertada",
                                            style: TextStyle(
                                              color: Colors.greenAccent,
                                            ),
                                          ),
                                        if (data['status'] == 'lost')
                                          const Text(
                                            "❌ Fallada",
                                            style: TextStyle(
                                              color: Colors.redAccent,
                                            ),
                                          ),
                                        if (data['status'] == 'open')
                                          const Text(
                                            "🟡 Abierta",
                                            style: TextStyle(
                                              color: Colors.amber,
                                            ),
                                          ),
                                        Text(
                                          "  👀 ${data['views'] ?? 0}",
                                          style: const TextStyle(
                                            fontSize: 10,
                                            color: Colors.white54,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    // ========= TIPO RESULTADO =========
                    else if (data['type'] == 'resultado') {
                      final resolucion =
                          (data['resolucion'] as num?)?.toDouble() ?? 0.0;
                      final positivo = resolucion >= 0;
                      final texto = positivo
                          ? "+ ${resolucion.toStringAsFixed(2)} UNIDADES"
                          : "- ${resolucion.abs().toStringAsFixed(2)} UNIDADES";

                      children.add(
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            margin: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 16,
                            ),
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 20,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: positivo
                                    ? const Color(0xFF00C853).withOpacity(0.7)
                                    : Colors.redAccent.withOpacity(0.7),
                                width: 1.3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.07),
                                  blurRadius: 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  positivo
                                      ? Icons.trending_up
                                      : Icons.trending_down,
                                  color: positivo
                                      ? const Color(0xFF00C853)
                                      : Colors.redAccent,
                                  size: 22,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  texto,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1,
                                    color: positivo
                                        ? const Color(0xFF00C853)
                                        : Colors.redAccent,
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  onSelected: (value) async {
                                    if (value == 'delete') {
                                      await _borrarPost(postId);
                                    } else if (value == 'won' ||
                                        value == 'lost') {
                                      final snap = await FirebaseFirestore
                                          .instance
                                          .collection('canales')
                                          .doc(user.uid)
                                          .collection('posts')
                                          .doc(data['postId'])
                                          .get();

                                      if (snap.exists) {
                                        final p =
                                            snap.data() as Map<String, dynamic>;
                                        await _resolverPronostico(
                                          data['postId'],
                                          p,
                                          value,
                                        );
                                      }
                                    }
                                  },
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'won',
                                      child: Text("✅ Marcar como Acertada"),
                                    ),
                                    const PopupMenuItem(
                                      value: 'lost',
                                      child: Text("❌ Marcar como Fallada"),
                                    ),
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text("🗑️ Eliminar"),
                                    ),
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
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                8,
                8,
                8,
                12,
              ), // margen lateral y abajo
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textoCtrl,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: "Escribe algo...",
                        hintStyle: const TextStyle(color: Colors.white54),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        filled: true,
                        fillColor: Colors.grey[850], // fondo gris oscuro
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _enviarTexto,
                    icon: const Icon(Icons.send, color: Colors.white),
                  ),
                  IconButton(
                    onPressed: _abrirFormularioPronostico,
                    icon: const Icon(Icons.add_chart, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
