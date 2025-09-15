// create_channel_page.dart
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'tipster_page.dart';

class CreateChannelPage extends StatefulWidget {
  final String uid;
  final String email;

  const CreateChannelPage({super.key, required this.uid, required this.email});

  @override
  State<CreateChannelPage> createState() => _CreateChannelPageState();
}

class _CreateChannelPageState extends State<CreateChannelPage> {
  final _formKey = GlobalKey<FormState>();
  final _nombreCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  XFile? _pickedImage;
  Uint8List? _pickedBytes;
  bool _loading = false;

  // ---- Estilo consistente con la app ----
  Color get _bg => const Color(0xFF121212);
  Color get _card => const Color(0xFF1E1E1E);
  Color get _accent => Colors.greenAccent[400]!;
  Color get _text => Colors.white;
  Color get _muted => Colors.white70;

  ButtonStyle get _primaryBtn => ElevatedButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      );
  ButtonStyle get _outlineBtn => OutlinedButton.styleFrom(
        side: BorderSide(color: _accent, width: 1.4),
        foregroundColor: _accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      );

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _slog(String msg) {
    if (!kReleaseMode) debugPrint(msg);
  }

  // ------------------ Helpers ------------------
  static bool _isSafeUid(String uid) =>
      RegExp(r'^[A-Za-z0-9_-]{6,128}$').hasMatch(uid);

  static String _sanitizeText(String input, {int maxLen = 100}) {
    final trimmed =
        input.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
    if (trimmed.isEmpty) return '';
    final regex =
        RegExp(r'^[a-zA-Z0-9áéíóúüñÁÉÍÓÚÜÑ\s\-_.,!?\(\)]+$'); // básicos
    final safe = regex.hasMatch(trimmed) ? trimmed : '';
    return safe.length > maxLen ? safe.substring(0, maxLen) : safe;
  }

  static String _sanitizeEmail(String input) {
    final trimmed = input.trim().toLowerCase();
    final regex = RegExp(r'^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$');
    return regex.hasMatch(trimmed) ? trimmed : '';
  }

  static String _maskUid(String uid) {
    if (uid.length <= 6) return uid;
    return '${uid.substring(0, 3)}***${uid.substring(uid.length - 3)}';
  }

  /// Firma simple → MIME permitido o null si no soportado
  static String? _detectImageMime(Uint8List data) {
    if (data.lengthInBytes >= 3 &&
        data[0] == 0xFF &&
        data[1] == 0xD8 &&
        data[2] == 0xFF) return 'image/jpeg';
    if (data.lengthInBytes >= 8 &&
        data[0] == 0x89 &&
        data[1] == 0x50 &&
        data[2] == 0x4E &&
        data[3] == 0x47 &&
        data[4] == 0x0D &&
        data[5] == 0x0A &&
        data[6] == 0x1A &&
        data[7] == 0x0A) return 'image/png';
    if (data.lengthInBytes >= 3 &&
        data[0] == 0x47 &&
        data[1] == 0x49 &&
        data[2] == 0x46) return 'image/gif';
    if (data.lengthInBytes >= 12 &&
        data[0] == 0x52 &&
        data[1] == 0x49 &&
        data[2] == 0x46 &&
        data[3] == 0x46 &&
        data[8] == 0x57 &&
        data[9] == 0x45 &&
        data[10] == 0x42 &&
        data[11] == 0x50) return 'image/webp';
    // HEIC/HEIF heurística simple
    if (data.lengthInBytes >= 12) {
      final ftyp = String.fromCharCodes(data.sublist(4, 8));
      if (ftyp == 'ftyp') {
        final brand = String.fromCharCodes(data.sublist(8, 12)).toLowerCase();
        if (brand.contains('heic') || brand.contains('heif')) return 'image/heic';
      }
    }
    return null;
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked =
          await picker.pickImage(source: ImageSource.gallery, imageQuality: 85, maxWidth: 1200, maxHeight: 1200);
      if (picked != null) {
        final bytes = await picked.readAsBytes();

        // Tamaño máx 6MB (coherente con storage.rules)
        const maxBytes = 6 * 1024 * 1024;
        if (bytes.length > maxBytes) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Imagen demasiado pesada (máx 6 MB).')),
          );
          return;
        }

        final mime = _detectImageMime(bytes);
        const allowed = {
          'image/jpeg', 'image/png', 'image/webp', 'image/gif', 'image/heic', 'image/heif'
        };
        if (mime == null || !allowed.contains(mime)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('❌ Formato no soportado. Usa JPG/PNG/WEBP/GIF/HEIC.')),
          );
          return;
        }

        setState(() {
          _pickedImage = picked;
          _pickedBytes = bytes;
        });
      }
    } catch (e) {
      _slog('⚠️ Error al seleccionar imagen: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Error al seleccionar la imagen')),
      );
    }
  }

  Future<void> _createChannel() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _loading = true);

    String? imageUrl;
    try {
      // Defensa: confirmar sesión vs widget.uid
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid == null || currentUid != widget.uid || !_isSafeUid(widget.uid)) {
        _showError('⛔ Sesión inconsistente. Inicia sesión de nuevo.');
        return;
      }

      final nombre = _sanitizeText(_nombreCtrl.text, maxLen: 60);
      final descripcion = _sanitizeText(_descCtrl.text, maxLen: 200);
      final email = _sanitizeEmail(widget.email); // opcional

      if (nombre.isEmpty) {
        _showError('⚠️ El nombre del canal no es válido');
        return;
      }

      final canalRef =
          FirebaseFirestore.instance.collection('canales').doc(widget.uid);
      final canalSnap = await canalRef.get();
      final exists = canalSnap.exists;

      // Subir imagen si hay
      if (_pickedBytes != null) {
        final bytes = _pickedBytes!;
        final mime = _detectImageMime(bytes) ?? 'image/jpeg';

        final storageRef = FirebaseStorage.instance
            .ref()
            .child('canales/${widget.uid}/foto_perfil.jpg');

        await storageRef.putData(
          bytes,
          SettableMetadata(
            contentType: mime,
            cacheControl: 'public,max-age=3600',
          ),
        );

        imageUrl = await storageRef.getDownloadURL();
      }

      if (!exists) {
        // Crear canal NUEVO (cumple regla: idTipster == uid)
        await canalRef.set({
          'ownerId'            : widget.uid,            // auxiliar
          'idTipster'          : widget.uid,            // 🔐 requerido por reglas
          'email'              : email,                 // normalizado (o '')
          'nombre_canal'       : nombre,
          'nombre_canal_lower' : nombre.toLowerCase(),
          'descripcion'        : descripcion,
          'foto_canal'         : imageUrl ?? '',
          'role'               : 'tipster',             // útil para badge
          'isPublic'           : true,                  // por defecto público
          'seguidores'         : <String>[],            // inicial vacío explícito
          'numero_seguidores'  : 0,
          'createdAt'          : FieldValue.serverTimestamp(),
          'updatedAt'          : FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        _slog('✅ Canal creado para UID: ${_maskUid(widget.uid)}');
      } else {
        // UPDATE seguro: no tocamos seguidores ni contadores ni role
        final data = <String, dynamic>{
          'nombre_canal'       : nombre,
          'nombre_canal_lower' : nombre.toLowerCase(),
          'descripcion'        : descripcion,
          'updatedAt'          : FieldValue.serverTimestamp(),
        };
        if (imageUrl != null) data['foto_canal'] = imageUrl;

        // Refijamos idTipster (no daña, mantiene la invariante de reglas)
        data['idTipster'] = widget.uid;

        await canalRef.set(data, SetOptions(merge: true));
        _slog('🔄 Canal actualizado para UID: ${_maskUid(widget.uid)}');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(exists ? '✅ Canal actualizado' : '✅ Canal creado'),
        ),
      );

      // Navegar a "Mi Canal" (como lo tenías)
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TipsterPage()),
      );
    } on FirebaseException catch (e) {
      _slog('❌ Firebase: ${e.code} - ${e.message}');
      if (!mounted) return;
      _showError('❌ Error creando canal (${e.code})');
    } catch (e) {
      _slog('❌ Error creando canal: $e');
      if (!mounted) return;
      _showError('❌ Error creando canal');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text('Crear Canal'),
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  // Avatar
                  GestureDetector(
                    onTap: _loading ? null : _pickImage,
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundImage: _pickedBytes != null
                              ? MemoryImage(_pickedBytes!)
                              : null,
                          backgroundColor: Colors.grey.shade800,
                          child: _pickedBytes == null
                              ? const Icon(Icons.add_a_photo,
                                  size: 40, color: Colors.white)
                              : null,
                        ),
                        Positioned(
                          bottom: 4,
                          right: 4,
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: _accent,
                            child: const Icon(Icons.edit, color: Colors.black),
                          ),
                        )
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Card de formulario
                  Card(
                    color: _card,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _nombreCtrl,
                            enabled: !_loading,
                            style: TextStyle(color: _text),
                            decoration: InputDecoration(
                              labelText: 'Nombre del canal',
                              labelStyle: TextStyle(color: _muted),
                              prefixIcon: Icon(Icons.title, color: _accent),
                              enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: _accent)),
                              focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: _accent)),
                            ),
                            validator: (v) {
                              final s = _sanitizeText(v ?? '', maxLen: 60);
                              if (s.isEmpty) return 'Introduce un nombre válido';
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _descCtrl,
                            enabled: !_loading,
                            maxLines: 3,
                            style: TextStyle(color: _text),
                            decoration: InputDecoration(
                              labelText: 'Descripción del canal (opcional)',
                              labelStyle: TextStyle(color: _muted),
                              prefixIcon:
                                  Icon(Icons.description, color: _accent),
                              enabledBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: _accent)),
                              focusedBorder: UnderlineInputBorder(
                                  borderSide: BorderSide(color: _accent)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Botones
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: _primaryBtn,
                      onPressed: _loading ? null : _createChannel,
                      icon: const Icon(Icons.check_circle_outline),
                      label: Text(_loading ? 'Creando…' : 'Crear canal'),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: _outlineBtn,
                      onPressed: _loading ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Volver'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Overlay de carga
          if (_loading)
            Container(
              color: Colors.black.withOpacity(0.25),
              child: const Center(
                child: CircularProgressIndicator(color: Colors.greenAccent),
              ),
            ),
        ],
      ),
    );
  }
}
