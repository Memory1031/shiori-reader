import 'package:flutter/material.dart';

import '../../shared/widgets/shiori_sheet.dart';

export '../../shared/widgets/shiori_sheet.dart' show ShioriSheetSize;

typedef ReaderSheetSize = ShioriSheetSize;

/// Reader sheets use the app-wide sheet policy.
Future<T?> showReaderSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  ShioriSheetSize size = ShioriSheetSize.fit,
}) => showShioriSheet<T>(context, builder: builder, size: size);
