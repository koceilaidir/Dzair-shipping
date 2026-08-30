import 'package:flutter/material.dart';
import '../services/api.dart';
import '../theme.dart';
import '../widgets/dzair_logo.dart';
import 'shell.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  bool _souvenir = true;
  String? _error;

  Future<void> _login() async {
    final email = _email.text.trim();
    final password = _password.text;
    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = 'Entre ton email et ton mot de passe.');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      await Api.login(email, password, souvenir: _souvenir);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const Shell()),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.message; });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Serveur injoignable — vérifie ta connexion.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: DzairLogo(size: 104)),
                const SizedBox(height: 18),
                const Center(child: DzairWordmark(fontSize: 30)),
                const SizedBox(height: 40),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  onSubmitted: (_) => _login(),
                  decoration: const InputDecoration(labelText: 'Mot de passe'),
                ),
                const SizedBox(height: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _souvenir = !_souvenir),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(children: [
                      Container(
                        width: 19, height: 19, alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: _souvenir ? DzColors.lime : DzColors.card2,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: _souvenir
                            ? const Icon(Icons.check_rounded,
                                size: 14, color: DzColors.inkOnLime)
                            : null,
                      ),
                      const SizedBox(width: 9),
                      const Text('Se souvenir de moi',
                          style: TextStyle(color: DzColors.txt2, fontSize: 13)),
                    ]),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: DzColors.red, fontSize: 12.5)),
                ],
                const SizedBox(height: 14),
                FilledButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const SizedBox(
                          height: 18, width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Se connecter'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
