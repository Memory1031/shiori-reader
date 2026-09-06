import 'package:flutter/material.dart';

void main() {
  runApp(const ShioriApp());
}

class ShioriApp extends StatelessWidget {
  const ShioriApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Shiori',
      home: Scaffold(
        body: SafeArea(child: Center(child: Text('Shiori'))),
      ),
    );
  }
}
