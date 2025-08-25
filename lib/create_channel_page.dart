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

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _slog(String msg) { if (!kReleaseMode) debugPrint(msg); }

  // ------------------ Helpers ------------------
  static bool _isSafeUid(String uid) => RegExp(r'^[A-Za-z0-9_-]{6,128}$').hasMatch(uid);

  static String _sanitizeText(String input, {int maxLen = 100}) {
    final trimmed = input.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
    if (trimmed.isEmpty) return '';
    // letras, números, espacios y signos básicos
    final regex = RegExp(r'^[a-zA-Z0-9áéíóúüñÁÉÍÓÚÜÑ\s\-_.,!?\(\)]+$');
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
        data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) {
      return 'image/jpeg';
    }
    if (data.lengthInBytes >= 8 &&
        data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 &&
        data[4] == 0x0D && data[5] == 0x0A && data[6] == 0x1A && data[7] == 0x0A) {
      return 'image/png';
    }
    if (data.lengthInBytes >= 12 &&
        data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46) {
      return 'image/gif';
    }
    if (data.lengthInBytes >= 12 &&
        data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 &&
        data[8] == 0x57 && data[9] == 0x45 && data[10] == 0x42 && data[11] == 0x50) {
      return 'image/webp';
    }
    // HEIC/HEIF heurística light
    if (data.lengthInBytes >= 12) {
      final ftyp = String.fromCharCodes(data.sublist(4, 8));
      if (ftyp == 'ftyp') {
        final brand = String.fromCharCodes(data.sublist(8, 12)).toLowerCase();
        if (brand.contains('heic') || brand.contains('heif')) {
          return 'image/heic'; // tratamos ambos como heic
        }
      }
    }
    return null;
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
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
          'image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif'
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('❌ Error al seleccionar la imagen')),
      );
    }
  }

  Future<void> _createChannel() async {
    if (!_formKey.currentState!.validate()) return;

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

      // Guardar canal (campos alineados con el resto de la app)
      await FirebaseFirestore.instance.collection('canales').doc(widget.uid).set({
        'ownerId'            : widget.uid,         // 🔐 reglas
        'idTipster'          : widget.uid,
        'email'              : email,              // normalizado (o '')
        'nombre_canal'       : nombre,
        'nombre_canal_lower' : nombre.toLowerCase(),
        'descripcion'        : descripcion,        // 👈 nombre de campo consistente
        'foto_canal'         : imageUrl ?? '',     // 👈 nombre de campo consistente
        'role'               : 'tipster',          // útil para badges
        'isPublic'           : true,               // por defecto público
        'seguidores'         : FieldValue.arrayUnion(<String>[]), // inicial vacío
        'createdAt'          : FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      _slog('✅ Canal creado para UID: ${_maskUid(widget.uid)}');

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TipsterPage()),
      );
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
      appBar: AppBar(title: const Text('Crear Canal')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              GestureDetector(
                onTap: _pickImage,
                child: CircleAvatar(
                  radius: 60,
                  backgroundImage: _pickedBytes != null ? MemoryImage(_pickedBytes!) : null,
                  child: _pickedBytes == null ? const Icon(Icons.add_a_photo, size: 40) : null,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nombre del canal',
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (v) {
                  final s = _sanitizeText(v ?? '', maxLen: 60);
                  if (s.isEmpty) return 'Introduce un nombre válido';
                  return null;
                },
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Descripción del canal (opcional)',
                  prefixIcon: Icon(Icons.description),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _createChannel,
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text('Crear canal'),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
