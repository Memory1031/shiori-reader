import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @readerImagePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Illustration'**
  String get readerImagePlaceholder;

  /// No description provided for @hideReaderControls.
  ///
  /// In en, this message translates to:
  /// **'Hide reading controls'**
  String get hideReaderControls;

  /// No description provided for @showReaderControls.
  ///
  /// In en, this message translates to:
  /// **'Show reading controls'**
  String get showReaderControls;

  /// No description provided for @readerExperimentAction.
  ///
  /// In en, this message translates to:
  /// **'Viewport experiment'**
  String get readerExperimentAction;

  /// No description provided for @accessRestrictedMessage.
  ///
  /// In en, this message translates to:
  /// **'Access to this content is restricted.'**
  String get accessRestrictedMessage;

  /// No description provided for @catalogTitle.
  ///
  /// In en, this message translates to:
  /// **'Contents'**
  String get catalogTitle;

  /// No description provided for @loadMoreAction.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get loadMoreAction;

  /// No description provided for @openReaderAction.
  ///
  /// In en, this message translates to:
  /// **'Open reader'**
  String get openReaderAction;

  /// No description provided for @pagedReading.
  ///
  /// In en, this message translates to:
  /// **'Paged'**
  String get pagedReading;

  /// No description provided for @scrollReading.
  ///
  /// In en, this message translates to:
  /// **'Scroll'**
  String get scrollReading;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Shiori'**
  String get appTitle;

  /// No description provided for @backAction.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get backAction;

  /// No description provided for @cacheFailureMessage.
  ///
  /// In en, this message translates to:
  /// **'The cache is unavailable. Content may not have been saved locally.'**
  String get cacheFailureMessage;

  /// No description provided for @cacheMissMessage.
  ///
  /// In en, this message translates to:
  /// **'No cached content is available. Connect to the internet and try again.'**
  String get cacheMissMessage;

  /// No description provided for @connectionFailureMessage.
  ///
  /// In en, this message translates to:
  /// **'Unable to connect. Check your network and try again.'**
  String get connectionFailureMessage;

  /// No description provided for @databaseFailureMessage.
  ///
  /// In en, this message translates to:
  /// **'A local storage problem prevented this operation.'**
  String get databaseFailureMessage;

  /// No description provided for @featurePending.
  ///
  /// In en, this message translates to:
  /// **'This feature is still in development.'**
  String get featurePending;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @loadingSettings.
  ///
  /// In en, this message translates to:
  /// **'Loading settings'**
  String get loadingSettings;

  /// No description provided for @notFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'This content could not be found.'**
  String get notFoundMessage;

  /// No description provided for @novelDetailsTitle.
  ///
  /// In en, this message translates to:
  /// **'Novel details'**
  String get novelDetailsTitle;

  /// No description provided for @parseFailureMessage.
  ///
  /// In en, this message translates to:
  /// **'The content format may have changed and cannot be read right now.'**
  String get parseFailureMessage;

  /// No description provided for @rateLimitedMessage.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Please try again later.'**
  String get rateLimitedMessage;

  /// No description provided for @readCacheAction.
  ///
  /// In en, this message translates to:
  /// **'Read cached content'**
  String get readCacheAction;

  /// No description provided for @readerTitle.
  ///
  /// In en, this message translates to:
  /// **'Reader'**
  String get readerTitle;

  /// No description provided for @readingFeaturesPending.
  ///
  /// In en, this message translates to:
  /// **'Reading features are coming soon.'**
  String get readingFeaturesPending;

  /// No description provided for @retryAction.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryAction;

  /// No description provided for @searchTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchTitle;

  /// No description provided for @sessionFailureMessage.
  ///
  /// In en, this message translates to:
  /// **'The access session is unavailable. Try again later.'**
  String get sessionFailureMessage;

  /// No description provided for @sourceUnavailableMessage.
  ///
  /// In en, this message translates to:
  /// **'The content service is temporarily unavailable. Try again later.'**
  String get sourceUnavailableMessage;

  /// No description provided for @tooLargeMessage.
  ///
  /// In en, this message translates to:
  /// **'This content is too large to process.'**
  String get tooLargeMessage;

  /// No description provided for @unsupportedMessage.
  ///
  /// In en, this message translates to:
  /// **'This feature is not supported yet.'**
  String get unsupportedMessage;

  /// No description provided for @readerSettings.
  ///
  /// In en, this message translates to:
  /// **'Reading settings'**
  String get readerSettings;

  /// No description provided for @readerFontSize.
  ///
  /// In en, this message translates to:
  /// **'Font size'**
  String get readerFontSize;

  /// No description provided for @readerLineHeight.
  ///
  /// In en, this message translates to:
  /// **'Line height'**
  String get readerLineHeight;

  /// No description provided for @readerParagraphSpacing.
  ///
  /// In en, this message translates to:
  /// **'Paragraph spacing'**
  String get readerParagraphSpacing;

  /// No description provided for @readerHorizontalPadding.
  ///
  /// In en, this message translates to:
  /// **'Horizontal padding'**
  String get readerHorizontalPadding;

  /// No description provided for @readerThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get readerThemeSystem;

  /// No description provided for @readerThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get readerThemeLight;

  /// No description provided for @readerThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get readerThemeDark;

  /// No description provided for @readerSettingsFailure.
  ///
  /// In en, this message translates to:
  /// **'Could not load or save reading settings.'**
  String get readerSettingsFailure;

  /// No description provided for @readerReset.
  ///
  /// In en, this message translates to:
  /// **'Reset defaults'**
  String get readerReset;

  /// No description provided for @readerProgressUnsaved.
  ///
  /// In en, this message translates to:
  /// **'Reading progress not saved. Tap to retry.'**
  String get readerProgressUnsaved;

  /// No description provided for @labTitle.
  ///
  /// In en, this message translates to:
  /// **'Theme Lab'**
  String get labTitle;

  /// No description provided for @labNotice.
  ///
  /// In en, this message translates to:
  /// **'Offline visual prototype · no library changes'**
  String get labNotice;

  /// No description provided for @labShelf.
  ///
  /// In en, this message translates to:
  /// **'Bookshelf'**
  String get labShelf;

  /// No description provided for @labDetail.
  ///
  /// In en, this message translates to:
  /// **'Book details'**
  String get labDetail;

  /// No description provided for @labReader.
  ///
  /// In en, this message translates to:
  /// **'Reader'**
  String get labReader;

  /// No description provided for @labContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue reading'**
  String get labContinue;

  /// No description provided for @labMyBooks.
  ///
  /// In en, this message translates to:
  /// **'My books'**
  String get labMyBooks;

  /// No description provided for @labDiscover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get labDiscover;

  /// No description provided for @labChapter.
  ///
  /// In en, this message translates to:
  /// **'Chapter 1 · The last train'**
  String get labChapter;

  /// No description provided for @labProgress.
  ///
  /// In en, this message translates to:
  /// **'About 36% of this chapter'**
  String get labProgress;

  /// No description provided for @labAuthor.
  ///
  /// In en, this message translates to:
  /// **'Shiori Studio'**
  String get labAuthor;

  /// No description provided for @labBook1.
  ///
  /// In en, this message translates to:
  /// **'The Station Beyond Summer'**
  String get labBook1;

  /// No description provided for @labBook2.
  ///
  /// In en, this message translates to:
  /// **'Letters to the Moon'**
  String get labBook2;

  /// No description provided for @labBook3.
  ///
  /// In en, this message translates to:
  /// **'A City in the Rain'**
  String get labBook3;

  /// No description provided for @labBook4.
  ///
  /// In en, this message translates to:
  /// **'Where the Sea Begins'**
  String get labBook4;

  /// No description provided for @labLongTitle.
  ///
  /// In en, this message translates to:
  /// **'The day we followed the last train beyond summer, and found a letter addressed to tomorrow'**
  String get labLongTitle;

  /// No description provided for @labSynopsis.
  ///
  /// In en, this message translates to:
  /// **'At a station with no name, a letter arrives every summer. This time, its sender is someone who has not yet been born. A quiet journey through seaside towns, small promises, and the space between two departures.'**
  String get labSynopsis;

  /// No description provided for @labParagraph.
  ///
  /// In en, this message translates to:
  /// **'The platform was quiet. Beyond the tracks, the sea held the last light of the afternoon. She opened the envelope carefully, as though the summer itself might slip out.\nThe letter began with a date from tomorrow. Somewhere behind her, a bell rang once.'**
  String get labParagraph;

  /// No description provided for @labCatalog.
  ///
  /// In en, this message translates to:
  /// **'Contents'**
  String get labCatalog;

  /// No description provided for @labSave.
  ///
  /// In en, this message translates to:
  /// **'Add to bookshelf'**
  String get labSave;

  /// No description provided for @labSaved.
  ///
  /// In en, this message translates to:
  /// **'On your bookshelf'**
  String get labSaved;

  /// No description provided for @labEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your next story is waiting.'**
  String get labEmpty;

  /// No description provided for @labSearch.
  ///
  /// In en, this message translates to:
  /// **'Find a book'**
  String get labSearch;

  /// No description provided for @labImport.
  ///
  /// In en, this message translates to:
  /// **'Import a file'**
  String get labImport;

  /// No description provided for @labNormal.
  ///
  /// In en, this message translates to:
  /// **'Content'**
  String get labNormal;

  /// No description provided for @labLong.
  ///
  /// In en, this message translates to:
  /// **'Long titles'**
  String get labLong;

  /// No description provided for @labMissing.
  ///
  /// In en, this message translates to:
  /// **'Missing cover'**
  String get labMissing;

  /// No description provided for @labEmptyState.
  ///
  /// In en, this message translates to:
  /// **'Empty'**
  String get labEmptyState;

  /// No description provided for @labLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get labLoading;

  /// No description provided for @labError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get labError;

  /// No description provided for @labPreviewAction.
  ///
  /// In en, this message translates to:
  /// **'Preview only — this action will be connected in the feature task.'**
  String get labPreviewAction;

  /// No description provided for @labSize.
  ///
  /// In en, this message translates to:
  /// **'Canvas width'**
  String get labSize;

  /// No description provided for @labScale.
  ///
  /// In en, this message translates to:
  /// **'Text scale'**
  String get labScale;

  /// No description provided for @labNight.
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get labNight;

  /// No description provided for @labIllustration.
  ///
  /// In en, this message translates to:
  /// **'Original geometric cover illustration'**
  String get labIllustration;

  /// No description provided for @labSettings.
  ///
  /// In en, this message translates to:
  /// **'Reading settings'**
  String get labSettings;

  /// No description provided for @labFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Full screen preview'**
  String get labFullscreen;

  /// No description provided for @readerRestoreNearby.
  ///
  /// In en, this message translates to:
  /// **'Content changed. Restored to a nearby position.'**
  String get readerRestoreNearby;

  /// No description provided for @readerRestoreReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read saved progress. Saving is paused; tap to retry restoration.'**
  String get readerRestoreReadFailed;

  /// No description provided for @appAppearance.
  ///
  /// In en, this message translates to:
  /// **'App appearance'**
  String get appAppearance;

  /// No description provided for @appAppearanceDescription.
  ///
  /// In en, this message translates to:
  /// **'Applies to app pages. Reading colors are set separately.'**
  String get appAppearanceDescription;

  /// No description provided for @readerColors.
  ///
  /// In en, this message translates to:
  /// **'Reading colors'**
  String get readerColors;

  /// No description provided for @readerPaper.
  ///
  /// In en, this message translates to:
  /// **'Paper'**
  String get readerPaper;

  /// No description provided for @readerWarm.
  ///
  /// In en, this message translates to:
  /// **'Warm paper'**
  String get readerWarm;

  /// No description provided for @readerNight.
  ///
  /// In en, this message translates to:
  /// **'Night'**
  String get readerNight;

  /// No description provided for @readerControlsHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the center for controls. In paged mode, tap either side; in scroll mode, swipe vertically. Change modes in reading settings.'**
  String get readerControlsHint;

  /// No description provided for @readerGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get readerGotIt;

  /// No description provided for @readerPreviousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous page'**
  String get readerPreviousPage;

  /// No description provided for @readerNextPage.
  ///
  /// In en, this message translates to:
  /// **'Next page'**
  String get readerNextPage;

  /// No description provided for @readerChapterProgress.
  ///
  /// In en, this message translates to:
  /// **'About {percent}% of this chapter'**
  String readerChapterProgress(int percent);
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
