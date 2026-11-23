import 'package:flutter/material.dart';

import 'state/app_controller.dart';
import 'ui/home_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CuacaApp());
}

class CuacaApp extends StatefulWidget {
  const CuacaApp({super.key});

  @override
  State<CuacaApp> createState() => _CuacaAppState();
}

class _CuacaAppState extends State<CuacaApp> {
  final AppController _controller = AppController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF1E6FD9),
        brightness: brightness,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cuaca Kelurahan',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      themeMode: ThemeMode.system,
      home: HomePage(controller: _controller),
    );
  }
}
