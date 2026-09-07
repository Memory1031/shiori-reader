import 'package:flutter/widgets.dart';
import 'fixture_codec_check.dart';

/// Run with flutter run --target test/support/fixture_android_decode.dart.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final count = await decodeFixtureImages();
    debugPrint('FIXTURE_CODEC_PASS count=$count');
  } catch (error) {
    debugPrint('FIXTURE_CODEC_FAIL $error');
    rethrow;
  }
}
