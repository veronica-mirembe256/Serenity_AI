import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:serenity/core/theme/app_theme.dart';
import 'package:serenity/shared/widgets/web_widgets.dart';
import 'package:serenity/state/providers.dart';

class RegisterPage extends ConsumerStatefulWidget {
  const RegisterPage({super.key});
  @override
  ConsumerState<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends ConsumerState<RegisterPage> {
  final _formKey              = GlobalKey<FormState>();
  final _nameCtrl             = TextEditingController();
  final _emailCtrl            = TextEditingController();
  final _passCtrl             = TextEditingController();
  final _emergencyEmailCtrl   = TextEditingController();
  final _therapistEmailCtrl   = TextEditingController(); // NEW
  bool _obscure = true;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _emergencyEmailCtrl.dispose();
    _therapistEmailCtrl.dispose();
    super.dispose();
  }

  /// Returns only the last word of the full name.
  /// "Maria Nakato" → "Nakato",  "John" → "John"
  String _lastName(String fullName) {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.last;
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    final success = await ref.read(authProvider.notifier).register(
      email:                 _emailCtrl.text.trim(),
      password:              _passCtrl.text,
      displayName:           _lastName(_nameCtrl.text),  // last name only
      emergencyContactEmail: _emergencyEmailCtrl.text.trim().isEmpty
          ? null : _emergencyEmailCtrl.text.trim(),
      therapistEmail:        _therapistEmailCtrl.text.trim().isEmpty  // NEW
          ? null : _therapistEmailCtrl.text.trim(),
    );

    if (success && mounted) context.go('/onboarding');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authProvider);
    final t         = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Create Account', style: t.headlineMedium),
                  const SizedBox(height: 8),
                  Text('Start your recovery journey today',
                      style: t.bodyMedium?.copyWith(color: AppColors.inkLt)),
                  const SizedBox(height: 32),

                  // Full Name
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) =>
                        v == null || v.isEmpty ? 'Enter your name' : null,
                  ),
                  const SizedBox(height: 16),

                  // Email
                  TextFormField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined),
                    ),
                    validator: (v) =>
                        v == null || !v.contains('@') ? 'Enter a valid email' : null,
                  ),
                  const SizedBox(height: 16),

                  // Emergency Contact Email
                  TextFormField(
                    controller: _emergencyEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Emergency Contact Email (Optional)',
                      hintText: 'A trusted person to alert in crisis',
                      prefixIcon: Icon(Icons.emergency_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Therapist Email — NEW
                  TextFormField(
                    controller: _therapistEmailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'Therapist / Support Email (Optional)',
                      hintText: 'Your therapist or counsellor',
                      prefixIcon: Icon(Icons.medical_services_outlined),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Password
                  TextFormField(
                    controller: _passCtrl,
                    obscureText: _obscure,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure
                            ? Icons.visibility_off : Icons.visibility),
                        onPressed: () =>
                            setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        v == null || v.length < 6 ? 'Min 6 characters' : null,
                  ),

                  if (authState.error != null) ...[
                    const SizedBox(height: 16),
                    Text(authState.error!,
                        style: const TextStyle(
                            color: Colors.red, fontSize: 13)),
                  ],

                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: authState.isLoading ? null : _handleRegister,
                      child: authState.isLoading
                          ? const CircularProgressIndicator(
                              color: Colors.white)
                          : const Text('Create Account'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Already have an account? Login'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}