import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreateAccPage extends StatefulWidget {
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

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
    });

    try {
      // 1️⃣ Comprobar si username ya existe
      final existing = await FirebaseFirestore.instance
          .collection('users')
          .where('username', isEqualTo: _usernameController.text.trim())
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("⚠️ El nombre de usuario ya está en uso")),
        );
        return;
      }

      // 2️⃣ Crear cuenta en Firebase Auth
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      User? user = userCredential.user;
      if (user != null) {
        // 3️⃣ Guardar datos en Firestore con docId = uid
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'email': _emailController.text.trim(),
          'username': _usernameController.text.trim(),
          'phone': '$_selectedCountryCode${_phoneController.text.trim()}',
          'role': 'user',
          'createdAt': FieldValue.serverTimestamp(),
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("✅ Cuenta creada con éxito")),
        );

        Navigator.pop(context); // volver al login o main
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error: ${e.message}")),
      );
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ Error inesperado: $e")),
      );
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
      appBar: AppBar(title: Text("Crear Cuenta")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // EMAIL
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(labelText: "Correo electrónico"),
                validator: (value) =>
                    value!.isEmpty ? "Introduce un correo" : null,
              ),
              SizedBox(height: 16),

              // USERNAME
              TextFormField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: "Nombre de usuario"),
                validator: (value) =>
                    value!.isEmpty ? "Introduce un nombre de usuario" : null,
              ),
              SizedBox(height: 16),

              // CONTRASEÑA
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: InputDecoration(labelText: "Contraseña"),
                validator: (value) =>
                    value!.length < 6 ? "Mínimo 6 caracteres" : null,
              ),
              SizedBox(height: 16),

              // CONFIRMAR CONTRASEÑA
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: InputDecoration(labelText: "Repetir Contraseña"),
                validator: (value) =>
                    value != _passwordController.text ? "No coinciden" : null,
              ),
              SizedBox(height: 16),

              // TELÉFONO
              Row(
                children: [
                  DropdownButton<String>(
                    value: _selectedCountryCode,
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
                  SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _phoneController,
                      decoration: InputDecoration(labelText: "Número de teléfono"),
                      keyboardType: TextInputType.phone,
                      validator: _validatePhone,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 24),

              // BOTÓN CREAR CUENTA
              _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : ElevatedButton(
                      onPressed: _register,
                      child: Text("Crear Cuenta"),
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
