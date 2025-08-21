import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

class CreateAccPage extends StatefulWidget {
  const CreateAccPage({super.key});

  @override
  _CreateAccPageState createState() => _CreateAccPageState();
}

class _CreateAccPageState extends State<CreateAccPage> {
  final _formKey = GlobalKey<FormState>();

  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();

  String _selectedCountryCode = "+34"; // prefijo por defecto
  bool _isLoading = false;

  /// 🔐 Generar hash SHA-256
  String hashValue(String input) {
    return sha256.convert(utf8.encode(input.toLowerCase().trim())).toString();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final username = _usernameController.text.trim();
      final email = _emailController.text.trim();
      final phone = '$_selectedCountryCode${_phoneController.text.trim()}';

      final emailHash = hashValue(email);
      final phoneHash = hashValue(phone);

      // 1️⃣ Comprobar username
      final existingUsername = await FirebaseFirestore.instance
          .collection('usernames')
          .doc(username)
          .get();
      if (existingUsername.exists) {
        _showError("⚠️ El nombre de usuario ya está en uso");
        return;
      }

      // 2️⃣ Comprobar email
      final existingEmail = await FirebaseFirestore.instance
          .collection('emails')
          .doc(emailHash)
          .get();
      if (existingEmail.exists) {
        _showError("⚠️ El correo ya está en uso");
        return;
      }

      // 3️⃣ Comprobar teléfono
      final existingPhone = await FirebaseFirestore.instance
          .collection('phones')
          .doc(phoneHash)
          .get();
      if (existingPhone.exists) {
        _showError("⚠️ El número de teléfono ya está en uso");
        return;
      }

      // 4️⃣ Crear usuario en Firebase Auth
      UserCredential userCredential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: _passwordController.text.trim(),
      );

      User? user = userCredential.user;

      if (user != null) {
        final uid = user.uid;

        // 5️⃣ Guardar datos en Firestore
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'email': email,
          'username': username,
          'phone': phone,
          'role': 'user', // 👈 por defecto user
          'createdAt': FieldValue.serverTimestamp(),
        });

        // 6️⃣ Guardar índices únicos
        await FirebaseFirestore.instance.collection('usernames').doc(username).set({'uid': uid});
        await FirebaseFirestore.instance.collection('emails').doc(emailHash).set({'uid': uid});
        await FirebaseFirestore.instance.collection('phones').doc(phoneHash).set({'uid': uid});

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Cuenta creada con éxito")),
        );

        Navigator.pop(context); // volver al login
      }
    } catch (e) {
      _showError("❌ Error: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showError(String msg) {
    setState(() => _isLoading = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  String? _validatePhone(String? value) {
    if (value == null || value.isEmpty) return "Introduce tu número";
    final numeric = RegExp(r'^[0-9]+$');
    if (!numeric.hasMatch(value)) return "Solo se permiten números";
    if (value.length < 6 || value.length > 15) {
      return "Número no válido";
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // 🔹 Logo
                Image.asset(
                  "assets/images/logo.png",
                  height: 100,
                ),
                const SizedBox(height: 20),

                // 🔹 Texto "REGISTRO"
                const Text(
                  "REGISTRO",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 30),

                // EMAIL
                _buildTextField(
                  controller: _emailController,
                  label: "Correo electrónico",
                  icon: Icons.email,
                  validator: (value) =>
                      value!.isEmpty ? "Introduce un correo" : null,
                ),
                const SizedBox(height: 16),

                // USERNAME
                _buildTextField(
                  controller: _usernameController,
                  label: "Nombre de usuario",
                  icon: Icons.person,
                  validator: (value) =>
                      value!.isEmpty ? "Introduce un nombre de usuario" : null,
                ),
                const SizedBox(height: 16),

                // CONTRASEÑA
                _buildTextField(
                  controller: _passwordController,
                  label: "Contraseña",
                  icon: Icons.lock,
                  obscure: true,
                  validator: (value) =>
                      value!.length < 6 ? "Mínimo 6 caracteres" : null,
                ),
                const SizedBox(height: 16),

                // CONFIRMAR CONTRASEÑA
                _buildTextField(
                  controller: _confirmPasswordController,
                  label: "Repetir contraseña",
                  icon: Icons.lock_outline,
                  obscure: true,
                  validator: (value) =>
                      value != _passwordController.text ? "No coinciden" : null,
                ),
                const SizedBox(height: 16),

                // TELÉFONO
                Row(
                  children: [
                    Container(
                      width: 90,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String>(
                        dropdownColor: Colors.grey[900],
                        value: _selectedCountryCode,
                        isExpanded: true,
                        underline: const SizedBox(),
                        style: const TextStyle(color: Colors.white),
                        items: ["+34", "+1", "+44", "+49", "+33"]
                            .map((code) => DropdownMenuItem(
                                  value: code,
                                  child: Text(code),
                                ))
                            .toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedCountryCode = value!;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _buildTextField(
                        controller: _phoneController,
                        label: "Número de teléfono",
                        icon: Icons.phone,
                        keyboardType: TextInputType.phone,
                        validator: _validatePhone,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 30),

                // BOTÓN CREAR CUENTA
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
                          onPressed: _register,
                          child: const Text(
                            "Crear cuenta",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black, // letras negras
                            ),
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 🔹 Helper para textfields con estilo dark
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      validator: validator,
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
