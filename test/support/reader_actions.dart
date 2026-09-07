import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/features/reader/reader_screen.dart';
import 'package:shiori/features/reader/settings_panel.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';

Future<void> openReaderSettings(WidgetTester tester) async {
  final l = AppLocalizations.of(tester.element(find.byType(ReaderContentView)));
  if (find.text(l.readerGotIt).evaluate().isNotEmpty) {
    await tester.ensureVisible(find.text(l.readerGotIt));
    await tester.tap(find.text(l.readerGotIt));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }
  if (find.byTooltip(l.showReaderControls).evaluate().isNotEmpty) {
    await tester.tap(find.byTooltip(l.showReaderControls));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }
  await tester.tap(find.byTooltip(l.readerSettings));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> chooseReaderMode(WidgetTester tester, String label) async {
  await openReaderSettings(tester);
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
  Navigator.of(tester.element(find.byType(ReaderSettingsPanel))).pop();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}
