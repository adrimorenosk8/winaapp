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
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;

  // Backoff simple en cliente para frenar fuerza bruta
  int _attempts = 0;
  DateTime? _lockedUntil;
  Timer? _lockTimer;

  // ---------- Estilo coherente con la app ----------
  Color get _bg => const Color(0xFF121212);
  Color get _card => const Color(0xFF1E1E1E);
  Color get _accent => Colors.greenAccent[400]!;
  Color get _muted => Colors.white70;

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
    if (v.length > 254) return "Correo demasiado largo";
    return null;
  }

  String? _validatePassword(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return "Introduce tu contraseña";
    if (v.length < 6) return "Mínimo 6 caracteres";
    if (v.length > 128) return "Contraseña demasiado larga";
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
        case 'wrong-password':
        case 'invalid-credential': // alias moderno
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
        case 'operation-not-allowed':
          message = "Método de acceso no habilitado";
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

  Future<void> _resetPassword() async {
    final email = _normalizeEmail(_emailController.text);
    if (_validateEmail(email) != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Introduce un correo válido primero")),
      );
      return;
    }
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Te enviamos un correo para restablecer la contraseña.")),
      );
    } on FirebaseAuthException catch (e) {
      String msg = "No se pudo enviar el correo de restablecimiento.";
      if (e.code == 'user-not-found') {
        // Mantener mensaje genérico para no filtrar existencia de cuentas
        msg = "Si el correo es válido, recibirás un mensaje con instrucciones.";
      } else if (e.code == 'invalid-email') {
        msg = "Formato de correo inválido.";
      } else if (e.code == 'network-request-failed') {
        msg = "Sin conexión. Revisa tu red.";
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Ocurrió un error enviando el correo.")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locked = _remainingLockSeconds();
    final isDisabled = _isLoading || locked > 0;

    return Scaffold(
      backgroundColor: _bg,
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
                  Image.asset("assets/images/logo.png", height: 120),
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
                    maxLength: 254,
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
                    maxLength: 128,
                  ),
                  const SizedBox(height: 12),

                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: isDisabled ? null : _resetPassword,
                      child: Text("¿Olvidaste tu contraseña?", style: TextStyle(color: _accent)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // BOTÓN LOGIN
                  _isLoading
                      ? const CircularProgressIndicator(color: Colors.greenAccent)
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDisabled ? _accent.withOpacity(0.5) : _accent,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            onPressed: isDisabled ? null : _login,
                            child: Text(
                              locked > 0 ? "Reintentar en ${locked}s" : "Iniciar sesión",
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                          ),
                        ),
                  const SizedBox(height: 16),

                  // BOTÓN CREAR CUENTA
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: _accent),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: isDisabled
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => const CreateAccPage()),
                              );
                            },
                      child: Text(
                        "Crear cuenta",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _accent),
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
    int? maxLength,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      autofillHints: autofillHints,
      autocorrect: false,
      enableSuggestions: !obscure,
      maxLength: maxLength,
      buildCounter: (_, {required int currentLength, required bool isFocused, int? maxLength}) => null,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70),
        prefixIcon: Icon(icon, color: _accent),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: _card,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _accent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: _accent, width: 2),
        ),
      ),
    );
  }
}
