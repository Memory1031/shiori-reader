import 'package:flutter/widgets.dart';
import '../domain/contracts/image_export.dart';

/// Explicit composition injection, available above the Reader navigator.
class ImageExportScope extends InheritedWidget {
  const ImageExportScope({
    super.key,
    required this.exporter,
    required super.child,
  });
  final ImageExporter exporter;
  static ImageExporter? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ImageExportScope>()?.exporter;
  @override
  bool updateShouldNotify(ImageExportScope oldWidget) =>
      exporter != oldWidget.exporter;
}
