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
      // --------- Sanitización y normalización ---------
      final email = _sanitizeEmail(_emailController.text);
      final rawUsername = _sanitizeUsername(_usernameController.text);
      final phoneDigits = _sanitizePhone(_phoneController.text);
      final cc = _sanitizeCountryCode(_selectedCountryCode);

      if (email.isEmpty || rawUsername.isEmpty || phoneDigits.isEmpty || cc.isEmpty) {
        _showError("⚠️ Los datos introducidos no son válidos");
        return;
      }

      // Clave normalizada para unicidad (case-insensitive)
      final usernameKey = _usernameKey(rawUsername);
      final phone = '$cc$phoneDigits';

      final emailHash = hashValue(email);
      final phoneHash = hashValue(phone);

      // --------- Crear usuario en Firebase Auth ---------
      final credential = await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: _passwordController.text.trim(),
      );
      final user = credential.user;
      if (user == null) {
        _showError("❌ No se pudo crear el usuario.");
        return;
      }
      final uid = user.uid;

      // --------- Transacción atómica en Firestore ---------
      // Crea users/{uid} y los 3 índices de unicidad en un único paso.
      // Si algo falla (p.ej. username/email/teléfono ya usado), se aborta todo.
      try {
        await FirebaseFirestore.instance.runTransaction((tx) async {
          final userRef = FirebaseFirestore.instance.collection('users').doc(uid);
          final usernameRef = FirebaseFirestore.instance.collection('usernames').doc(usernameKey);
          final emailRef = FirebaseFirestore.instance.collection('emails').doc(emailHash);
          final phoneRef = FirebaseFirestore.instance.collection('phones').doc(phoneHash);

          // Comprobaciones de existencia (anti-TOCTOU, se reintenta si compite)
          if ((await tx.get(usernameRef)).exists) {
            throw StateError('USERNAME_TAKEN');
          }
          if ((await tx.get(emailRef)).exists) {
            throw StateError('EMAIL_TAKEN');
          }
          if ((await tx.get(phoneRef)).exists) {
            throw StateError('PHONE_TAKEN');
          }

          // users/{uid}
          tx.set(userRef, {
            'email': email,
            'username': rawUsername,          // tal como lo introdujo (ya sanitizado)
            'username_lower': usernameKey,    // clave de búsqueda/única
            'phone': phone,
            'role': 'user',
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
            'email_hash': emailHash,
            'phone_hash': phoneHash,
          });

          // Índices de unicidad (permitidos por reglas: create-only, dueños)
          final now = FieldValue.serverTimestamp();
          tx.set(usernameRef, {'uid': uid, 'createdAt': now});
          tx.set(emailRef, {'uid': uid, 'createdAt': now});
          tx.set(phoneRef, {'uid': uid, 'createdAt': now});
        });
      } catch (e) {
        // Rollback: borra el usuario de Auth para no dejar cuentas huérfanas
        try {
          await user.delete();
        } catch (delErr) {
          debugPrint("⚠️ No se pudo borrar el usuario tras fallo de registro: $delErr");
        }

        final msg = e.toString();
        if (msg.contains('USERNAME_TAKEN')) {
          _showError("⚠️ El nombre de usuario ya está en uso");
          return;
        } else if (msg.contains('EMAIL_TAKEN')) {
          _showError("⚠️ El correo ya está en uso");
          return;
        } else if (msg.contains('PHONE_TAKEN')) {
          _showError("⚠️ El número de teléfono ya está en uso");
          return;
        } else if (e is FirebaseException && e.code == 'permission-denied') {
          // Si las reglas han bloqueado por intento de colisión (sin lecturas)
          _showError("⚠️ Alguno de los datos ya está en uso");
          return;
        } else {
          debugPrint("❌ Error en transacción de registro: $e");
          _showError("❌ Error al crear la cuenta.");
          return;
        }
      }

      debugPrint("✅ Usuario creado con UID: ${_maskUid(uid)} | Email: ${_maskEmail(email)}");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Cuenta creada con éxito")),
        );
        Navigator.pop(context); // volver al login
      }
    } on FirebaseAuthException catch (e) {
      _showError("❌ Error Auth: ${_firebaseErrorMessage(e.code)}");
    } catch (e) {
      debugPrint("❌ Error inesperado creando cuenta: $e");
      _showError("❌ Error al crear la cuenta.");
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String msg) {
    if (mounted) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
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
                  validator: (value) => value!.isEmpty ? "Introduce un correo" : null,
                ),
                const SizedBox(height: 16),

                // USERNAME
                _buildTextField(
                  controller: _usernameController,
                  label: "Nombre de usuario",
                  icon: Icons.person,
                  validator: (value) => value!.isEmpty ? "Introduce un nombre de usuario" : null,
                ),
                const SizedBox(height: 16),

                // CONTRASEÑA
                _buildTextField(
                  controller: _passwordController,
                  label: "Contraseña",
                  icon: Icons.lock,
                  obscure: true,
                  validator: (value) => value!.length < 6 ? "Mínimo 6 caracteres" : null,
                ),
                const SizedBox(height: 16),

                // CONFIRMAR CONTRASEÑA
                _buildTextField(
                  controller: _confirmPasswordController,
                  label: "Repetir contraseña",
                  icon: Icons.lock_outline,
                  obscure: true,
                  validator: (value) => value != _passwordController.text ? "No coinciden" : null,
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
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: _register,
                          child: const Text(
                            "Crear cuenta",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
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

  // ----------------- Sanitización y helpers extra -----------------

  static String _sanitizeEmail(String input) {
    final trimmed = input.trim().toLowerCase();
    final regex = RegExp(r'^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$');
    return regex.hasMatch(trimmed) ? trimmed : "";
  }

  static String _sanitizeUsername(String input) {
    final trimmed = input.trim();
    // 3-30 caracteres, letras (incluye acentos y ñ), números, espacios, guion y guion bajo
    final regex = RegExp(r'^[a-zA-Z0-9áéíóúüñÁÉÍÓÚÜÑ\s\-_]{3,30}$');
    return regex.hasMatch(trimmed) ? trimmed : "";
  }

  static String _usernameKey(String username) {
    // Unicidad case-insensitive: minúsculas + trim + colapsar espacios
    final lower = username.toLowerCase().trim();
    return lower.replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _sanitizePhone(String input) {
    final trimmed = input.trim();
    final regex = RegExp(r'^[0-9]{6,15}$');
    return regex.hasMatch(trimmed) ? trimmed : "";
  }

  static String _sanitizeCountryCode(String input) {
    final trimmed = input.trim();
    final regex = RegExp(r'^\+[0-9]{1,3}$');
    return regex.hasMatch(trimmed) ? trimmed : "";
  }

  static String _firebaseErrorMessage(String code) {
    switch (code) {
      case "email-already-in-use":
        return "Este email ya está en uso.";
      case "invalid-email":
        return "El email no es válido.";
      case "weak-password":
        return "La contraseña es demasiado débil.";
      default:
        return "Error desconocido al crear la cuenta.";
    }
  }

  static String _maskUid(String uid) {
    if (uid.length <= 6) return uid;
    return "${uid.substring(0, 3)}***${uid.substring(uid.length - 3)}";
  }

  static String _maskEmail(String email) {
    final parts = email.split("@");
    if (parts.length != 2) return email;
    final user = parts[0];
    final domain = parts[1];
    if (user.length <= 2) return "***@$domain";
    return "${user.substring(0, 2)}***@$domain";
  }
}
