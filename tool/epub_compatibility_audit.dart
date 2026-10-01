import 'dart:io';
import 'epub_audit/cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await auditMain(args);
}
