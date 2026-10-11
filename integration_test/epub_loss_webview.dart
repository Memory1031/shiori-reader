// Explicit private WebView host. No normal app entry, user library, online
// source, plugin fault switches or persisted reading progress are involved.
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:shiori/domain/contracts/local_content_links.dart';
import 'package:shiori/shared/epub_link_address.dart';
import 'package:shiori/app/app.dart';
import 'package:shiori/app/routes.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/features/reader/epub_layout_page.dart';
import 'package:shiori/features/reader/epub_page_inspection.dart';
import 'package:shiori/features/reader/epub_webview_host.dart';
import 'package:shiori/features/reader/reader_theme.dart';
import '../tool/epub_audit/browser_probe.dart';
import '../tool/epub_audit/loss_model.dart';
import '../tool/epub_audit/plan.dart';
import '../tool/epub_audit/replay.dart';
import '../tool/epub_audit/report.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (args.length != 1) {
    exit(64);
  }
  final request = await boundedJson(File(args.single), maxBytes: 1024 * 1024);
  final snapshot = await readBundle(
    request['bundle'] as String,
    request['allowRoot'] as String,
  );
  final target = VerificationTarget.fromJson(request['target'] as Json);
  final config = ProbeConfiguration.fromJson(request['configuration'] as Json);
  final key = target.chapterKey == null
      ? null
      : ChapterKey.fromJson(target.chapterKey!);
  final html = snapshot.parser.presentations[key?.chapterId];
  final timeout = Timer(
    Duration(seconds: target.timeoutSeconds),
    () => exit(124),
  );
  var completed = false;
  final pane = GlobalKey();
  final activations = <LocalContentLink>[];
  Future<void> finish(Json result) async {
    if (completed) return;
    completed = true;
    timeout.cancel();
    await atomicJson(
      request['result'] as String,
      result,
      maxBytes: target.maxEvidenceBytes,
    );
    runApp(const SizedBox());
    await Future<void>.delayed(const Duration(milliseconds: 500));
    exit(0);
  }

  if (html == null) {
    await finish({
      'complete': false,
      'reason': 'no_production_presentation',
      'observedPath': 'not_run',
      'layers': {},
      'assertions': {},
    });
    return;
  }
  runApp(
    ShioriApp(
      locale: Locale(config.language),
      routes: AppRoutes(
        home: (_) => EpubWebViewHost(
          userDataDirectory: Directory(
            '${request['privateRoot']}/webview-profile',
          ),
          child: Theme(
            data: readerTheme(
              ReaderSettings(
                themeMode: config.theme == 'dark'
                    ? ReaderThemeMode.dark
                    : ReaderThemeMode.light,
              ),
              Brightness.light,
            ),
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: config.width.toDouble(),
                  height: config.height.toDouble(),
                  child: EpubLayoutPage(
                    key: pane,
                    html: html,
                    links: snapshot.parsed.content.links
                        .where((l) => l.source == key)
                        .toList(),
                    onLink: activations.add,
                    onCenterTap: () {},
                    onReady: () {},
                    onFailed: () => unawaited(
                      finish({
                        'complete': false,
                        'reason': 'production_host_load_failure',
                        'observedPath': 'not_run',
                        'providerDetail': 'Flutter_production_WebView_host',
                        'layers': {},
                        'assertions': {'nativeFallbackRequired': true},
                      }),
                    ),
                    onInspection: (EpubPageInspection inspection) async {
                      if (inspection.values['error'] != null) {
                        unawaited(
                          finish({
                            'complete': false,
                            'reason': 'host_measurement_unavailable',
                            'observedPath': 'presentation',
                            'layers': {},
                            'assertions': {},
                          }),
                        );
                        return;
                      }
                      final measurements = sanitizeBrowserMeasurement(
                        inspection.values,
                      );
                      final sourceScope = target.candidate.location.domPath;
                      measurements['targetVisible'] =
                          sourceScope == 'document' ||
                          (measurements['text'] as List).cast<Json>().any(
                            (t) =>
                                ((t['domPath'] as String) == sourceScope ||
                                    (t['domPath'] as String).startsWith(
                                      '$sourceScope/',
                                    )) &&
                                (t['boxes'] as List).isNotEmpty,
                          );
                      final hit = (inspection.values['links'] as List)
                          .cast<Json>()
                          .where(
                            (l) => epubLinkId(l['address'] as String?) != null,
                          )
                          .firstOrNull;
                      var clicked = false;
                      if (hit != null) {
                        final r = hit['rect'] as Json;
                        final local = Offset(
                          ((r['left'] as num) + (r['right'] as num)) / 2,
                          ((r['top'] as num) + (r['bottom'] as num)) / 2,
                        );
                        final render = pane.currentContext?.findRenderObject();
                        if (render is RenderBox &&
                            (Offset.zero & render.size).contains(local)) {
                          final point = render.localToGlobal(local);
                          GestureBinding.instance.handlePointerEvent(
                            PointerDownEvent(pointer: 37, position: point),
                          );
                          GestureBinding.instance.handlePointerEvent(
                            PointerUpEvent(pointer: 37, position: point),
                          );
                          await Future<void>.delayed(
                            const Duration(milliseconds: 500),
                          );
                          final expected = snapshot.parsed.content.links
                              .where(
                                (l) =>
                                    l.source == key &&
                                    l.presentationId ==
                                        epubLinkId(hit['address'] as String?),
                              )
                              .firstOrNull;
                          clicked =
                              expected != null &&
                              activations.length == 1 &&
                              activations.single == expected;
                          measurements['hostInput'] = {
                            'activations': activations.length,
                            'declaredId': epubLinkId(hit['address'] as String?),
                            'matched': clicked,
                            'method':
                                'Flutter_pointer_hit_test_and_production_host_route',
                          };
                        }
                      }
                      final failed =
                          (measurements['unreachableClippedRanges'] as int) >
                              0 ||
                          (measurements['lowContrastRanges'] as int) > 0;
                      final unknown =
                          measurements['truncated'] == true ||
                          (measurements['overlappingTextRanges'] as int) > 0 ||
                          (measurements['unknownBackgroundRanges'] as int) >
                              0 ||
                          measurements['targetVisible'] != true;
                      unawaited(
                        finish({
                          'complete': !unknown,
                          'reason': unknown
                              ? 'partial_or_ambiguous_geometry'
                              : 'executed',
                          'observedPath': 'presentation',
                          'providerDetail': Platform.isWindows
                              ? 'Flutter_WebView2'
                              : Platform.isIOS
                              ? 'Flutter_WKWebView'
                              : 'Flutter_Android_WebView',
                          'layers': {
                            for (final layer in EvidenceLayer.values)
                              wireName(
                                layer,
                              ): layer == EvidenceLayer.nativeWebView
                                  ? failed
                                        ? 'fail'
                                        : unknown
                                        ? 'unknown'
                                        : 'pass'
                                  : layer == EvidenceLayer.controlRouting &&
                                        clicked
                                  ? 'pass'
                                  : 'not_run',
                          },
                          'environmentDetail': {
                            'platform': Platform.operatingSystem,
                            'clientWidth': measurements['clientWidth'],
                            'clientHeight': measurements['clientHeight'],
                            'pathSelection':
                                'explicit_production_special_page_host',
                          },
                          'assertions': measurements,
                        }),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
