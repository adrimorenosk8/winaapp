import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:wina/tipster_channel_info.dart';

/// ======= Colores de la app =======
const Color kPrimaryGreen = Color(0xFF2ECC71);
const Color kDarkBg = Colors.black;
const Color kFieldBg = Color(0xFF1E1E1E);
const BorderRadius kRadius = BorderRadius.all(Radius.circular(12));

/// ======= Seguridad imágenes (top-level) =======
enum _ImageType { jpeg, png, gif, webp, unknown }

_ImageType _detectImageType(Uint8List bytes) {
  if (bytes.length < 12) return _ImageType.unknown;
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return _ImageType.jpeg; // JPEG
  if (bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E && bytes[3] == 0x47) return _ImageType.png; // PNG
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return _ImageType.gif; // GIF
  if (bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
      bytes[8] == 0x57 && bytes[9] == 0x45 && bytes[10] == 0x42 && bytes[11] == 0x50) {
    return _ImageType.webp; // WEBP
  }
  return _ImageType.unknown;
}

bool _isValidHttpUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final u = Uri.tryParse(url);
  return u != null && (u.scheme == 'http' || u.scheme == 'https');
}

class TipsterPage extends StatefulWidget {
  const TipsterPage({super.key});

  @override
  State<TipsterPage> createState() => _TipsterPageState();
}

class _TipsterPageState extends State<TipsterPage> {
  final _textoCtrl = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  // anti-spam
  bool _sendingText = false;
  bool _creatingTip = false;

