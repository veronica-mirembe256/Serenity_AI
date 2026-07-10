import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:serenity/core/theme/app_theme.dart';
import 'package:serenity/state/providers.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});
  @override ConsumerState<LoginPage> createState() => _State();
}
class _State extends ConsumerState<LoginPage> {
  final _form  = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _pass  = TextEditingController();
  bool _obs    = true;

  @override void dispose() { _email.dispose(); _pass.dispose(); super.dispose(); }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    final ok = await ref.read(authProvider.notifier).login(_email.text.trim(), _pass.text);
    if (ok && mounted) context.go('/dashboard');
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final t    = Theme.of(context).textTheme;
    final w    = MediaQuery.of(context).size.width;
    final narrow = w < 780;

    Widget form = Container(
      color: Colors.white,
      child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Padding(padding: const EdgeInsets.all(48),
          child: Form(key: _form, child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(width: 32, height: 32,
                    decoration: BoxDecoration(color: AppColors.sage, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.eco_rounded, color: Colors.white, size: 18)),
                const SizedBox(width: 10),
                Text('Serenity', style: GoogleFonts.fraunces(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.ink)),
              ]),
              const SizedBox(height: 40),
              Text('Welcome back', style: t.displaySmall),
              const SizedBox(height: 4),
              Text('Sign in to your recovery dashboard.',
                  style: t.bodyMedium?.copyWith(color: AppColors.inkMid)),
              const SizedBox(height: 32),
              TextFormField(controller: _email, keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Email address'),
                validator: (v) => v == null || !v.contains('@') ? 'Enter a valid email' : null),
              const SizedBox(height: 12),
              TextFormField(controller: _pass, obscureText: _obs,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _login(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(_obs ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 18, color: AppColors.inkLt),
                    onPressed: () => setState(() => _obs = !_obs)),
                ),
                validator: (v) => v == null || v.length < 6 ? 'Too short' : null),
              if (auth.error != null) ...[
                const SizedBox(height: 10),
                Text(auth.error!, style: t.bodySmall?.copyWith(color: AppColors.rose)),
              ],
              const SizedBox(height: 24),
              SizedBox(width: double.infinity, height: 46,
                child: ElevatedButton(
                  onPressed: auth.isLoading ? null : _login,
                  child: auth.isLoading
                      ? const SizedBox(width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Sign In'),
                ),
              ),
              const SizedBox(height: 16),
              Center(child: GestureDetector(
                onTap: () => context.go('/register'),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: "Don't have an account? ",
                      style: t.bodySmall?.copyWith(color: AppColors.inkMid)),
                  TextSpan(text: 'Create one',
                      style: t.bodySmall?.copyWith(color: AppColors.sage, fontWeight: FontWeight.w600)),
                ])),
              )),
            ],
          )),
        ),
      )),
    );

    if (narrow) return Scaffold(body: form);

    return Scaffold(
      body: Row(children: [
        Expanded(flex: 5, child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [AppColors.sidebar, Color(0xFF2A4A2C)],
                begin: Alignment.topLeft, end: Alignment.bottomRight)),
          padding: const EdgeInsets.all(60),
          child: Column(mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Your recovery,\nyour way.', style: GoogleFonts.fraunces(
                fontSize: 48, fontWeight: FontWeight.w700, color: Colors.white,
                height: 1.15, letterSpacing: -1.5)),
            const SizedBox(height: 22),
            Text('An AI-powered companion for daily reflection,\npattern awareness, and sustainable recovery.',
                style: const TextStyle(color: Colors.white60, fontSize: 17, height: 1.65)),
            const SizedBox(height: 48),
            ...[
              ('🌿', 'AI-powered journaling & insights'),
              ('📊', 'Mood tracking and pattern detection'),
              ('🔥', 'Streak tracking and milestone rewards'),
              ('💙', 'Crisis-safe support whenever you need it'),
            ].map((f) => Padding(padding: const EdgeInsets.only(bottom: 14),
              child: Row(children: [
                Text(f.$1, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 14),
                Text(f.$2, style: const TextStyle(color: Colors.white70, fontSize: 15)),
              ]))),
          ]),
        )),
        Expanded(flex: 4, child: form),
      ]),
    );
  }
}
