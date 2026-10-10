import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'app/production_app.dart';
import 'app/flutter_binding.dart';
export 'app/app.dart' show ShioriApp;

void main() {
  ShioriWidgetsFlutterBinding();
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks([
      'WHATWG Encoding indexes',
    ], await rootBundle.loadString('assets/licenses/whatwg-encoding.txt'));
  });
  runApp(const ProductionApp());
}
