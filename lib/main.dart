import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
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
      home: const LoginScreen(),
    );
  }
}
