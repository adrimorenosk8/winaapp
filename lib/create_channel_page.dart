import 'dart:typed_data'; // para manejar bytes en web/móvil
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
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

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      final bytes = await picked.readAsBytes();
      setState(() {
        _pickedImage = picked;
        _pickedBytes = bytes;
      });
    }
  }

  Future<void> _createChannel() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _loading = true);

    String? imageUrl;
    try {
      if (_pickedBytes != null && _pickedImage != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child("canales/${widget.uid}/foto_perfil.jpg");

        // 🔹 Subida compatible con Web y móvil
        await storageRef.putData(_pickedBytes!,
            SettableMetadata(contentType: "image/jpeg"));

        imageUrl = await storageRef.getDownloadURL();
      }

      await FirebaseFirestore.instance.collection("canales").doc(widget.uid).set({
        "idTipster": widget.uid,
        "nombre_canal": _nombreCtrl.text.trim(),
        "descripcion_canal": _descCtrl.text.trim(),
        "foto": imageUrl,
        "createdAt": FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TipsterPage()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error creando canal: $e")),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Crear Canal")),
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
                  backgroundImage: _pickedBytes != null
                      ? MemoryImage(_pickedBytes!) // 🔹 Compatible con Web
                      : null,
                  child: _pickedBytes == null
                      ? const Icon(Icons.add_a_photo, size: 40)
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _nombreCtrl,
                decoration: const InputDecoration(
                  labelText: "Nombre del canal",
                  prefixIcon: Icon(Icons.title),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? "Introduce un nombre" : null,
              ),
              const SizedBox(height: 15),
              TextFormField(
                controller: _descCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: "Descripción del canal (opcional)",
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
                      : const Text("Crear canal"),
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
