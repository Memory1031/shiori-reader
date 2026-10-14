import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiori/domain/contracts/contracts.dart';
import 'package:shiori/l10n/generated/app_localizations.dart';
import 'package:shiori/shared/widgets/state_views.dart';
import 'failure_cooldown_test.dart' show render, shot;

void main() {
  for (final lang in ['zh', 'en']) {
    for (final width in [320.0, 1000.0]) {
      testWidgets(
        'unknown source response and unsupported remain distinct in $lang at $width',
        (tester) async {
          var retries = 0;
          final failure = AppFailure(
            kind: FailureKind.unsupported,
            operation: Operation.chapter,
            context: FailureContext.unrecognizedSourceResponse,
          );
          final capture = GlobalKey();
          await render(
            tester,
            FailureView(failure: failure, onRetry: () => retries++),
            capture: capture,
            lang: lang,
            width: width,
          );
          await tester.pumpAndSettle();
          final l = AppLocalizations.of(
            tester.element(find.byType(FailureView)),
          );
          expect(
            find.text(l.unrecognizedSourceResponseMessage),
            findsOneWidget,
          );
          expect(find.text(l.unsupportedMessage), findsNothing);
          expect(find.byType(FilledButton), findsNothing);
          expect(failure.retryPolicy, RetryPolicy.never);
          await tester.pump(const Duration(minutes: 1));
          expect(retries, 0);
          expect(tester.takeException(), isNull);
          await shot(tester, capture, 'source-response-$lang-${width.toInt()}');

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

          await render(
            tester,
            FailureView(
              failure: AppFailure(
                kind: FailureKind.unsupported,
                operation: Operation.discover,
              ),
              onRetry: () => retries++,
            ),
            lang: lang,
            width: width,
          );
          await tester.pumpAndSettle();
          expect(find.text(l.unsupportedMessage), findsOneWidget);
          expect(find.text(l.unrecognizedSourceResponseMessage), findsNothing);
          expect(find.byType(FilledButton), findsNothing);
          expect(tester.takeException(), isNull);
        },
        variant: TargetPlatformVariant({
          TargetPlatform.android,
          TargetPlatform.iOS,
          TargetPlatform.windows,
        }),
      );
    }
  }
}
