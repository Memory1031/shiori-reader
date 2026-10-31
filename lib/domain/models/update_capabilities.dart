import 'value_model.dart';

enum UpdateMethod { inApp, downloadOnly, checkOnly, external, unavailable }

enum ExternalUpdateTarget { testFlight, appStore, originalSource }

/// The update operations and optional destination outside the application.
final class UpdateCapabilities extends ValueModel {
  const UpdateCapabilities({required this.method, this.externalTarget});

  final UpdateMethod method;
  final ExternalUpdateTarget? externalTarget;

  bool get canCheck => switch (method) {
    UpdateMethod.inApp ||
    UpdateMethod.downloadOnly ||
    UpdateMethod.checkOnly => true,
    UpdateMethod.external || UpdateMethod.unavailable => false,
  };
  bool get canDownload =>
      method == UpdateMethod.inApp || method == UpdateMethod.downloadOnly;
  bool get canInstall => method == UpdateMethod.inApp;
  bool get canOpenExternal => externalTarget != null;

  @override
  List<Object?> get values => [method, externalTarget];
}
