import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

class EditChannelPage extends StatefulWidget {
  final String canalId;      // normalmente == uid del tipster
  final String nombre;
  final String descripcion;
  final String foto;

  const EditChannelPage({
    super.key,
    required this.canalId,
    required this.nombre,
    required this.descripcion,
    required this.foto,
  });

  @override
  State<EditChannelPage> createState() => _EditChannelPageState();
}

class _EditChannelPageState extends State<EditChannelPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nombreCtrl;
  late TextEditingController _descCtrl;
  XFile? _pickedImage;
  Uint8List? _pickedBytes;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.nombre);
    _descCtrl = TextEditingController(text: widget.descripcion);
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  // ---------------- Helpers de seguridad/sanitización ----------------
  static bool _isOwnerOfChannel(String currentUid, String canalDocId) {
    // En tu modelo, el doc de canal es canales/{uid_del_tipster}
    return currentUid == canalDocId;
  }

  static String _sanitizeText(String input, {int maxLen = 100}) {
    final trimmed = input.replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
    if (trimmed.isEmpty) return '';
    final regex = RegExp(r'^[a-zA-Z0-9áéíóúüñÁÉÍÓÚÜÑ\s\-_.,!?\(\)]+$');
    final safe = regex.hasMatch(trimmed) ? trimmed : '';
    return safe.length > maxLen ? safe.substring(0, maxLen) : safe;
  }

  static String _toLowerKey(String s) => s.toLowerCase();

  static String? _detectImageMime(Uint8List data) {
    if (data.lengthInBytes >= 3 &&
        data[0] == 0xFF && data[1] == 0xD8 && data[2] == 0xFF) return 'image/jpeg';
    if (data.lengthInBytes >= 8 &&
        data[0] == 0x89 && data[1] == 0x50 && data[2] == 0x4E && data[3] == 0x47 &&
        data[4] == 0x0D && data[5] == 0x0A && data[6] == 0x1A && data[7] == 0x0A) return 'image/png';
    if (data.lengthInBytes >= 12 &&
        data[0] == 0x47 && data[1] == 0x49 && data[2] == 0x46) return 'image/gif';
    if (data.lengthInBytes >= 12 &&
        data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 &&
        data[8] == 0x57 && data[9] == 0x45 && data[10] == 0x42 && data[11] == 0x50) return 'image/webp';
    // HEIC/HEIF heurístico ligero
    if (data.lengthInBytes >= 12) {
      final ftyp = String.fromCharCodes(data.sublist(4, 8));
      if (ftyp == 'ftyp') {
        final brand = String.fromCharCodes(data.sublist(8, 12)).toLowerCase();
        if (brand.contains('heic') || brand.contains('heif')) return 'image/heic';
      }
    }
    return null;
  }

  // ---------------- Imagen ----------------
  Future<void> _pickImage() async {
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      final bytes = await picked.readAsBytes();

      // 6 MB máx (coherente con storage.rules)
      const maxBytes = 6 * 1024 * 1024;
      if (bytes.length > maxBytes) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Imagen demasiado pesada (máx 6 MB).")),
        );
        return;
      }

      final mime = _detectImageMime(bytes);
      const allowed = {
        'image/jpeg','image/png','image/webp','image/gif','image/heic','image/heif'
      };
      if (mime == null || !allowed.contains(mime)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Formato no soportado. Usa JPG/PNG/WEBP/GIF/HEIC.")),
        );
        return;
      }

      setState(() {
        _pickedImage = picked;
        _pickedBytes = bytes;
      });
    } catch (e) {
      debugPrint("❌ Error seleccionando imagen: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error al seleccionar la imagen")),
        );
      }
    }
  }

  Future<String?> _uploadImageIfNeeded() async {
    if (_pickedBytes == null) return widget.foto.isNotEmpty ? widget.foto : null;

    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception("Usuario no autenticado");
      if (!_isOwnerOfChannel(uid, widget.canalId)) {
        throw Exception("No puedes modificar la imagen de este canal");
      }

      final mime = _detectImageMime(_pickedBytes!) ?? 'image/jpeg';

      final ref = FirebaseStorage.instance
          .ref()
          .child('canales')
          .child(uid)
          .child('foto_perfil.jpg');

      await ref.putData(
        _pickedBytes!,
        SettableMetadata(contentType: mime, cacheControl: 'public,max-age=3600'),
      );

      return await ref.getDownloadURL();
    } catch (e) {
      debugPrint("❌ Error al subir imagen: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Error al subir imagen")),
        );
      }
      return widget.foto.isNotEmpty ? widget.foto : null;
    }
  }

  // ---------------- Guardado ----------------
  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final currentUid = FirebaseAuth.instance.currentUser?.uid;
      if (currentUid == null || !_isOwnerOfChannel(currentUid, widget.canalId)) {
        throw Exception("⛔ Sesión inconsistente. Inicia sesión nuevamente.");
      }

      final fotoUrl = await _uploadImageIfNeeded();

      final nombre = _sanitizeText(_nombreCtrl.text, maxLen: 60);
      final descripcion = _sanitizeText(_descCtrl.text, maxLen: 200);

      if (nombre.isEmpty) {
        throw Exception("El nombre del canal no es válido");
      }

      await FirebaseFirestore.instance
          .collection('canales')
          .doc(widget.canalId)
          .update({
        "nombre_canal": nombre,
        "nombre_canal_lower": _toLowerKey(nombre),
        "descripcion": descripcion,     // 👈 consistente con el resto de la app
        "foto_canal": fotoUrl ?? "",    // 👈 consistente con el resto de la app
        "updatedAt": FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Canal actualizado")),
      );
    } catch (e) {
      debugPrint("❌ Error guardando cambios: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error al actualizar canal: $e")),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget imagenPreview;
    if (_pickedBytes != null) {
      imagenPreview = Image.memory(
        _pickedBytes!,
        height: 100, width: 100, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 60),
      );
    } else if (widget.foto.isNotEmpty) {
      imagenPreview = Image.network(
        widget.foto,
        height: 100, width: 100, fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 60),
      );
    } else {
      imagenPreview = const Icon(Icons.person, size: 60);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Editar Canal"),
        backgroundColor: Colors.grey[900],
      ),
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              Center(
                child: Stack(
                  children: [
                    ClipOval(
                      child: Container(
                        width: 100,
                        height: 100,
                        color: Colors.grey[800],
                        child: imagenPreview,
                      ),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        backgroundColor: Colors.grey[700],
                        child: IconButton(
                          onPressed: _pickImage,
                          icon: const Icon(Icons.edit, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nombreCtrl,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Nombre del canal",
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.grey[850],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                validator: (v) {
                  final s = _sanitizeText(v ?? '', maxLen: 60);
                  if (s.isEmpty) return "Introduce un nombre de canal válido";
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: "Descripción del canal",
                  labelStyle: const TextStyle(color: Colors.white70),
                  filled: true,
                  fillColor: Colors.grey[850],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isSaving ? null : _guardarCambios,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text("Guardar cambios"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
