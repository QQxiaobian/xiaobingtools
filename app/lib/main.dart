import 'package:flutter/material.dart';

import 'modules/map/map_page.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const XianluToolboxApp());
}

class XianluToolboxApp extends StatelessWidget {
  const XianluToolboxApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '线路工具箱',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1565C0),
        ),
      ),
      home: const MapPage(),
    );
  }
}
