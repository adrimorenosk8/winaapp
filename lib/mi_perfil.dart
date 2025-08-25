import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

/// 👇 (Opcional) wrapper que ya tenías; lo dejo igual por compatibilidad
class HomeWithBottomNav extends StatefulWidget {
  const HomeWithBottomNav({super.key});

  @override
  State<HomeWithBottomNav> createState() => _HomeWithBottomNavState();
}

class _HomeWithBottomNavState extends State<HomeWithBottomNav> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    Center(child: Text("Pronósticos")),
    Center(child: Text("Canales")),
    MiPerfilPage(),
  ];

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        backgroundColor: const Color(0xFF1E1E1E),
        selectedItemColor: Colors.greenAccent[400],
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.sports_soccer), label: "Pronósticos"),
          BottomNavigationBarItem(icon: Icon(Icons.campaign), label: "Canales"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Perfil"),
        ],
      ),
    );
  }
}

class MiPerfilPage extends StatefulWidget {
  const MiPerfilPage({super.key});

  @override
  State<MiPerfilPage> createState() => _MiPerfilPageState();
}

class _MiPerfilPageState extends State<MiPerfilPage> {
  final User? user = FirebaseAuth.instance.currentUser;

  Color get _cardBg => const Color(0xFF1E1E1E);
  Color get _pageBg => const Color(0xFF121212);
  Color get _muted => Colors.white70;
  Color get _text => Colors.white;
  Color get _accent => Colors.greenAccent[400]!;

  ButtonStyle get _primaryBtn => ElevatedButton.styleFrom(
        backgroundColor: _accent,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      );

  ButtonStyle get _dangerBtn => ElevatedButton.styleFrom(
        backgroundColor: Colors.redAccent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      );

  ButtonStyle get _outlineBtn => OutlinedButton.styleFrom(
        side: BorderSide(color: _accent, width: 1.4),
        foregroundColor: _accent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
      );

  String _sanitizeText(dynamic v) {
    if (v == null) return '';
    try {
      return v.toString().replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), '').trim();
    } catch (_) {
      return '';
    }
  }

  bool _looksLikeEmail(String s) {
    final v = s.trim();
    final re = RegExp(r"^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$");
    return re.hasMatch(v) && v.length <= 254;
  }

  Future<void> _cambiarFoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
    if (picked == null) return;

    try {
      final Uint8List bytes = await picked.readAsBytes();
      if (bytes.isEmpty || user == null) return;

      final ref = FirebaseStorage.instance.ref().child("usuarios/${user!.uid}/foto_perfil.jpg");
      await ref.putData(bytes, SettableMetadata(contentType: "image/jpeg"));
      final url = await ref.getDownloadURL();

      await user!.updatePhotoURL(url);
      await user!.reload();

      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ Foto actualizada")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error subiendo la imagen: $e")),
      );
    }
  }

  Future<void> _cambiarEmail() async {
    final controller = TextEditingController();
    final result = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _cardBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      isScrollControlled: true,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16, right: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16, top: 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 6),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 16),
              Text("Cambiar correo", style: TextStyle(color: _text, fontWeight: FontWeight.bold, fontSize: 18)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                style: TextStyle(color: _text),
                decoration: InputDecoration(
                  hintText: "nuevo@correo.com",
                  hintStyle: TextStyle(color: _muted),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accent)),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: _accent)),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: _primaryBtn,
                  onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
                  child: const Text("Enviar verificación"),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );

    final newEmail = result?.trim() ?? '';
    if (newEmail.isEmpty) return;

    if (!_looksLikeEmail(newEmail)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Formato de email inválido.")),
      );
      return;
    }

    try {
      await user?.verifyBeforeUpdateEmail(newEmail);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Te enviamos un correo para verificar el nuevo email.")),
      );
    } on FirebaseAuthException catch (e) {
      String msg = "Error al cambiar el correo.";
      if (e.code == 'requires-recent-login') {
        msg = "Por seguridad, vuelve a iniciar sesión y reinténtalo (requires-recent-login).";
      } else if (e.code == 'invalid-email') {
        msg = "El email no es válido.";
      } else if (e.code == 'email-already-in-use') {
        msg = "Ese email ya está en uso.";
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ $msg")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ $e")));
    }
  }

  Future<void> _resetPassword() async {
    final mail = user?.email;
    if (mail == null || mail.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No hay correo asociado a esta cuenta.")),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: mail);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Te enviamos un correo para restablecer la contraseña.")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("❌ $e")));
    }
  }

  Future<void> _cerrarSesion() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cardBg,
        title: Text("Cerrar sesión", style: TextStyle(color: _text, fontWeight: FontWeight.bold)),
        content: Text("¿Seguro que quieres salir?", style: TextStyle(color: _muted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text("Cancelar", style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            style: _dangerBtn,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text("Cerrar sesión"),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      // incluso si falla, intentamos limpiar la navegación
      debugPrint("Error en signOut: $e");
    }

    if (!mounted) return;

    // Navegación segura al entrypoint (main.dart)
    bool routed = false;
    try {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
      routed = true;
    } catch (_) {
      // Si no tienes rutas nombradas, volvemos a la raíz actual
    }
    if (!routed) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return Scaffold(
        backgroundColor: _pageBg,
        body: const Center(child: Text("No hay usuario autenticado", style: TextStyle(color: Colors.white70))),
      );
    }

    final photoUrl = _sanitizeText(user!.photoURL);
    final email = _sanitizeText(user!.email);
    final uid = _sanitizeText(user!.uid);

    return Scaffold(
      backgroundColor: _pageBg,
      appBar: AppBar(
        title: const Text("Mi Perfil"),
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar + botón editar
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: (photoUrl.isNotEmpty) ? NetworkImage(photoUrl) : null,
                    backgroundColor: Colors.grey.shade800,
                    child: (photoUrl.isEmpty)
                        ? const Icon(Icons.person, size: 64, color: Colors.white)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: InkWell(
                      onTap: _cambiarFoto,
                      borderRadius: BorderRadius.circular(20),
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: _accent,
                        child: const Icon(Icons.edit, color: Colors.black),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Card con datos
            Card(
              color: _cardBg,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ListTile(
                      leading: Icon(Icons.email, color: _accent),
                      title: Text("Correo electrónico", style: TextStyle(color: _muted)),
                      subtitle: Text(email.isEmpty ? "No disponible" : email, style: TextStyle(color: _text)),
                    ),
                    const Divider(color: Colors.white12),
                    ListTile(
                      leading: Icon(Icons.fingerprint, color: _accent),
                      title: Text("UID", style: TextStyle(color: _muted)),
                      subtitle: Text(uid, style: TextStyle(color: _text)),
                    ),
                    const Divider(color: Colors.white12),
                    ListTile(
                      leading: Icon(user!.emailVerified ? Icons.verified : Icons.mark_email_unread, color: _accent),
                      title: Text("Email verificado", style: TextStyle(color: _muted)),
                      subtitle: Text(user!.emailVerified ? "Sí" : "No", style: TextStyle(color: _text)),
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
                onPressed: _cambiarEmail,
                icon: const Icon(Icons.edit),
                label: const Text("Cambiar correo"),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                style: _outlineBtn,
                onPressed: _resetPassword,
                icon: const Icon(Icons.lock_reset),
                label: const Text("Cambiar contraseña"),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: _dangerBtn,
                onPressed: _cerrarSesion,
                icon: const Icon(Icons.logout),
                label: const Text("Cerrar sesión"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
