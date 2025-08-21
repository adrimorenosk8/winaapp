import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = const [
    Center(child: Text("Pronósticos")),
    Center(child: Text("Canales")),
    MiPerfilPage(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        backgroundColor: Colors.black,
        selectedItemColor: Colors.greenAccent.shade400,
        unselectedItemColor: Colors.grey.shade400,
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.sports_soccer),
            label: "Pronósticos",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.campaign),
            label: "Canales",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: "Perfil",
          ),
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
  final user = FirebaseAuth.instance.currentUser;

  Future<void> _cambiarFoto() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      File imageFile = File(pickedFile.path);
      try {
        await user?.updatePhotoURL(imageFile.path); // demo (Storage recomendado)
        await user?.reload();
        if (mounted) setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Foto actualizada")),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e")),
        );
      }
    }
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    Color color = Colors.green,
    bool outlined = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: outlined
          ? OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: color),
                foregroundColor: color,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: Icon(icon),
              label: Text(label, style: const TextStyle(fontSize: 16)),
              onPressed: onPressed,
            )
          : ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: Icon(icon),
              label: Text(label, style: const TextStyle(fontSize: 16)),
              onPressed: onPressed,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (user == null) {
      return const Scaffold(
        body: Center(child: Text("No hay usuario autenticado")),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Mi Perfil"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Avatar con botón de edición
            Center(
              child: Stack(
                children: [
                  CircleAvatar(
                    radius: 60,
                    backgroundImage: user?.photoURL != null
                        ? FileImage(File(user!.photoURL!))
                        : null,
                    backgroundColor: Colors.grey.shade800,
                    child: user?.photoURL == null
                        ? const Icon(Icons.person, size: 64, color: Colors.white)
                        : null,
                  ),
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: InkWell(
                      onTap: _cambiarFoto,
                      child: CircleAvatar(
                        radius: 20,
                        backgroundColor: Colors.green,
                        child: const Icon(Icons.edit, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Datos del usuario (estilo dark card)
            Card(
              color: Colors.grey.shade900,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.email, color: Colors.green),
                      title: const Text("Correo electrónico",
                          style: TextStyle(color: Colors.white70)),
                      subtitle: Text(user?.email ?? "No disponible",
                          style: const TextStyle(color: Colors.white)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.fingerprint, color: Colors.green),
                      title: const Text("UID",
                          style: TextStyle(color: Colors.white70)),
                      subtitle: Text(user?.uid ?? "No disponible",
                          style: const TextStyle(color: Colors.white)),
                    ),
                    ListTile(
                      leading: const Icon(Icons.verified, color: Colors.green),
                      title: const Text("Email verificado",
                          style: TextStyle(color: Colors.white70)),
                      subtitle: Text(user!.emailVerified ? "Sí" : "No",
                          style: const TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Botones de acción con estilo del login
            _buildActionButton(
              icon: Icons.edit,
              label: "Cambiar correo",
              onPressed: () async {
                final newEmail = await showDialog<String>(
                  context: context,
                  builder: (ctx) {
                    String tempEmail = "";
                    return AlertDialog(
                      backgroundColor: Colors.grey.shade900,
                      title: const Text("Cambiar correo",
                          style: TextStyle(color: Colors.white)),
                      content: TextField(
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: "Nuevo correo",
                          labelStyle: TextStyle(color: Colors.white70),
                          enabledBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.green)),
                          focusedBorder: UnderlineInputBorder(
                              borderSide: BorderSide(color: Colors.green)),
                        ),
                        onChanged: (val) => tempEmail = val,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text("Cancelar",
                              style: TextStyle(color: Colors.white70)),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                          ),
                          onPressed: () => Navigator.pop(ctx, tempEmail),
                          child: const Text("Enviar verificación"),
                        ),
                      ],
                    );
                  },
                );

                if (newEmail != null && newEmail.isNotEmpty) {
                  try {
                    await user?.verifyBeforeUpdateEmail(newEmail);
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            "Se envió un correo de verificación al nuevo email.",
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text("Error: $e")),
                      );
                    }
                  }
                }
              },
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              icon: Icons.lock_reset,
              label: "Cambiar contraseña",
              onPressed: () async {
                if (user?.email != null) {
                  await FirebaseAuth.instance
                      .sendPasswordResetEmail(email: user!.email!);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          "Se envió un correo para restablecer la contraseña.",
                        ),
                      ),
                    );
                  }
                }
              },
            ),
            const SizedBox(height: 12),
            _buildActionButton(
              icon: Icons.logout,
              label: "Cerrar sesión",
              color: Colors.redAccent,
              onPressed: () async {
                await FirebaseAuth.instance.signOut();
                if (mounted) {
                  Navigator.of(context).popUntil((route) => route.isFirst);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
