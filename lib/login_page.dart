import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'create_acc_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;

  Future<void> _login() async {
    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      // 🔥 AuthGate decide a dónde ir
    } on FirebaseAuthException catch (e) {
      String message = "Error desconocido";
      if (e.code == 'user-not-found') {
        message = "No existe un usuario con ese correo";
      } else if (e.code == 'wrong-password') {
        message = "Contraseña incorrecta";
      }
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 🔹 Logo
              Image.asset(
                "assets/images/logo.png",
                height: 120,
              ),
              const SizedBox(height: 40),

              // EMAIL
              _buildTextField(
                controller: _emailController,
                label: "Correo electrónico",
                icon: Icons.email,
              ),
              const SizedBox(height: 16),

              // PASSWORD
              _buildTextField(
                controller: _passwordController,
                label: "Contraseña",
                icon: Icons.lock,
                obscure: true,
              ),
              const SizedBox(height: 30),

              // BOTÓN LOGIN
              _isLoading
                  ? const CircularProgressIndicator(color: Colors.green)
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8), // menos redondo
                          ),
                        ),
                        onPressed: _login,
                        child: const Text(
                          "Iniciar sesión",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Colors.black, // letras negras
                          ),
                        ),
                      ),
                    ),
              const SizedBox(height: 16),

              // BOTÓN CREAR CUENTA
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.green),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => CreateAccPage()),
                    );
                  },
                  child: const Text(
                    "Crear cuenta",
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 🔹 Helper para campos de texto
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.green),
        filled: true,
        fillColor: Colors.grey[900],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.green),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.green, width: 2),
        ),
      ),
    );
  }
}
