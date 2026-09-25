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

  /// No description provided for @readerImagePreview.
  ///
  /// In en, this message translates to:
  /// **'View image'**
  String get readerImagePreview;

  /// No description provided for @readerFootnote.
  ///
  /// In en, this message translates to:
  /// **'Footnote {number}'**
  String readerFootnote(String number);

  /// No description provided for @localBookContents.
  ///
  /// In en, this message translates to:
  /// **'Book contents'**
  String get localBookContents;

  /// No description provided for @articleContents.
  ///
  /// In en, this message translates to:
  /// **'In-volume contents'**
  String get articleContents;

  /// No description provided for @articleContentsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recognisable section headings in this article. Use the volume list to switch articles.'**
  String get articleContentsEmpty;

  /// No description provided for @articleContentsHint.
  ///
  /// In en, this message translates to:
  /// **'Built from content headings; plain-text detection may be incomplete.'**
  String get articleContentsHint;

  /// No description provided for @volumesTitle.
  ///
  /// In en, this message translates to:
  /// **'Volumes'**
  String get volumesTitle;

  /// No description provided for @volumesLoad.
  ///
  /// In en, this message translates to:
  /// **'Browse volumes and chapters'**
  String get volumesLoad;

  /// No description provided for @volumesDescription.
  ///
  /// In en, this message translates to:
  /// **'Browse the source groups and choose a volume or chapter to read.'**
  String get volumesDescription;

  /// No description provided for @shelfTagline.
  ///
  /// In en, this message translates to:
  /// **'Keep your favourite stories close.'**
  String get shelfTagline;

  /// No description provided for @discoverTagline.
  ///
  /// In en, this message translates to:
  /// **'Find your next chapter.'**
  String get discoverTagline;

  /// No description provided for @offlineEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Offline demo · sample books only'**
  String get offlineEnvironment;

  /// No description provided for @historyTitle.
  ///
  /// In en, this message translates to:
  /// **'Reading history'**
  String get historyTitle;

  /// No description provided for @historyClear.
  ///
  /// In en, this message translates to:
  /// **'Clear this reading history'**
  String get historyClear;

  /// No description provided for @chapterFallback.
  ///
  /// In en, this message translates to:
  /// **'The saved chapter is no longer listed. Opened a nearby chapter.'**
  String get chapterFallback;

  /// No description provided for @historyEmpty.
  ///
  /// In en, this message translates to:
  /// **'No reading history yet.'**
  String get historyEmpty;

  /// No description provided for @shelfTitle.
  ///
  /// In en, this message translates to:
  /// **'Bookshelf'**
  String get shelfTitle;

  /// No description provided for @noSources.
  ///
  /// In en, this message translates to:
  /// **'No sources available. Saved books remain on your bookshelf.'**
  String get noSources;

  /// No description provided for @discoverEmpty.
  ///
  /// In en, this message translates to:
  /// **'No recommendations available.'**
  String get discoverEmpty;

  /// No description provided for @importTitle.
  ///
  /// In en, this message translates to:
  /// **'Import book'**
  String get importTitle;

  /// No description provided for @importPending.
  ///
  /// In en, this message translates to:
  /// **'TXT / EPUB import and Open with Shiori are planned and still in development.'**
  String get importPending;

  /// No description provided for @discoverUnsupported.
  ///
  /// In en, this message translates to:
  /// **'This source has no recommendations. Use Search to find a novel.'**
  String get discoverUnsupported;

  /// No description provided for @discoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get discoverTitle;

  /// No description provided for @shelfEmpty.
  ///
  /// In en, this message translates to:
  /// **'Your bookshelf is empty.'**
  String get shelfEmpty;

  /// No description provided for @shelfLayout.
  ///
  /// In en, this message translates to:
  /// **'Switch bookshelf layout'**
  String get shelfLayout;

  /// No description provided for @nextChapter.
  ///
  /// In en, this message translates to:
  /// **'Next chapter'**
  String get nextChapter;

  /// No description provided for @previousChapter.
  ///
  /// In en, this message translates to:
  /// **'Previous chapter'**
  String get previousChapter;

  /// No description provided for @catalogUnnamedVolume.
  ///
  /// In en, this message translates to:
  /// **'Untitled volume'**
  String get catalogUnnamedVolume;

  /// No description provided for @catalogStale.
  ///
  /// In en, this message translates to:
  /// **'Saved contents may be out of date.'**
  String get catalogStale;

  /// No description provided for @catalogEmpty.
  ///
  /// In en, this message translates to:
  /// **'No chapters available.'**
  String get catalogEmpty;

  /// No description provided for @detailRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh details'**
  String get detailRefresh;

  /// No description provided for @detailStale.
  ///
  /// In en, this message translates to:
  /// **'Saved details may be out of date.'**
  String get detailStale;

  /// No description provided for @detailStart.
  ///
  /// In en, this message translates to:
  /// **'Start reading'**
  String get detailStart;

  /// No description provided for @detailContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue reading'**
  String get detailContinue;

  /// No description provided for @homeContinueAction.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get homeContinueAction;

  /// No description provided for @detailAddShelf.
  ///
  /// In en, this message translates to:
  /// **'Add to bookshelf'**
  String get detailAddShelf;

  /// No description provided for @detailRemoveShelf.
  ///
  /// In en, this message translates to:
  /// **'Remove from bookshelf'**
  String get detailRemoveShelf;

  /// No description provided for @detailActionsPending.
  ///
  /// In en, this message translates to:
  /// **'Unavailable reading and bookshelf actions are still in development.'**
  String get detailActionsPending;

  /// No description provided for @detailSynopsis.
  ///
  /// In en, this message translates to:
  /// **'Synopsis'**
  String get detailSynopsis;

  /// No description provided for @detailOnShelf.
  ///
  /// In en, this message translates to:
  /// **'In bookshelf'**
  String get detailOnShelf;

  /// No description provided for @detailShowMore.
  ///
  /// In en, this message translates to:
  /// **'Show more'**
  String get detailShowMore;

  /// No description provided for @detailShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get detailShowLess;

  /// No description provided for @detailNoSynopsis.
  ///
  /// In en, this message translates to:
  /// **'No synopsis available.'**
  String get detailNoSynopsis;

  /// No description provided for @detailCover.
  ///
  /// In en, this message translates to:
  /// **'Book cover'**
  String get detailCover;

  /// No description provided for @detailStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Publication status unavailable'**
  String get detailStatusUnknown;

  /// No description provided for @detailStatusOngoing.
  ///
  /// In en, this message translates to:
  /// **'Ongoing'**
  String get detailStatusOngoing;

  /// No description provided for @detailStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get detailStatusCompleted;

  /// No description provided for @detailStatusHiatus.
  ///
  /// In en, this message translates to:
  /// **'On hiatus'**
  String get detailStatusHiatus;

  /// No description provided for @searchKeyword.
  ///
  /// In en, this message translates to:
  /// **'Title or keyword'**
  String get searchKeyword;

  /// No description provided for @searchInitial.
  ///
  /// In en, this message translates to:
  /// **'Enter a keyword, then choose Search.'**
  String get searchInitial;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No novels found. Try another keyword.'**
  String get searchNoResults;

  /// No description provided for @searchNoMore.
  ///
  /// In en, this message translates to:
  /// **'All results shown'**
  String get searchNoMore;

  /// No description provided for @searchDraftNotice.
  ///
  /// In en, this message translates to:
  /// **'These are previous results. Submit your edited keyword to search again.'**
  String get searchDraftNotice;

  /// No description provided for @searchResultsFor.
  ///
  /// In en, this message translates to:
  /// **'Results for “{query}”'**
  String searchResultsFor(String query);

  /// No description provided for @devSearchTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline search'**
  String get devSearchTitle;

  /// No description provided for @devSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search “a” to try pagination and view offline novel details.'**
  String get devSearchHint;

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
  /// **'Chapter 36%'**
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

  /// No description provided for @readerPageTurn.
  ///
  /// In en, this message translates to:
  /// **'Page turn'**
  String get readerPageTurn;

  /// No description provided for @readerPageTurnCurl.
  ///
  /// In en, this message translates to:
  /// **'Curl'**
  String get readerPageTurnCurl;

  /// No description provided for @readerPageTurnCover.
  ///
  /// In en, this message translates to:
  /// **'Cover'**
  String get readerPageTurnCover;

  /// No description provided for @readerPageTurnSlide.
  ///
  /// In en, this message translates to:
  /// **'Slide'**
  String get readerPageTurnSlide;

  /// No description provided for @readerPageTurnNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get readerPageTurnNone;

  /// No description provided for @readerControlsHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the center to show or hide controls. Tap either side or swipe horizontally to turn pages.'**
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
  /// **'Chapter {percent}%'**
  String readerChapterProgress(String percent);

  /// No description provided for @moreActions.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get moreActions;

  /// No description provided for @readerProgressLabel.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get readerProgressLabel;

  /// No description provided for @shelfGrid.
  ///
  /// In en, this message translates to:
  /// **'Grid'**
  String get shelfGrid;

  /// No description provided for @shelfList.
  ///
  /// In en, this message translates to:
  /// **'List'**
  String get shelfList;

  /// No description provided for @allChapters.
  ///
  /// In en, this message translates to:
  /// **'All chapters'**
  String get allChapters;

  /// No description provided for @onlineSource.
  ///
  /// In en, this message translates to:
  /// **'Online source'**
  String get onlineSource;

  /// No description provided for @shelfDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get shelfDetails;

  /// No description provided for @shelfRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get shelfRemove;

  /// No description provided for @launchTagline.
  ///
  /// In en, this message translates to:
  /// **'Your story continues'**
  String get launchTagline;

  /// No description provided for @launchLoading.
  ///
  /// In en, this message translates to:
  /// **'Preparing your library…'**
  String get launchLoading;

  /// No description provided for @cacheTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline content'**
  String get cacheTitle;

  /// No description provided for @cacheUsage.
  ///
  /// In en, this message translates to:
  /// **'Text & metadata {text} MiB · Images {images} MiB'**
  String cacheUsage(String text, String images);

  /// No description provided for @cacheOfflineHint.
  ///
  /// In en, this message translates to:
  /// **'Chapters cached from online books, available for offline reading. Cached content may be cleared to free up space.'**
  String get cacheOfflineHint;

  /// No description provided for @cacheChapterStatus.
  ///
  /// In en, this message translates to:
  /// **'Text cached · Images {saved}/{total}'**
  String cacheChapterStatus(int saved, int total);

  /// No description provided for @cacheStored.
  ///
  /// In en, this message translates to:
  /// **'Cached storage'**
  String get cacheStored;

  /// No description provided for @cacheBooks.
  ///
  /// In en, this message translates to:
  /// **'Cached books'**
  String get cacheBooks;

  /// No description provided for @cacheCounts.
  ///
  /// In en, this message translates to:
  /// **'{books, plural, =1{1 book} other{{books} books}} · {chapters, plural, =1{1 chapter} other{{chapters} chapters}}'**
  String cacheCounts(int books, int chapters);

  /// No description provided for @cacheBookImages.
  ///
  /// In en, this message translates to:
  /// **'{chapters, plural, =1{1 chapter} other{{chapters} chapters}} · Images {saved}/{total}'**
  String cacheBookImages(int chapters, int saved, int total);

  /// No description provided for @cacheBookNoImages.
  ///
  /// In en, this message translates to:
  /// **'{chapters, plural, =1{1 chapter} other{{chapters} chapters}} · No illustrations'**
  String cacheBookNoImages(int chapters);

  /// No description provided for @cacheNoChapters.
  ///
  /// In en, this message translates to:
  /// **'Metadata only · No offline chapters'**
  String get cacheNoChapters;

  /// No description provided for @cacheClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear all cache'**
  String get cacheClearAll;

  /// No description provided for @cacheEmpty.
  ///
  /// In en, this message translates to:
  /// **'No cached articles yet'**
  String get cacheEmpty;

  /// No description provided for @cacheClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear cached content?'**
  String get cacheClearTitle;

  /// No description provided for @cacheClearExplanation.
  ///
  /// In en, this message translates to:
  /// **'Your bookshelf, progress and settings are kept. Cleared content may need a connection when reopened.'**
  String get cacheClearExplanation;

  /// No description provided for @cacheClearBook.
  ///
  /// In en, this message translates to:
  /// **'Clear book cache'**
  String get cacheClearBook;

  /// No description provided for @cacheCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cacheCancel;

  /// No description provided for @cacheClear.
  ///
  /// In en, this message translates to:
  /// **'Clear cache'**
  String get cacheClear;

  /// No description provided for @prefetchTitle.
  ///
  /// In en, this message translates to:
  /// **'Reading cache'**
  String get prefetchTitle;

  /// No description provided for @prefetchExplanation.
  ///
  /// In en, this message translates to:
  /// **'Prepares this article and one article you choose. It never opens it or changes your reading progress.'**
  String get prefetchExplanation;

  /// No description provided for @prefetchCurrent.
  ///
  /// In en, this message translates to:
  /// **'Cache images in this article'**
  String get prefetchCurrent;

  /// No description provided for @prefetchNext.
  ///
  /// In en, this message translates to:
  /// **'Prepare the selected next article'**
  String get prefetchNext;

  /// No description provided for @prefetchChoose.
  ///
  /// In en, this message translates to:
  /// **'Read next'**
  String get prefetchChoose;

  /// No description provided for @prefetchNoTarget.
  ///
  /// In en, this message translates to:
  /// **'No next article'**
  String get prefetchNoTarget;

  /// No description provided for @prefetchPause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get prefetchPause;

  /// No description provided for @prefetchResume.
  ///
  /// In en, this message translates to:
  /// **'Continue / retry'**
  String get prefetchResume;

  /// No description provided for @prefetchIdle.
  ///
  /// In en, this message translates to:
  /// **'Not started'**
  String get prefetchIdle;

  /// No description provided for @prefetchRunning.
  ///
  /// In en, this message translates to:
  /// **'Preparing images and next reading'**
  String get prefetchRunning;

  /// No description provided for @prefetchPaused.
  ///
  /// In en, this message translates to:
  /// **'Caching paused'**
  String get prefetchPaused;

  /// No description provided for @prefetchBudget.
  ///
  /// In en, this message translates to:
  /// **'Batch limit reached. Continue manually.'**
  String get prefetchBudget;

  /// No description provided for @prefetchPartial.
  ///
  /// In en, this message translates to:
  /// **'Some resources could not be saved. You can retry.'**
  String get prefetchPartial;

  /// No description provided for @prefetchComplete.
  ///
  /// In en, this message translates to:
  /// **'Batch finished. Check saved content for offline availability.'**
  String get prefetchComplete;

  /// No description provided for @prefetchSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not save your choice. Please retry.'**
  String get prefetchSaveFailed;

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

  /// No description provided for @importIncoming.
  ///
  /// In en, this message translates to:
  /// **'A file is ready to import'**
  String get importIncoming;

  /// No description provided for @importReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get importReview;

  /// No description provided for @importCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get importCancel;

  /// No description provided for @importReceiving.
  ///
  /// In en, this message translates to:
  /// **'Copying file…'**
  String get importReceiving;

  /// No description provided for @importProcessing.
  ///
  /// In en, this message translates to:
  /// **'Importing book…'**
  String get importProcessing;

  /// No description provided for @importSuccess.
  ///
  /// In en, this message translates to:
  /// **'The book has been saved.'**
  String get importSuccess;

  /// No description provided for @importHint.
  ///
  /// In en, this message translates to:
  /// **'Choose TXT or EPUB files, up to 128 MiB each.'**
  String get importHint;

  /// No description provided for @importChoose.
  ///
  /// In en, this message translates to:
  /// **'Choose file'**
  String get importChoose;

  /// No description provided for @importStart.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get importStart;

  /// No description provided for @importRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get importRetry;

  /// No description provided for @importDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get importDone;

  /// No description provided for @importImportAll.
  ///
  /// In en, this message translates to:
  /// **'Import all'**
  String get importImportAll;

  /// No description provided for @importRetryFailed.
  ///
  /// In en, this message translates to:
  /// **'Retry failed'**
  String get importRetryFailed;

  /// No description provided for @importResume.
  ///
  /// In en, this message translates to:
  /// **'Continue importing'**
  String get importResume;

  /// No description provided for @importStop.
  ///
  /// In en, this message translates to:
  /// **'Stop importing'**
  String get importStop;

  /// No description provided for @importWaiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get importWaiting;

  /// No description provided for @importItemImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing'**
  String get importItemImporting;

  /// No description provided for @importItemImported.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get importItemImported;

  /// No description provided for @importBatchReady.
  ///
  /// In en, this message translates to:
  /// **'Ready to import {count} books'**
  String importBatchReady(int count);

  /// No description provided for @importBatchProgress.
  ///
  /// In en, this message translates to:
  /// **'Importing {current} of {total}'**
  String importBatchProgress(int current, int total);

  /// No description provided for @importBatchFinished.
  ///
  /// In en, this message translates to:
  /// **'Finished importing'**
  String get importBatchFinished;

  /// No description provided for @importBatchDone.
  ///
  /// In en, this message translates to:
  /// **'Imported {count} books'**
  String importBatchDone(int count);

  /// No description provided for @importBatchStopped.
  ///
  /// In en, this message translates to:
  /// **'Import stopped'**
  String get importBatchStopped;

  /// No description provided for @importBatchSummary.
  ///
  /// In en, this message translates to:
  /// **'{succeeded} imported · {failed} failed'**
  String importBatchSummary(int succeeded, int failed);

  /// No description provided for @importBatchRemaining.
  ///
  /// In en, this message translates to:
  /// **'{count} not imported yet'**
  String importBatchRemaining(int count);

  /// No description provided for @importTooLarge.
  ///
  /// In en, this message translates to:
  /// **'The file exceeds 128 MiB. Choose a smaller file.'**
  String get importTooLarge;

  /// No description provided for @importBatchLimit.
  ///
  /// In en, this message translates to:
  /// **'The selection exceeds the batch import limit. Choose fewer or smaller files.'**
  String get importBatchLimit;

  /// No description provided for @importMultiple.
  ///
  /// In en, this message translates to:
  /// **'Only one file can be received at a time. Select again.'**
  String get importMultiple;

  /// No description provided for @importBusy.
  ///
  /// In en, this message translates to:
  /// **'Handle the pending file first, then open or share this file again.'**
  String get importBusy;

  /// No description provided for @importUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Choose a TXT or EPUB file. Web links cannot be imported.'**
  String get importUnsupported;

  /// No description provided for @importInvalid.
  ///
  /// In en, this message translates to:
  /// **'The file is empty or its contents do not match the format.'**
  String get importInvalid;

  /// No description provided for @importParserUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This version cannot parse this format yet. Nothing was imported. You can cancel and choose the file again later.'**
  String get importParserUnavailable;

  /// No description provided for @importStorage.
  ///
  /// In en, this message translates to:
  /// **'The file could not be saved. Check available space and retry.'**
  String get importStorage;

  /// No description provided for @importCancelled.
  ///
  /// In en, this message translates to:
  /// **'Import cancelled. The book was not saved.'**
  String get importCancelled;

  /// No description provided for @importUnreadable.
  ///
  /// In en, this message translates to:
  /// **'The file could not be read. Check access and choose it again.'**
  String get importUnreadable;

  /// No description provided for @importEncodingHint.
  ///
  /// In en, this message translates to:
  /// **'Check the previews and choose the encoding that displays the text correctly.'**
  String get importEncodingHint;

  /// No description provided for @importEncodingAuto.
  ///
  /// In en, this message translates to:
  /// **'Text encoding: Automatic'**
  String get importEncodingAuto;

  /// No description provided for @importEncodingInvalid.
  ///
  /// In en, this message translates to:
  /// **'The entire file could not be decoded with this encoding. Choose another encoding or check the original.'**
  String get importEncodingInvalid;

  /// No description provided for @importDrm.
  ///
  /// In en, this message translates to:
  /// **'This EPUB contains protected or encrypted content and cannot be imported.'**
  String get importDrm;

  /// No description provided for @importFixedLayout.
  ///
  /// In en, this message translates to:
  /// **'Fixed-layout EPUB is not supported. Use a reflowable edition.'**
  String get importFixedLayout;

  /// No description provided for @importParseLimit.
  ///
  /// In en, this message translates to:
  /// **'Parsing limits exceeded: TXT 16 MiB, EPUB 64 MiB. Oversized chapters, images, or expanded content are also unsupported.'**
  String get importParseLimit;

  /// No description provided for @importEpubSupport.
  ///
  /// In en, this message translates to:
  /// **'Supports EPUB text and images.'**
  String get importEpubSupport;

  /// No description provided for @localBooksCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 book} other{{count} books}}'**
  String localBooksCount(int count);

  /// No description provided for @localBooksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Your imported books, ready to read offline.'**
  String get localBooksSubtitle;

  /// No description provided for @localBooksImportedOn.
  ///
  /// In en, this message translates to:
  /// **'Imported {date}'**
  String localBooksImportedOn(String date);

  /// No description provided for @localBooksTitle.
  ///
  /// In en, this message translates to:
  /// **'Local files'**
  String get localBooksTitle;

  /// No description provided for @localBooksHint.
  ///
  /// In en, this message translates to:
  /// **'Manage imported books. Removing a local book deletes its in-app files and reading progress. The original external file is unaffected.'**
  String get localBooksHint;

  /// No description provided for @localBooksEmpty.
  ///
  /// In en, this message translates to:
  /// **'No local books imported yet.'**
  String get localBooksEmpty;

  /// No description provided for @localDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete local book?'**
  String get localDeleteTitle;

  /// No description provided for @localDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Delete the app-owned original, text, images, shelf entry, and reading progress for “{title}”. The external original is unaffected. This cannot be undone.'**
  String localDeleteMessage(String title);

  /// No description provided for @localDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete book and progress'**
  String get localDeleteConfirm;

  /// No description provided for @localDeleted.
  ///
  /// In en, this message translates to:
  /// **'Local book and reading progress deleted.'**
  String get localDeleted;

  /// No description provided for @localCleanupPending.
  ///
  /// In en, this message translates to:
  /// **'Book and progress removed. Remaining files will be cleaned up at the next launch.'**
  String get localCleanupPending;

  /// No description provided for @localReadNow.
  ///
  /// In en, this message translates to:
  /// **'Read now'**
  String get localReadNow;

  /// No description provided for @appAccentTitle.
  ///
  /// In en, this message translates to:
  /// **'Accent color'**
  String get appAccentTitle;

  /// No description provided for @appAccentTeal.
  ///
  /// In en, this message translates to:
  /// **'Soft teal'**
  String get appAccentTeal;

  /// No description provided for @appAccentBlueGrey.
  ///
  /// In en, this message translates to:
  /// **'Blue grey'**
  String get appAccentBlueGrey;

  /// No description provided for @appAccentWarmBrown.
  ///
  /// In en, this message translates to:
  /// **'Warm brown'**
  String get appAccentWarmBrown;

  /// No description provided for @appAccentSoftPink.
  ///
  /// In en, this message translates to:
  /// **'Soft pink'**
  String get appAccentSoftPink;

  /// No description provided for @readerChapterLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not open the chapter. Your current page is still available.'**
  String get readerChapterLoadFailed;

  /// No description provided for @localReparseAll.
  ///
  /// In en, this message translates to:
  /// **'Reparse all'**
  String get localReparseAll;

  /// No description provided for @localFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get localFilterAll;

  /// No description provided for @localReparseAllConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reparse all {count} local books one at a time and restore reading positions where possible. Failures keep the previous content and do not stop other books. You can stop at any time.'**
  String localReparseAllConfirm(int count);

  /// No description provided for @localReparseAllProgress.
  ///
  /// In en, this message translates to:
  /// **'Reparsing {current} of {total}: {title}'**
  String localReparseAllProgress(int current, int total, String title);

  /// No description provided for @localReparseStop.
  ///
  /// In en, this message translates to:
  /// **'Stop reparsing'**
  String get localReparseStop;

  /// No description provided for @localReparseAllSummary.
  ///
  /// In en, this message translates to:
  /// **'Succeeded: {succeeded} · Failed: {failed} · Not processed: {remaining}'**
  String localReparseAllSummary(int succeeded, int failed, int remaining);

  /// No description provided for @localReparseAllApproximate.
  ///
  /// In en, this message translates to:
  /// **'Restored nearby positions for {count} books. Please check them when you resume reading.'**
  String localReparseAllApproximate(int count);

  /// No description provided for @localReparse.
  ///
  /// In en, this message translates to:
  /// **'Reparse'**
  String get localReparse;

  /// No description provided for @localReparseConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reparse the saved original and restore your reading position where possible. Failure or cancellation keeps the previous content.'**
  String get localReparseConfirm;

  /// No description provided for @localReparseDone.
  ///
  /// In en, this message translates to:
  /// **'Reparsed. Your reading position is preserved.'**
  String get localReparseDone;

  /// No description provided for @localReparseApproximate.
  ///
  /// In en, this message translates to:
  /// **'Reparsed. Restored a nearby position; please check the current text.'**
  String get localReparseApproximate;

  /// No description provided for @localReparseReaderClosed.
  ///
  /// In en, this message translates to:
  /// **'This book is being reparsed. Return to the library and reopen it.'**
  String get localReparseReaderClosed;

  /// No description provided for @readerLinks.
  ///
  /// In en, this message translates to:
  /// **'Chapter notes'**
  String get readerLinks;

  /// No description provided for @readerNotesFootnotes.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get readerNotesFootnotes;

  /// No description provided for @readerNotesLinks.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get readerNotesLinks;

  /// No description provided for @readerLinkHere.
  ///
  /// In en, this message translates to:
  /// **'In this chapter'**
  String get readerLinkHere;

  /// No description provided for @readerLinkElsewhere.
  ///
  /// In en, this message translates to:
  /// **'Elsewhere in this book'**
  String get readerLinkElsewhere;

  /// No description provided for @readerLinkReturn.
  ///
  /// In en, this message translates to:
  /// **'Return to reading'**
  String get readerLinkReturn;

  /// No description provided for @readerLinkUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Link unavailable. Only valid documents and anchors within this book can be opened.'**
  String get readerLinkUnavailable;

  /// No description provided for @readerLinkDepth.
  ///
  /// In en, this message translates to:
  /// **'Link depth limit reached. Return before opening another link.'**
  String get readerLinkDepth;

  /// No description provided for @readerMarginVeryNarrow.
  ///
  /// In en, this message translates to:
  /// **'Narrowest'**
  String get readerMarginVeryNarrow;

  /// No description provided for @readerMarginNarrow.
  ///
  /// In en, this message translates to:
  /// **'Narrow'**
  String get readerMarginNarrow;

  /// No description provided for @readerMarginMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get readerMarginMedium;

  /// No description provided for @readerMarginWide.
  ///
  /// In en, this message translates to:
  /// **'Wide'**
  String get readerMarginWide;

  /// No description provided for @readerMarginVeryWide.
  ///
  /// In en, this message translates to:
  /// **'Widest'**
  String get readerMarginVeryWide;

  /// No description provided for @readerFollowSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get readerFollowSystem;

  /// No description provided for @readerFollowSystemHint.
  ///
  /// In en, this message translates to:
  /// **'Switches to Night while the system is dark'**
  String get readerFollowSystemHint;

  /// No description provided for @readerUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get readerUndo;

  /// No description provided for @readerDecrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease {label}'**
  String readerDecrease(String label);

  /// No description provided for @readerIncrease.
  ///
  /// In en, this message translates to:
  /// **'Increase {label}'**
  String readerIncrease(String label);

  /// No description provided for @bookFinished.
  ///
  /// In en, this message translates to:
  /// **'Finished'**
  String get bookFinished;

  /// No description provided for @bookCaughtUp.
  ///
  /// In en, this message translates to:
  /// **'Caught up'**
  String get bookCaughtUp;

  /// No description provided for @bookCurrentEnd.
  ///
  /// In en, this message translates to:
  /// **'End of available chapters'**
  String get bookCurrentEnd;

  /// No description provided for @bookProgressPercent.
  ///
  /// In en, this message translates to:
  /// **'Reading progress {percent}%'**
  String bookProgressPercent(String percent);

  /// No description provided for @readerChapterPercent.
  ///
  /// In en, this message translates to:
  /// **'Chapter {percent}%'**
  String readerChapterPercent(String percent);

  /// No description provided for @readerReadingProgress.
  ///
  /// In en, this message translates to:
  /// **'Reading progress'**
  String get readerReadingProgress;

  /// No description provided for @readerBackToShelf.
  ///
  /// In en, this message translates to:
  /// **'Back to bookshelf'**
  String get readerBackToShelf;

  /// No description provided for @readerViewCatalog.
  ///
  /// In en, this message translates to:
  /// **'View contents'**
  String get readerViewCatalog;

  /// No description provided for @readerRestart.
  ///
  /// In en, this message translates to:
  /// **'Read again'**
  String get readerRestart;

  /// No description provided for @bookOnline.
  ///
  /// In en, this message translates to:
  /// **'Online'**
  String get bookOnline;

  /// No description provided for @updateTitle.
  ///
  /// In en, this message translates to:
  /// **'About & updates'**
  String get updateTitle;

  /// No description provided for @updateInstalled.
  ///
  /// In en, this message translates to:
  /// **'Installed: {version}'**
  String updateInstalled(String version);

  /// No description provided for @updateDevelopment.
  ///
  /// In en, this message translates to:
  /// **'Development builds do not connect to the production update source.'**
  String get updateDevelopment;

  /// No description provided for @updateUnsupported.
  ///
  /// In en, this message translates to:
  /// **'Get updates through the App Store or TestFlight.'**
  String get updateUnsupported;

  /// No description provided for @updateInvalidIdentity.
  ///
  /// In en, this message translates to:
  /// **'Unable to verify the installed version. Update checks are unavailable.'**
  String get updateInvalidIdentity;

  /// No description provided for @updateAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Check automatically'**
  String get updateAutomatic;

  /// No description provided for @updateAutomaticHint.
  ///
  /// In en, this message translates to:
  /// **'At most once a day. You choose when to download.'**
  String get updateAutomaticHint;

  /// No description provided for @updateChannel.
  ///
  /// In en, this message translates to:
  /// **'Update channel'**
  String get updateChannel;

  /// No description provided for @updateStable.
  ///
  /// In en, this message translates to:
  /// **'Stable'**
  String get updateStable;

  /// No description provided for @updateBeta.
  ///
  /// In en, this message translates to:
  /// **'Beta'**
  String get updateBeta;

  /// No description provided for @updateChannelHint.
  ///
  /// In en, this message translates to:
  /// **'Switching channels never downgrades. If your beta is newer, you\'ll be notified when a stable upgrade is available.'**
  String get updateChannelHint;

  /// No description provided for @updateNeverChecked.
  ///
  /// In en, this message translates to:
  /// **'Not checked yet'**
  String get updateNeverChecked;

  /// No description provided for @updateLastChecked.
  ///
  /// In en, this message translates to:
  /// **'Last checked: {time}'**
  String updateLastChecked(String time);

  /// No description provided for @updateCheck.
  ///
  /// In en, this message translates to:
  /// **'Check for updates'**
  String get updateCheck;

  /// No description provided for @updateCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get updateCancel;

  /// No description provided for @updateChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get updateChecking;

  /// No description provided for @updateNetworkError.
  ///
  /// In en, this message translates to:
  /// **'Could not connect. Check your connection and try again.'**
  String get updateNetworkError;

  /// No description provided for @updateRateLimited.
  ///
  /// In en, this message translates to:
  /// **'Request limit reached. Try again after {time}.'**
  String updateRateLimited(String time);

  /// No description provided for @updateIncomplete.
  ///
  /// In en, this message translates to:
  /// **'Release information is incomplete. Try checking again later.'**
  String get updateIncomplete;

  /// No description provided for @updateVerificationError.
  ///
  /// In en, this message translates to:
  /// **'Update verification failed. Check for updates again.'**
  String get updateVerificationError;

  /// No description provided for @updatePackageInvalid.
  ///
  /// In en, this message translates to:
  /// **'The downloaded package is no longer valid. Download it again.'**
  String get updatePackageInvalid;

  /// No description provided for @updateStorageError.
  ///
  /// In en, this message translates to:
  /// **'Could not access update files. Check free space and folder permissions, then retry.'**
  String get updateStorageError;

  /// No description provided for @updateCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get updateCancelled;

  /// No description provided for @updateNoUpdate.
  ///
  /// In en, this message translates to:
  /// **'No newer release is available on this channel.'**
  String get updateNoUpdate;

  /// No description provided for @updateSize.
  ///
  /// In en, this message translates to:
  /// **'Download size: {size} MB'**
  String updateSize(String size);

  /// No description provided for @updateProgress.
  ///
  /// In en, this message translates to:
  /// **'{percent}% downloaded'**
  String updateProgress(int percent);

  /// No description provided for @updateDownload.
  ///
  /// In en, this message translates to:
  /// **'Download update'**
  String get updateDownload;

  /// No description provided for @updateDownloaded.
  ///
  /// In en, this message translates to:
  /// **'Download verified. Visit the release page for installation instructions.'**
  String get updateDownloaded;

  /// No description provided for @updateReleasePage.
  ///
  /// In en, this message translates to:
  /// **'View full release notes'**
  String get updateReleasePage;

  /// No description provided for @updateLinkCopied.
  ///
  /// In en, this message translates to:
  /// **'Could not open the browser. Link copied.'**
  String get updateLinkCopied;

  /// No description provided for @updateAvailable.
  ///
  /// In en, this message translates to:
  /// **'Update available: {version}'**
  String updateAvailable(String version);

  /// No description provided for @updateView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get updateView;

  /// No description provided for @updateInstall.
  ///
  /// In en, this message translates to:
  /// **'Install update'**
  String get updateInstall;

  /// No description provided for @updateInstallHint.
  ///
  /// In en, this message translates to:
  /// **'The package is verified. Installing will close the app; your library, reading position and settings will be kept.'**
  String get updateInstallHint;

  /// No description provided for @updateInstallPermission.
  ///
  /// In en, this message translates to:
  /// **'Allow Shiori to install app updates. Return to this page after granting permission, then tap Install update.'**
  String get updateInstallPermission;

  /// No description provided for @updateInstallSettings.
  ///
  /// In en, this message translates to:
  /// **'Open installation settings'**
  String get updateInstallSettings;

  /// No description provided for @updateInstalling.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the system installer. Confirm or cancel in the system dialog.'**
  String get updateInstalling;

  /// No description provided for @updateInstallCancelled.
  ///
  /// In en, this message translates to:
  /// **'Installation cancelled. The downloaded package is kept for retry.'**
  String get updateInstallCancelled;

  /// No description provided for @updateInstallFailed.
  ///
  /// In en, this message translates to:
  /// **'The system could not complete installation. Check free space and installation permission, then retry.'**
  String get updateInstallFailed;

  /// No description provided for @updateRestartInstall.
  ///
  /// In en, this message translates to:
  /// **'Restart to update'**
  String get updateRestartInstall;

  /// No description provided for @updateInstallHintWindows.
  ///
  /// In en, this message translates to:
  /// **'The package is verified. Shiori will close, replace its program files and start again; your library, reading position and settings will be kept.'**
  String get updateInstallHintWindows;

  /// No description provided for @updateRestarting.
  ///
  /// In en, this message translates to:
  /// **'Closing Shiori to install the update. It will start again when installation finishes.'**
  String get updateRestarting;

  /// No description provided for @updateInstallFailedWindows.
  ///
  /// In en, this message translates to:
  /// **'The update could not be completed. Retry, or download the full Windows ZIP from the release page and extract it again. Your library and reading data are stored separately and are not affected.'**
  String get updateInstallFailedWindows;

  /// No description provided for @updateInstallInstances.
  ///
  /// In en, this message translates to:
  /// **'Close other Shiori windows, then retry.'**
  String get updateInstallInstances;

  /// No description provided for @updateInstallLocation.
  ///
  /// In en, this message translates to:
  /// **'Shiori cannot update itself in this folder. Extract the full Windows ZIP to a writable folder on a local drive, or update manually from the release page.'**
  String get updateInstallLocation;

  /// No description provided for @updateWorkspaceConflict.
  ///
  /// In en, this message translates to:
  /// **'A folder named “<Shiori folder name>.update” next to the Shiori folder was not created by Shiori. The update stopped to protect its files. Move or rename that folder, then retry.'**
  String get updateWorkspaceConflict;

  /// No description provided for @updateInstallBusy.
  ///
  /// In en, this message translates to:
  /// **'Wait for the current operation to finish before installing.'**
  String get updateInstallBusy;

  /// No description provided for @updateReturnToLibrary.
  ///
  /// In en, this message translates to:
  /// **'Return to the library and finish any import, then open App updates from the menu.'**
  String get updateReturnToLibrary;

  /// No description provided for @updateSection.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updateSection;

  /// No description provided for @updateProject.
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get updateProject;

  /// No description provided for @updateChooseChannel.
  ///
  /// In en, this message translates to:
  /// **'Choose update channel'**
  String get updateChooseChannel;

  /// No description provided for @updateStableHint.
  ///
  /// In en, this message translates to:
  /// **'Receive stable releases only'**
  String get updateStableHint;

  /// No description provided for @updateBetaHint.
  ///
  /// In en, this message translates to:
  /// **'Receive beta and stable releases'**
  String get updateBetaHint;

  /// No description provided for @updateNewVersion.
  ///
  /// In en, this message translates to:
  /// **'New version available'**
  String get updateNewVersion;

  /// No description provided for @updateLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open-source licenses'**
  String get updateLicenses;

  /// No description provided for @updateCopyVersion.
  ///
  /// In en, this message translates to:
  /// **'Copy version info'**
  String get updateCopyVersion;

  /// No description provided for @updateVersionCopied.
  ///
  /// In en, this message translates to:
  /// **'Version info copied'**
  String get updateVersionCopied;
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