  // ======= Sanitización / validaciones =======
  String _sanitizeText(String input, {int maxLen = 500}) {
    final withoutControls = input.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '');
    final noRLO = withoutControls.replaceAll('\u202E', '');
    final collapsed = noRLO.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.length > maxLen ? collapsed.substring(0, maxLen) : collapsed;
  }

  bool _isSafeDocId(String id) {
    return RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(id);
  }

  double _sanitizeCuota(String raw) {
    final s = raw.replaceAll(',', '.').trim();
    final v = double.tryParse(s) ?? 0.0;
    if (v.isNaN || v.isInfinite) return 0.0;
    return (v.clamp(1.01, 10000.0)).toDouble();
  }

  /// ✅ stake permite decimales; se guarda como double
  double _sanitizeStake(String raw) {
    final s = raw.replaceAll(',', '.').trim();
    final v = double.tryParse(s) ?? 0.0;
    if (v.isNaN || v.isInfinite) return 0.0;
    return (v.clamp(0.1, 10.0)).toDouble();
  }

  // ======= Imagen: visor + helper sin recortes =======
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
        borderRadius: kRadius,
        child: Image.network(
          url,
          width: double.infinity,
          fit: BoxFit.fitWidth, // 🔸 sin recortes
          errorBuilder: (_, __, ___) => const SizedBox(
            height: 140,
            child: Center(child: Text('⚠️ Imagen no disponible', style: TextStyle(color: Colors.white70))),
          ),
        ),
      ),
    );
  }

  // ======= SUBIR TEXTO =======
  Future<void> _enviarTexto() async {
    if (_sendingText) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Debes iniciar sesión')),
      );
      return;
    }

    final sanitized = _sanitizeText(_textoCtrl.text);
    if (sanitized.isEmpty) return;

    _sendingText = true;
    FocusScope.of(context).unfocus();

    try {
      final uid = user.uid;
      final postsCol = FirebaseFirestore.instance.collection('canales').doc(uid).collection('posts');
      final docId = postsCol.doc().id;

      final data = {
        'type': 'texto',
        'content': sanitized,
        'postedAt': FieldValue.serverTimestamp(),
        'views': 0,
        'viewers': <String>[],
      };

      await postsCol.doc(docId).set(data);
      _textoCtrl.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
      }
    } finally {
      _sendingText = false;
    }
  }

  // ======= FORMULARIO DE PRONOSTICO =======
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
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Debes iniciar sesión')),
        );
        return null;
      }
      final uid = user.uid;

      final bytes = await _pickedImage!.readAsBytes();

      // límite de peso (6 MB)
      const maxBytes = 6 * 1024 * 1024;
      if (bytes.length > maxBytes) {
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Imagen demasiado pesada (máx 6 MB).')),
        );
        return null;
      }

      // detectar tipo
      final t = _detectImageType(bytes);
      if (t == _ImageType.unknown) {
        if (!mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Formato de imagen no soportado.')),
        );
        return null;
      }

      final ext = {
        _ImageType.jpeg: 'jpg',
        _ImageType.png: 'png',
        _ImageType.gif: 'gif',
        _ImageType.webp: 'webp',
      }[t]!;

      final contentType = {
        _ImageType.jpeg: 'image/jpeg',
        _ImageType.png: 'image/png',
        _ImageType.gif: 'image/gif',
        _ImageType.webp: 'image/webp',
      }[t]!;

      final ref = FirebaseStorage.instance
          .ref()
          .child('posts')
          .child(uid)
          .child('${DateTime.now().millisecondsSinceEpoch}.$ext');

      await ref.putData(
        bytes,
        SettableMetadata(contentType: contentType),
      );

      return await ref.getDownloadURL();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error al subir imagen: $e")),
        );
      }
      return null;
    }
  }

  Future<void> _crearPronostico() async {
    if (_creatingTip) return;
    if (!_formKey.currentState!.validate()) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Debes iniciar sesión')),
      );
      return;
    }

    _creatingTip = true;
    try {
      final uid = user.uid;
      final imageUrl = await _uploadImage();

      // sanitizar
      final sport = _sanitizeText(_sport.text, maxLen: 60);
      final evento = _sanitizeText(_evento.text, maxLen: 120);
      final seleccion = _sanitizeText(_seleccion.text, maxLen: 120);
      final cuota = _sanitizeCuota(_cuota.text);
      final stake = _sanitizeStake(_stake.text);

      final postsCol = FirebaseFirestore.instance.collection('canales').doc(uid).collection('posts');
      final docId = postsCol.doc().id;

      final postData = {
        'type': 'pronostico',
        'sport': sport,
        'evento': evento,
        'seleccion': seleccion,
        'cuota': cuota,
        'stake': stake,
        'imageUrl': imageUrl,
        'postedAt': FieldValue.serverTimestamp(),
        'status': 'open',
        'tipsterId': uid,
        'views': 0,
        'viewers': <String>[],
      };

      await postsCol.doc(docId).set(postData);

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✅ Pronóstico creado')));

      _sport.clear();
      _evento.clear();
      _seleccion.clear();
      _cuota.clear();
      _stake.clear();
      setState(() => _pickedImage = null);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error: $e')));
      }
    } finally {
      _creatingTip = false;
    }
  }

  // ======= BORRAR / EDITAR =======
  Future<void> _borrarPost(String postId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Debes iniciar sesión')),
      );
      return;
    }
    if (!_isSafeDocId(postId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ ID no válido')),
      );
      return;
    }

    final uid = user.uid;
    try {
      final canalRef = FirebaseFirestore.instance.collection('canales').doc(uid).collection('posts');

      final snap = await canalRef.doc(postId).get();
      final data = snap.data();

      if (data == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Post no encontrado')));
        }
        return;
      }

      final tipo = data['type'];
      await canalRef.doc(postId).delete();

      if (tipo == 'resultado') {
        final originalPostId = data['postId'];
        final apuestaSnap = await FirebaseFirestore.instance
            .collection('apuesta_resuelta')
            .where('uid', isEqualTo: uid)
            .where('postId', isEqualTo: originalPostId)
            .get();

        for (var doc in apuestaSnap.docs) {
          final resolucion = (doc['resolucion'] as num?)?.toDouble() ?? 0.0;
          await doc.reference.delete();

          final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
          await FirebaseFirestore.instance.runTransaction((tx) async {
            final uSnap = await tx.get(userRef);
            final current = (uSnap.data()?['unidades'] ?? 0).toDouble();
            tx.update(userRef, {"unidades": current - resolucion});
          });
        }
      } else if (tipo == 'pronostico') {
        final resultadoSnap = await canalRef
            .where('type', isEqualTo: 'resultado')
            .where('postId', isEqualTo: postId)
            .get();
        for (var doc in resultadoSnap.docs) {
          await doc.reference.delete();
        }

        final apuestaSnap = await FirebaseFirestore.instance
            .collection('apuesta_resuelta')
            .where('uid', isEqualTo: uid)
            .where('postId', isEqualTo: postId)
            .get();

        for (var doc in apuestaSnap.docs) {
          final resolucion = (doc['resolucion'] as num?)?.toDouble() ?? 0.0;
          await doc.reference.delete();

          final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
          await FirebaseFirestore.instance.runTransaction((tx) async {
            final uSnap = await tx.get(userRef);
            final current = (uSnap.data()?['unidades'] ?? 0).toDouble();
            tx.update(userRef, {"unidades": current - resolucion});
          });
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🗑️ Post eliminado')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error eliminando: $e')));
      }
    }
  }

  Future<void> _editarPost(String postId, Map<String, dynamic> data) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Debes iniciar sesión')),
      );
      return;
    }
    if (!_isSafeDocId(postId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ ID no válido')),
      );
      return;
    }

    try {
      final safeData = Map<String, dynamic>.from(data);
      if (safeData.containsKey('content')) {
        safeData['content'] = _sanitizeText('${safeData['content']}');
      }
      if (safeData.containsKey('sport')) {
        safeData['sport'] = _sanitizeText('${safeData['sport']}', maxLen: 60);
      }
      if (safeData.containsKey('evento')) {
        safeData['evento'] = _sanitizeText('${safeData['evento']}', maxLen: 120);
      }
      if (safeData.containsKey('seleccion')) {
        safeData['seleccion'] = _sanitizeText('${safeData['seleccion']}', maxLen: 120);
      }
      if (safeData.containsKey('cuota')) {
        safeData['cuota'] = _sanitizeCuota('${safeData['cuota']}');
      }
      if (safeData.containsKey('stake')) {
        safeData['stake'] = _sanitizeStake('${safeData['stake']}');
      }

      await FirebaseFirestore.instance
          .collection('canales')
          .doc(user.uid)
          .collection('posts')
          .doc(postId)
          .update(safeData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('✏️ Post actualizado')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('❌ Error editando: $e')));
      }
    }
  }

  // ======= RESOLVER PRONOSTICO =======
  Future<void> _resolverPronostico(String postId, Map<String, dynamic> data, String status) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Debes iniciar sesión')),
      );
      return;
    }
    if (!_isSafeDocId(postId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ ID no válido')),
      );
      return;
    }

    final uid = user.uid;
    final cuota = (data['cuota'] as num?)?.toDouble() ?? 0.0;
    final stake = (data['stake'] as num?)?.toDouble() ?? 0.0;

    double resolucion = 0;
    if (status == 'won') {
      resolucion = (stake * cuota) - stake;
    } else if (status == 'lost') {
      resolucion = -stake;
    }

    final apuestaRef = FirebaseFirestore.instance.collection('apuesta_resuelta');
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

    final canalPosts = FirebaseFirestore.instance.collection('canales').doc(uid).collection('posts');

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

    final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(userRef);
      final current = (snap.data()?['unidades'] ?? 0).toDouble();
      final nuevoTotal = current - (resolucionAnterior ?? 0) + resolucion;
      tx.update(userRef, {"unidades": nuevoTotal});
    });

    await _editarPost(postId, {"status": status});
  }

  // ======= VISITAS ÚNICAS =======
  Future<void> _registrarVisita(String ownerUid, String postId) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    if (!_isSafeDocId(ownerUid) || !_isSafeDocId(postId)) return;

    final currentUid = user.uid;
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

  // ======= FECHAS =======
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

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const Scaffold(
        backgroundColor: kDarkBg,
        body: Center(child: Text('Debes iniciar sesión', style: TextStyle(color: Colors.white70))),
      );
    }

    return Scaffold(
      backgroundColor: kDarkBg,
      appBar: AppBar(
        backgroundColor: kDarkBg,
        elevation: 0,
        title: StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('canales').doc(user.uid).snapshots(),
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const Text("Cargando...");
            }
            final data = snapshot.data!.data() as Map<String, dynamic>?;
            final nombre = data?['nombre_canal'] ?? "Mi canal";
            final foto = data?['foto_canal'];

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
                  if (_isValidHttpUrl(foto)) CircleAvatar(backgroundImage: NetworkImage(foto))
                  else const CircleAvatar(child: Icon(Icons.person)),
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
                        "${(data?['seguidores'] as List?)?.length ?? 0} seguidores",
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
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
                  controller: _scrollController,
                  padding: const EdgeInsets.all(10),
                  itemCount: posts.length,
                  itemBuilder: (ctx, i) {
                    final data = posts[i].data() as Map<String, dynamic>;
                    final postId = posts[i].id;

                    final ts = (data['postedAt'] as Timestamp?)?.toDate();
                    final fecha = ts != null ? _formatDate(ts) : '';

                    final thisDateKey = ts != null ? "${ts.year}-${ts.month}-${ts.day}" : '';

                    List<Widget> children = [];

                    if (thisDateKey != lastDate && ts != null) {
                      children.add(
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                DateFormat.yMMMd().format(ts),
                                style: const TextStyle(fontSize: 12, color: Colors.white70),
                              ),
                            ),
                          ),
                        ),
                      );
                      lastDate = thisDateKey;
                    }

                    _registrarVisita(user.uid, postId);

                    // TEXTO
                    if (data['type'] == 'texto') {
                      children.add(
                        Align(
                          alignment: Alignment.centerRight,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            padding: const EdgeInsets.all(10),
                            decoration: const BoxDecoration(
                              color: kFieldBg,
                              borderRadius: kRadius,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        data['content'] ?? '',
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                    ),
                                    Theme(
                                      data: Theme.of(context).copyWith(
                                        popupMenuTheme: const PopupMenuThemeData(
                                          color: kFieldBg,
                                          textStyle: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      child: PopupMenuButton<String>(
                                        iconColor: Colors.white70,
                                        onSelected: (value) {
                                          if (value == 'delete') {
                                            _borrarPost(postId);
                                          } else if (value == 'edit') {
                                            final ctrl = TextEditingController(text: data['content']);
                                            showDialog(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                backgroundColor: kFieldBg,
                                                title: const Text("Editar mensaje", style: TextStyle(color: Colors.white)),
                                                content: TextField(
                                                  controller: ctrl,
                                                  style: const TextStyle(color: Colors.white),
                                                  inputFormatters: [LengthLimitingTextInputFormatter(500)],
                                                  decoration: _decor("Mensaje", Icons.edit),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(ctx),
                                                    child: const Text("Cancelar"),
                                                  ),
                                                  ElevatedButton(
                                                    style: ElevatedButton.styleFrom(
                                                      backgroundColor: kPrimaryGreen, foregroundColor: Colors.black),
                                                    onPressed: () {
                                                      _editarPost(postId, {"content": _sanitizeText(ctrl.text)});
                                                      Navigator.pop(ctx);
                                                    },
                                                    child: const Text("Guardar"),
                                                  ),
                                                ],
                                              ),
                                            );
                                          }
                                        },
                                        itemBuilder: (context) => const [
                                          PopupMenuItem(value: 'edit', child: Text("✏️ Editar", style: TextStyle(color: Colors.white))),
                                          PopupMenuItem(value: 'delete', child: Text("🗑️ Eliminar", style: TextStyle(color: Colors.white))),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (fecha.isNotEmpty)
                                      Text("🗓️ $fecha", style: const TextStyle(fontSize: 10, color: Colors.white54)),
                                    Text("👀 ${data['views'] ?? 0}", style: const TextStyle(fontSize: 10, color: Colors.white54)),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
                    // PRONOSTICO
                    else if (data['type'] == 'pronostico') {
                      children.add(
                        Card(
                          color: kFieldBg,
                          shape: RoundedRectangleBorder(borderRadius: kRadius, side: const BorderSide(color: kPrimaryGreen, width: 1)),
                          margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        "Selección: ${data['seleccion'] ?? ''}",
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                      ),
                                    ),
                                    Theme(
                                      data: Theme.of(context).copyWith(
                                        popupMenuTheme: const PopupMenuThemeData(
                                          color: kFieldBg,
                                          textStyle: TextStyle(color: Colors.white),
                                        ),
                                      ),
                                      child: PopupMenuButton<String>(
                                        iconColor: Colors.white70,
                                        onSelected: (value) async {
                                          if (value == 'delete') {
                                            _borrarPost(postId);
                                          } else if (value == 'edit') {
                                            _sport.text = data['sport'] ?? '';
                                            _evento.text = data['evento'] ?? '';
                                            _seleccion.text = data['seleccion'] ?? '';
                                            _cuota.text = data['cuota'].toString();
                                            _stake.text = (data['stake'] as num?)?.toDouble().toString() ?? '';
                                            _abrirFormularioPronostico(); // crea uno nuevo reusando UI
                                          } else if (value == 'won' || value == 'lost') {
                                            await _resolverPronostico(postId, data, value);
                                          }
                                        },
                                        itemBuilder: (context) => const [
                                          PopupMenuItem(value: 'edit', child: Text("✏️ Editar", style: TextStyle(color: Colors.white))),
                                          PopupMenuItem(value: 'delete', child: Text("🗑️ Eliminar", style: TextStyle(color: Colors.white))),
                                          PopupMenuItem(value: 'won', child: Text("✅ Acertada", style: TextStyle(color: Colors.white))),
                                          PopupMenuItem(value: 'lost', child: Text("❌ Fallada", style: TextStyle(color: Colors.white))),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(children: const [Icon(Icons.sports, color: Colors.white70, size: 18), SizedBox(width: 4)]),
                                Text("${data['sport'] ?? ''}", style: const TextStyle(color: Colors.white70)),
                                Row(children: const [Icon(Icons.flag, color: Colors.white70, size: 18), SizedBox(width: 4)]),
                                Text("${data['evento'] ?? ''}", style: const TextStyle(color: Colors.white70)),
                                Row(children: const [Icon(Icons.monetization_on, color: kPrimaryGreen, size: 18), SizedBox(width: 4)]),
                                Text("Cuota: ${data['cuota']}", style: const TextStyle(color: Colors.white70)),
                                Row(children: const [Icon(Icons.casino, color: Colors.orangeAccent, size: 18), SizedBox(width: 4)]),
                                Text("Stake: ${data['stake']}", style: const TextStyle(color: Colors.white70)),
                                if (_isValidHttpUrl(data['imageUrl'] is String ? data['imageUrl'] as String : null))
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: _postImage(data['imageUrl']),
                                  ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    if (fecha.isNotEmpty)
                                      Text("🗓️ $fecha", style: const TextStyle(fontSize: 10, color: Colors.white54))
                                    else
                                      const SizedBox.shrink(),
                                    Row(
                                      children: [
                                        if (data['status'] == 'won')
                                          const Text("✅ Acertada", style: TextStyle(color: kPrimaryGreen)),
                                        if (data['status'] == 'lost')
                                          const Text("❌ Fallada", style: TextStyle(color: Colors.redAccent)),
                                        if (data['status'] == 'open')
                                          const Text("🟡 Abierta", style: TextStyle(color: Colors.amber)),
                                        Text("  👀 ${data['views'] ?? 0}", style: const TextStyle(fontSize: 10, color: Colors.white54)),
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
                    // RESULTADO
                    else if (data['type'] == 'resultado') {
                      final resolucion = (data['resolucion'] as num?)?.toDouble() ?? 0.0;
                      final positivo = resolucion >= 0;
                      final texto = positivo
                          ? "+ ${resolucion.toStringAsFixed(2)} UNIDADES"
                          : "- ${resolucion.abs().toStringAsFixed(2)} UNIDADES";

                      children.add(
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: positivo ? kPrimaryGreen : Colors.redAccent,
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
                                Icon(positivo ? Icons.trending_up : Icons.trending_down,
                                    color: positivo ? kPrimaryGreen : Colors.redAccent, size: 22),
                                const SizedBox(width: 8),
                                Text(
                                  texto,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.1,
                                    color: positivo ? kPrimaryGreen : Colors.redAccent,
                                  ),
                                ),
                                Theme(
                                  data: Theme.of(context).copyWith(
                                    popupMenuTheme: const PopupMenuThemeData(
                                      color: kFieldBg,
                                      textStyle: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  child: PopupMenuButton<String>(
                                    iconColor: Colors.white70,
                                    onSelected: (value) async {
                                      if (value == 'delete') {
                                        await _borrarPost(postId);
                                      } else if (value == 'won' || value == 'lost') {
                                        final snap = await FirebaseFirestore.instance
                                            .collection('canales')
                                            .doc(user.uid)
                                            .collection('posts')
                                            .doc(data['postId'])
                                            .get();

                                        if (snap.exists) {
                                          final p = snap.data() as Map<String, dynamic>;
                                          await _resolverPronostico(data['postId'], p, value);
                                        }
                                      }
                                    },
                                    itemBuilder: (context) => const [
                                      PopupMenuItem(value: 'won', child: Text("✅ Marcar como Acertada", style: TextStyle(color: Colors.white))),
                                      PopupMenuItem(value: 'lost', child: Text("❌ Marcar como Fallada", style: TextStyle(color: Colors.white))),
                                      PopupMenuItem(value: 'delete', child: Text("🗑️ Eliminar", style: TextStyle(color: Colors.white))),
                                    ],
                                  ),
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
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _textoCtrl,
                      style: const TextStyle(color: Colors.white),
                      inputFormatters: [LengthLimitingTextInputFormatter(500)],
                      decoration: InputDecoration(
                        hintText: "Escribe algo...",
                        hintStyle: const TextStyle(color: Colors.white54),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        filled: true,
                        fillColor: kFieldBg,
                        enabledBorder: const OutlineInputBorder(
                          borderRadius: kRadius,
                          borderSide: BorderSide(color: kPrimaryGreen, width: 1),
                        ),
                        focusedBorder: const OutlineInputBorder(
                          borderRadius: kRadius,
                          borderSide: BorderSide(color: kPrimaryGreen, width: 2),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    onPressed: _enviarTexto,
                    icon: const Icon(Icons.send, color: kPrimaryGreen),
                  ),
                  IconButton(
                    onPressed: _abrirFormularioPronostico,
                    icon: const Icon(Icons.add_chart, color: kPrimaryGreen),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _decor(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: kPrimaryGreen),
      filled: true,
      fillColor: kFieldBg,
      labelStyle: const TextStyle(color: Colors.white70),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: const OutlineInputBorder(
        borderRadius: kRadius,
        borderSide: BorderSide(color: kPrimaryGreen, width: 1),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: kRadius,
        borderSide: BorderSide(color: kPrimaryGreen, width: 2),
      ),
    );
  }

  void _abrirFormularioPronostico() {
    showModalBottomSheet(
      isScrollControlled: true,
      backgroundColor: kDarkBg,
      context: context,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.92,
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 4),
                    Center(
                      child: Container(
                        width: 50, height: 5,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      "Nuevo Pronóstico",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _sport,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: _decor("Deporte", Icons.sports),
                      inputFormatters: [LengthLimitingTextInputFormatter(60)],
                      validator: (v) {
                        final s = _sanitizeText(v ?? '');
                        if (s.isEmpty) return "Introduce un deporte";
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _evento,
                      style: const TextStyle(color: Colors.white),
                      decoration: _decor("Evento", Icons.flag),
                      inputFormatters: [LengthLimitingTextInputFormatter(120)],
                      validator: (v) {
                        final s = _sanitizeText(v ?? '');
                        if (s.isEmpty) return "Introduce un evento";
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _seleccion,
                      style: const TextStyle(color: Colors.white),
                      decoration: _decor("Selección", Icons.checklist),
                      inputFormatters: [LengthLimitingTextInputFormatter(120)],
                      validator: (v) {
                        final s = _sanitizeText(v ?? '');
                        if (s.isEmpty) return "Introduce selección";
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _cuota,
                      style: const TextStyle(color: Colors.white),
                      decoration: _decor("Cuota", Icons.monetization_on),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d\.,]')),
                        LengthLimitingTextInputFormatter(10),
                      ],
                      validator: (v) {
                        final x = _sanitizeCuota(v ?? '');
                        if (x < 1.01) return "Introduce una cuota válida";
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _stake,
                      style: const TextStyle(color: Colors.white),
                      decoration: _decor("Stake (decimales permitidos)", Icons.casino),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[\d\.,]')),
                        LengthLimitingTextInputFormatter(5),
                      ],
                      validator: (v) {
                        final x = _sanitizeStake(v ?? '');
                        if (x <= 0 || x > 10) return "Stake 0.1 - 10.0";
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        if (_pickedImage == null)
                          const Text("Sin imagen", style: TextStyle(color: Colors.white70))
                        else if (kIsWeb)
                          Expanded(
                            child: ClipRRect(
                              borderRadius: kRadius,
                              child: Image.network(
                                _pickedImage!.path,
                                height: 100, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox(
                                  height: 100,
                                  child: Center(child: Text('⚠️ Error de vista previa', style: TextStyle(color: Colors.white70))),
                                ),
                              ),
                            ),
                          )
                        else
                          Expanded(
                            child: ClipRRect(
                              borderRadius: kRadius,
                              child: Image.file(
                                File(_pickedImage!.path),
                                height: 100, fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox(
                                  height: 100,
                                  child: Center(child: Text('⚠️ Error de vista previa', style: TextStyle(color: Colors.white70))),
                                ),
                              ),
                            ),
                          ),
                        IconButton(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.image, color: kPrimaryGreen),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _crearPronostico,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimaryGreen,
                          foregroundColor: Colors.black,
                          shape: RoundedRectangleBorder(borderRadius: kRadius),
                        ),
                        child: const Text("Aceptar", style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _textoCtrl.dispose();
    _sport.dispose();
    _evento.dispose();
    _seleccion.dispose();
    _cuota.dispose();
    _stake.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
