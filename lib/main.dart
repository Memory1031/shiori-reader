import 'package:flutter/material.dart';
import 'app/production_app.dart';
export 'app/app.dart' show ShioriApp;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProductionApp());
}
