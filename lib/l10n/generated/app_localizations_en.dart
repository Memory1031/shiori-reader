// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get accessRestrictedMessage => 'Access to this content is restricted.';

  @override
  String get catalogTitle => 'Contents';

  @override
  String get loadMoreAction => 'Load more';

  @override
  String get appTitle => 'Shiori';

  @override
  String get backAction => 'Back';

  @override
  String get cacheFailureMessage =>
      'The cache is unavailable. Content may not have been saved locally.';

  @override
  String get cacheMissMessage =>
      'No cached content is available. Connect to the internet and try again.';

  @override
  String get connectionFailureMessage =>
      'Unable to connect. Check your network and try again.';

  @override
  String get databaseFailureMessage =>
      'A local storage problem prevented this operation.';

  @override
  String get featurePending => 'This feature is still in development.';

  @override
  String get loading => 'Loading…';

  @override
  String get loadingSettings => 'Loading settings';

  @override
  String get notFoundMessage => 'This content could not be found.';

  @override
  String get novelDetailsTitle => 'Novel details';

  @override
  String get parseFailureMessage =>
      'The content format may have changed and cannot be read right now.';

  @override
  String get rateLimitedMessage => 'Too many requests. Please try again later.';

  @override
  String get readCacheAction => 'Read cached content';

  @override
  String get readerTitle => 'Reader';

  @override
  String get readingFeaturesPending => 'Reading features are coming soon.';

  @override
  String get retryAction => 'Retry';

  @override
  String get searchTitle => 'Search';

  @override
  String get sessionFailureMessage =>
      'The access session is unavailable. Try again later.';

  @override
  String get sourceUnavailableMessage =>
      'The content service is temporarily unavailable. Try again later.';

  @override
  String get tooLargeMessage => 'This content is too large to process.';

  @override
  String get unsupportedMessage => 'This feature is not supported yet.';
}
