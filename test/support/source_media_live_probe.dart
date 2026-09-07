// Explicit live opt-in only. Run seed and restore in separate flutter processes.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/data/network/request_scheduler.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_source.dart';
import 'package:shiori/data/sources/lightnovel/lightnovel_identity.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/domain/models/models.dart';
import 'package:shiori/shared/app_logger.dart';
import 'package:shiori/shared/source_image.dart';

class Budget {
  Budget(this.maximum);
  final int maximum;
  int attempts = 0;
}

class Adapter implements HttpClientAdapter {
  Adapter(this.budget);
  final Budget budget;
  final delegate = IOHttpClientAdapter();
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) {
    if (++budget.attempts > budget.maximum) {
      throw StateError('Live budget exceeded');
    }
    return delegate.fetch(options, body, cancel);
  }

  @override
  void close({bool force = false}) => delegate.close(force: force);
}

T checked<T>(Result<T> result) {
  if (result case Success(:final value)) return value;
  final failure = (result as Failure<T>).failure;
  throw StateError(
    'SRC010_STOP_${failure.operation.name}_${failure.kind.name}',
  );
}

void main() {
  const enabled = bool.fromEnvironment('SRC010_LIVE');
  const phase = String.fromEnvironment('SRC010_PHASE');
  test(
    'SRC010 bounded cross-process media check',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = null;
      if (phase != 'seed' && phase != 'restore') {
        throw StateError('Explicit phase required');
      }
      final budget = Budget(phase == 'seed' ? 6 : 4);
      final scheduler = RequestScheduler(
        startInterval: const Duration(seconds: 1),
      );
      final source = LightNovelSource(
        scheduler: scheduler,
        logger: AppLogger(),
        adapter: Adapter(budget),
        mediaAdapterFactory: () => Adapter(budget),
      );
      final token = CancellationSource().token;
      final file = File('.tooling/evidence/src010-refs.json');
      try {
        List<MediaRef> refs;
        if (phase == 'seed') {
          final detail = checked(
            await source.getNovelDetail(
              lightNovelKey(31607),
              cancellation: token,
            ),
          );
          final content = checked(
            await source.getChapter(
              lightNovelChapterKey(lightNovelKey(31607), 309555),
              cancellation: token,
            ),
          );
          refs = [
            detail.summary.cover!,
            content.blocks.whereType<ImageBlock>().first.media,
          ];
        } else {
          refs = (jsonDecode(await file.readAsString()) as List)
              .map((r) => MediaRef.fromJson(r as Map<String, dynamic>))
              .toList();
        }
        for (var i = 0; i < refs.length; i++) {
          final body = checked(
            await source.openMedia(
              refs[i],
              maxBytes: 20 * 1024 * 1024,
              cancellation: token,
            ),
          );
          try {
            final bytes = BytesBuilder(copy: false);
            await for (final chunk in body.chunks) {
              bytes.add(checked(chunk));
            }
            final value = bytes.takeBytes();
            final decoded = await decodeSourceImage(
              MemoryMedia(bytes: value, info: body.info),
              1024,
            );
            // Statistics only; never write bytes/URLs/body or exception details.
            stdout.writeln(
              'SRC010_METRIC phase=$phase item=$i bytes=${value.length} width=${decoded.intrinsicSize.width.toInt()} height=${decoded.intrinsicSize.height.toInt()}',
            );
            decoded.image.dispose();
          } finally {
            await body.close();
          }
        }
        if (phase == 'seed') {
          await file.writeAsString(
            jsonEncode(refs.map((r) => r.toJson()).toList()),
          );
        }
        stdout.writeln('SRC010_PASS phase=$phase attempts=${budget.attempts}');
      } finally {
        source.close();
        scheduler.close();
      }
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
