import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'create_acc_page.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  // Backoff simple en cliente para frenar fuerza bruta
  int _attempts = 0;
  DateTime? _lockedUntil;
  Timer? _lockTimer;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _lockTimer?.cancel();
    super.dispose();
  }

  // --------- Helpers de validación / normalización ----------
  String _normalizeEmail(String input) => input.trim().toLowerCase();

  String? _validateEmail(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return "Introduce tu correo";
    final regex = RegExp(r'^[a-z0-9._%+\-]+@[a-z0-9.\-]+\.[a-z]{2,}$', caseSensitive: false);
    if (!regex.hasMatch(v)) return "Formato de correo inválido";
    return null;
  }

  String? _validatePassword(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return "Introduce tu contraseña";
    if (v.length < 6) return "Mínimo 6 caracteres";
    return null;
  }

  // Backoff: 0, 10, 30, 60, 120, 300s (máx)
  int _nextBackoffSeconds() {
    const steps = [0, 10, 30, 60, 120, 300];
    final idx = _attempts.clamp(0, steps.length - 1);
    return steps[idx];
  }

  int _remainingLockSeconds() {
    if (_lockedUntil == null) return 0;
    final diff = _lockedUntil!.difference(DateTime.now()).inSeconds;
    return diff > 0 ? diff : 0;
  }

  void _startLockIfNeeded() {
    final sec = _nextBackoffSeconds();
    if (sec <= 0) return;
    _lockedUntil = DateTime.now().add(Duration(seconds: sec));
    _lockTimer?.cancel();
    _lockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_remainingLockSeconds() == 0) {
        _lockTimer?.cancel();
        setState(() => _lockedUntil = null);
      } else {
        setState(() {}); // actualizar contador visible
      }
    });
  }

  Future<void> _login() async {
    // Bloqueado por backoff
    final left = _remainingLockSeconds();
    if (left > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Espera $left s para volver a intentarlo")),
      );
      return;
    }

    // Validación de formulario
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final email = _normalizeEmail(_emailController.text);
    final password = _passwordController.text.trim();

    setState(() => _isLoading = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      // AuthGate se encargará de redirigir
      _attempts = 0; // éxito: resetea intentos
    } on FirebaseAuthException catch (e) {
      _attempts++;
      _startLockIfNeeded();

      String message = "❌ Error al iniciar sesión";
      switch (e.code) {
        case 'user-not-found':
          // Mensaje genérico para no revelar si el correo existe
          message = "Credenciales inválidas";
          break;
        case 'wrong-password':
          message = "Credenciales inválidas";
          break;
        case 'invalid-email':
          message = "Formato de correo inválido";
          break;
        case 'user-disabled':
          message = "Esta cuenta está deshabilitada";
          break;
        case 'too-many-requests':
          message = "Demasiados intentos, inténtalo más tarde";
          break;
        case 'network-request-failed':
          message = "Sin conexión. Revisa tu red";
          break;
        case 'requires-recent-login':
          message = "Requiere reautenticación";
          break;
        case 'multi-factor-auth-required':
          message = "Se requiere verificación adicional (MFA)";
          break;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (_) {
      _attempts++;
      _startLockIfNeeded();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("❌ Ha ocurrido un error inesperado")),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _remainingLockSeconds();
    final isDisabled = _isLoading || locked > 0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.disabled,
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
                  _buildTextFormField(
                    controller: _emailController,
                    label: "Correo electrónico",
                    icon: Icons.email,
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.email],
                  ),
                  const SizedBox(height: 16),

                  // PASSWORD con toggle
                  _buildTextFormField(
                    controller: _passwordController,
                    label: "Contraseña",
                    icon: Icons.lock,
                    obscure: _obscurePassword,
                    validator: _validatePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
                    autofillHints: const [AutofillHints.password],
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white70,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  const SizedBox(height: 30),

                  // BOTÓN LOGIN
                  _isLoading
                      ? const CircularProgressIndicator(color: Colors.green)
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDisabled ? Colors.green.withOpacity(0.5) : Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            onPressed: isDisabled ? null : _login,
                            child: Text(
                              locked > 0
                                  ? "Reintentar en ${locked}s"
                                  : "Iniciar sesión",
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
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
                      onPressed: isDisabled
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const CreateAccPage()),
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
        ),
      ),
    );
  }

  /// 🔹 Helper para campos de texto (FormField) con estilo dark
  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    String? Function(String?)? validator,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    Iterable<String>? autofillHints,
    void Function(String)? onFieldSubmitted,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      autofillHints: autofillHints,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: Colors.green),
        suffixIcon: suffixIcon,
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
