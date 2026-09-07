import 'package:flutter/widgets.dart';

import 'dev/ui/dev_app.dart';

void main() {
  runApp(
    createDevApp(scenarioId: const String.fromEnvironment('SHIORI_SCENARIO')),
  );
}
