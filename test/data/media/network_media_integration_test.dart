import 'package:flutter_test/flutter_test.dart';
import '../../support/network_media_probe.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'Dio + scheduler + SourceMedia + repository + codec compose without network',
    () async {
      final bytes = await verifyNetworkMedia();
      expect(bytes, isNotEmpty);
    },
  );
}
