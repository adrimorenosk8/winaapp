import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';

class EditChannelPage extends StatefulWidget {
  final String canalId;
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

  @override
  void initState() {
    super.initState();
    _nombreCtrl = TextEditingController(text: widget.nombre);
    _descCtrl = TextEditingController(text: widget.descripcion);
  }

  Future<void> _pickImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() => _pickedImage = picked);
    }
  }

  Future<String?> _uploadImageIfNeeded() async {
    if (_pickedImage == null) return widget.foto;

    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final ref = FirebaseStorage.instance
          .ref()
          .child('canales')
          .child(uid)
          .child('foto_perfil.jpg');

      final bytes = await _pickedImage!.readAsBytes();
      await ref.putData(bytes);

      return await ref.getDownloadURL();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("❌ Error al subir imagen: $e")),
        );
      }
      return widget.foto;
    }
  }

  Future<void> _guardarCambios() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      final fotoUrl = await _uploadImageIfNeeded();

      await FirebaseFirestore.instance
          .collection('canales')
          .doc(widget.canalId)
          .update({
        "nombre_canal": _nombreCtrl.text.trim(),
        "descripcion": _descCtrl.text.trim(),
        "foto_canal": fotoUrl,
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Canal actualizado")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final imagenPreview = _pickedImage != null
        ? (kIsWeb
            ? Image.network(_pickedImage!.path, height: 100, width: 100, fit: BoxFit.cover)
            : Image.file(File(_pickedImage!.path), height: 100, width: 100, fit: BoxFit.cover))
        : (widget.foto.isNotEmpty
            ? Image.network(widget.foto, height: 100, width: 100, fit: BoxFit.cover)
            : const Icon(Icons.person, size: 60));

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
                validator: (v) =>
                    v!.isEmpty ? "Introduce un nombre de canal" : null,
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
                onPressed: _guardarCambios,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.greenAccent[700],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text("Guardar cambios"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
