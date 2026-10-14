import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/l10n/generated/app_localizations_en.dart';
import 'package:shiori/l10n/generated/app_localizations_zh.dart';
import 'package:shiori/shared/widgets/state_views.dart';
import 'failure_cooldown_test.dart' show render, shot;

void main() {
  for (final l in [AppLocalizationsZh(), AppLocalizationsEn()]) {
    test('failure messages preserve kind and context in ${l.localeName}', () {
      final messages = {
        FailureKind.network: l.connectionFailureMessage,
        FailureKind.timeout: l.connectionFailureMessage,
        FailureKind.sourceUnavailable: l.sourceUnavailableMessage,
        FailureKind.session: l.sessionFailureMessage,
        FailureKind.accessRestricted: l.accessRestrictedMessage,
        FailureKind.parse: l.parseFailureMessage,
        FailureKind.notFound: l.notFoundMessage,
        FailureKind.rateLimited: l.rateLimitedMessage,
        FailureKind.database: l.databaseFailureMessage,
        FailureKind.cache: l.cacheFailureMessage,
        FailureKind.unsupported: l.unsupportedMessage,
        FailureKind.tooLarge: l.tooLargeMessage,
        FailureKind.cancelled: '',
      };
      for (final entry in messages.entries) {
        expect(
          failureMessage(
            l,
            AppFailure(kind: entry.key, operation: Operation.chapter),
          ),
          entry.value,
        );
      }
      expect(
        failureMessage(
          l,
          AppFailure(
            kind: FailureKind.unsupported,
            operation: Operation.chapter,
            context: FailureContext.unrecognizedSourceResponse,
          ),
        ),
        l.unrecognizedSourceResponseMessage,
      );
      expect(
        failureMessage(
          l,
          AppFailure(
            kind: FailureKind.cache,
            operation: Operation.chapter,
            context: FailureContext.cacheMiss,
          ),
        ),
        l.cacheMissMessage,
      );
      expect(
        failureMessage(
          l,
          AppFailure(
            kind: FailureKind.parse,
            operation: Operation.chapter,
            context: FailureContext.unrecognizedSourceResponse,
          ),
        ),
        l.parseFailureMessage,
      );
    });
  }

  for (final (lang, width, platform) in [
    ('en', 320.0, TargetPlatform.android),
    ('zh', 1000.0, TargetPlatform.windows),
  ]) {
    testWidgets(
      'source failure never offers retry in $lang at $width',
      (tester) async {
        var retries = 0;
        final capture = GlobalKey();
        for (final context in [
          FailureContext.unrecognizedSourceResponse,
          FailureContext.none,
        ]) {
          final failure = AppFailure(
            kind: FailureKind.unsupported,
            operation: Operation.chapter,
            context: context,
          );
          await render(
            tester,
            FailureView(failure: failure, onRetry: () => retries++),
            capture: capture,
            lang: lang,
            width: width,
          );
          await tester.pumpAndSettle();
          expect(
            find.text(
              context == FailureContext.none
                  ? (lang == 'en' ? AppLocalizationsEn() : AppLocalizationsZh())
                        .unsupportedMessage
                  : (lang == 'en' ? AppLocalizationsEn() : AppLocalizationsZh())
                        .unrecognizedSourceResponseMessage,
            ),
            findsOneWidget,
          );
          expect(find.byType(FilledButton), findsNothing);
          expect(failure.retryPolicy, RetryPolicy.never);
          await tester.pump(const Duration(minutes: 1));
          expect(retries, 0);
          expect(tester.takeException(), isNull);
          if (context == FailureContext.unrecognizedSourceResponse) {
            await shot(
              tester,
              capture,
              'source-response-$lang-${width.toInt()}',
            );
          }
        }
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }
}
