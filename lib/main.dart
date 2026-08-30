import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'services/api.dart';
import 'theme.dart';

void main() {
  runApp(const DzairApp());
}

class DzairApp extends StatelessWidget {
  const DzairApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dzair Shipping',
      debugShowCheckedModeBanner: false,
      theme: dzairTheme(),
      locale: const Locale('fr'),
      supportedLocales: const [Locale('fr')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _Demarrage(),
    );
  }
}

class _Demarrage extends StatefulWidget {
  const _Demarrage();

  @override
  State<_Demarrage> createState() => _DemarrageState();
}

class _DemarrageState extends State<_Demarrage> {
  bool? _connecte;

  @override
  void initState() {
    super.initState();
    Api.restaurerSession().then((ok) {
      if (mounted) setState(() => _connecte = ok);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_connecte == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: DzColors.lime)),
      );
    }
    return _connecte! ? const Shell() : const LoginScreen();
  }
}
