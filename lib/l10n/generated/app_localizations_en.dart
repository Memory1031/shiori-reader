// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get shelfLocal => 'Local';

  @override
  String shelfLocalFormat(String format) {
    return 'Local · $format';
  }

  @override
  String get localBookContents => 'Book contents';

  @override
  String get articleContents => 'In-volume contents';

  @override
  String get articleContentsEmpty =>
      'No recognisable section headings in this article. Use the volume list to switch articles.';

  @override
  String get articleContentsHint =>
      'Built from content headings; plain-text detection may be incomplete.';

  @override
  String get volumesTitle => 'Volumes';

  @override
  String get volumesLoad => 'Browse volumes and chapters';

  @override
  String get volumesDescription =>
      'Browse the source groups and choose a volume or chapter to read.';

  @override
  String get shelfTagline => 'Keep your favourite stories close.';

  @override
  String get discoverTagline => 'Find your next chapter.';

  @override
  String get offlineEnvironment => 'Offline demo · sample books only';

  @override
  String get historyTitle => 'Recent reading';

  @override
  String get historyClear => 'Clear this reading history';

  @override
  String get chapterFallback =>
      'The saved chapter is no longer listed. Opened a nearby chapter.';

  @override
  String get historyEmpty => 'No reading history yet.';

  @override
  String get shelfTitle => 'Bookshelf';

  @override
  String get noSources =>
      'No sources available. Saved books remain on your bookshelf.';

  @override
  String get discoverEmpty => 'No recommendations available.';

  @override
  String get importTitle => 'Import book';

  @override
  String get importPending =>
      'TXT / EPUB import and Open with Shiori are planned and still in development.';

  @override
  String get discoverUnsupported =>
      'This source has no recommendations. Use Search to find a novel.';

  @override
  String get discoverTitle => 'Discover';

  @override
  String get shelfEmpty => 'Your bookshelf is empty.';

  @override
  String get shelfLayout => 'Switch bookshelf layout';

  @override
  String get nextChapter => 'Next chapter';

  @override
  String get previousChapter => 'Previous chapter';

  @override
  String get catalogUnnamedVolume => 'Untitled volume';

  @override
  String get catalogStale => 'Saved contents may be out of date.';

  @override
  String get catalogEmpty => 'No chapters available.';

  @override
  String get detailRefresh => 'Refresh details';

  @override
  String get detailStale => 'Saved details may be out of date.';

  @override
  String get detailStart => 'Start reading';

  @override
  String get detailContinue => 'Continue reading';

  @override
  String get detailAddShelf => 'Add to bookshelf';

  @override
  String get detailRemoveShelf => 'Remove from bookshelf';

  @override
  String get detailActionsPending =>
      'Unavailable reading and bookshelf actions are still in development.';

  @override
  String get detailSynopsis => 'Synopsis';

  @override
  String get detailNoSynopsis => 'No synopsis available.';

  @override
  String get detailCover => 'Book cover';

  @override
  String get detailStatusUnknown => 'Publication status unavailable';

  @override
  String get detailStatusOngoing => 'Ongoing';

  @override
  String get detailStatusCompleted => 'Completed';

  @override
  String get detailStatusHiatus => 'On hiatus';

  @override
  String get searchKeyword => 'Title or keyword';

  @override
  String get searchInitial => 'Enter a keyword, then choose Search.';

  @override
  String get searchNoResults => 'No novels found. Try another keyword.';

  @override
  String get searchNoMore => 'All results shown';

  @override
  String get searchDraftNotice =>
      'These are previous results. Submit your edited keyword to search again.';

  @override
  String searchResultsFor(String query) {
    return 'Results for “$query”';
  }

  @override
  String get devSearchTitle => 'Offline search';

  @override
  String get devSearchHint =>
      'Search “a” to try pagination and view offline novel details.';

  @override
  String get readerImagePlaceholder => 'Illustration';

  @override
  String get hideReaderControls => 'Hide reading controls';

  @override
  String get showReaderControls => 'Show reading controls';

  @override
  String get readerExperimentAction => 'Viewport experiment';

  @override
  String get accessRestrictedMessage => 'Access to this content is restricted.';

  @override
  String get catalogTitle => 'Contents';

  @override
  String get loadMoreAction => 'Load more';

  @override
  String get openReaderAction => 'Open reader';

  @override
  String get pagedReading => 'Paged';

  @override
  String get scrollReading => 'Scroll';

  @override
  String get appTitle => 'Shiori';

  @override
  String get backAction => 'Back';

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

  @override
  String get readerSettings => 'Reading settings';

  @override
  String get readerFontSize => 'Font size';

  @override
  String get readerLineHeight => 'Line height';

  @override
  String get readerParagraphSpacing => 'Paragraph spacing';

  @override
  String get readerHorizontalPadding => 'Horizontal padding';

  @override
  String get readerThemeSystem => 'System';

  @override
  String get readerThemeLight => 'Light';

  @override
  String get readerThemeDark => 'Dark';

  @override
  String get readerSettingsFailure =>
      'Could not load or save reading settings.';

  @override
  String get readerReset => 'Reset defaults';

  @override
  String get readerProgressUnsaved =>
      'Reading progress not saved. Tap to retry.';

  @override
  String get labTitle => 'Theme Lab';

  @override
  String get labNotice => 'Offline visual prototype · no library changes';

  @override
  String get labShelf => 'Bookshelf';

  @override
  String get labDetail => 'Book details';

  @override
  String get labReader => 'Reader';

  @override
  String get labContinue => 'Continue reading';

  @override
  String get labMyBooks => 'My books';

  @override
  String get labDiscover => 'Discover';

  @override
  String get labChapter => 'Chapter 1 · The last train';

  @override
  String get labProgress => 'About 36% of this chapter';

  @override
  String get labAuthor => 'Shiori Studio';

  @override
  String get labBook1 => 'The Station Beyond Summer';

  @override
  String get labBook2 => 'Letters to the Moon';

  @override
  String get labBook3 => 'A City in the Rain';

  @override
  String get labBook4 => 'Where the Sea Begins';

  @override
  String get labLongTitle =>
      'The day we followed the last train beyond summer, and found a letter addressed to tomorrow';

  @override
  String get labSynopsis =>
      'At a station with no name, a letter arrives every summer. This time, its sender is someone who has not yet been born. A quiet journey through seaside towns, small promises, and the space between two departures.';

  @override
  String get labParagraph =>
      'The platform was quiet. Beyond the tracks, the sea held the last light of the afternoon. She opened the envelope carefully, as though the summer itself might slip out.\nThe letter began with a date from tomorrow. Somewhere behind her, a bell rang once.';

  @override
  String get labCatalog => 'Contents';

  @override
  String get labSave => 'Add to bookshelf';

  @override
  String get labSaved => 'On your bookshelf';

  @override
  String get labEmpty => 'Your next story is waiting.';

  @override
  String get labSearch => 'Find a book';

  @override
  String get labImport => 'Import a file';

  @override
  String get labNormal => 'Content';

  @override
  String get labLong => 'Long titles';

  @override
  String get labMissing => 'Missing cover';

  @override
  String get labEmptyState => 'Empty';

  @override
  String get labLoading => 'Loading';

  @override
  String get labError => 'Error';

  @override
  String get labPreviewAction =>
      'Preview only — this action will be connected in the feature task.';

  @override
  String get labSize => 'Canvas width';

  @override
  String get labScale => 'Text scale';

  @override
  String get labNight => 'Night';

  @override
  String get labIllustration => 'Original geometric cover illustration';

  @override
  String get labSettings => 'Reading settings';

  @override
  String get labFullscreen => 'Full screen preview';

  @override
  String get readerRestoreNearby =>
      'Content changed. Restored to a nearby position.';

  @override
  String get readerRestoreReadFailed =>
      'Could not read saved progress. Saving is paused; tap to retry restoration.';

  @override
  String get appAppearance => 'App appearance';

  @override
  String get appAppearanceDescription =>
      'Applies to app pages. Reading colors are set separately.';

  @override
  String get readerColors => 'Reading colors';

  @override
  String get readerPaper => 'Paper';

  @override
  String get readerWarm => 'Warm paper';

  @override
  String get readerNight => 'Night';

  @override
  String get readerControlsHint =>
      'Tap the center to show or hide controls. Tap either side or swipe horizontally to turn pages.';

  @override
  String get readerGotIt => 'Got it';

  @override
  String get readerPreviousPage => 'Previous page';

  @override
  String get readerNextPage => 'Next page';

  @override
  String readerChapterProgress(int percent) {
    return 'About $percent% of this chapter';
  }

  @override
  String get moreActions => 'More';

  @override
  String get readerProgressLabel => 'Progress';

  @override
  String get shelfGrid => 'Grid';

  @override
  String get shelfList => 'List';

  @override
  String get allChapters => 'All chapters';

  @override
  String get onlineSource => 'Online source';

  @override
  String get shelfDetails => 'Details';

  @override
  String get shelfRemove => 'Remove';

  @override
  String get launchTagline => 'Your story continues';

  @override
  String get launchLoading => 'Preparing your library…';

  @override
  String get cacheTitle => 'Cache & offline reading';

  @override
  String cacheUsage(String text, String images) {
    return 'Text & metadata $text MiB · Images $images MiB';
  }

  @override
  String get cacheOfflineHint =>
      'The articles below have cached text. Image counts reflect valid local files. Cached content may be evicted.';

  @override
  String cacheChapterStatus(int saved, int total) {
    return 'Text cached · Images $saved/$total';
  }

  @override
  String get cacheEmpty => 'No cached articles yet';

  @override
  String get cacheClearTitle => 'Clear cached content?';

  @override
  String get cacheClearExplanation =>
      'Your bookshelf, progress and settings are kept. Cleared content may need a connection when reopened.';

  @override
  String get cacheClearBook => 'Clear book cache';

  @override
  String get cacheCancel => 'Cancel';

  @override
  String get cacheClear => 'Clear cache';

  @override
  String get prefetchTitle => 'Reading cache';

  @override
  String get prefetchExplanation =>
      'Prepares this article and one article you choose. It never opens it or changes your reading progress.';

  @override
  String get prefetchCurrent => 'Cache images in this article';

  @override
  String get prefetchNext => 'Prepare the selected next article';

  @override
  String get prefetchChoose => 'Read next';

  @override
  String get prefetchNoTarget => 'No next article';

  @override
  String get prefetchPause => 'Pause';

  @override
  String get prefetchResume => 'Continue / retry';

  @override
  String get prefetchIdle => 'Not started';

  @override
  String get prefetchRunning => 'Preparing images and next reading';

  @override
  String get prefetchPaused => 'Caching paused';

  @override
  String get prefetchBudget => 'Batch limit reached. Continue manually.';

  @override
  String get prefetchPartial =>
      'Some resources could not be saved. You can retry.';

  @override
  String get prefetchComplete =>
      'Batch finished. Check saved content for offline availability.';

  @override
  String get prefetchSaveFailed => 'Could not save your choice. Please retry.';

  @override
  String get cacheFailureMessage =>
      'The cache is unavailable. Content may not have been saved locally.';

  @override
  String get cacheMissMessage =>
      'No cached content is available. Connect to the internet and try again.';

  @override
  String get importIncoming => 'A file is ready to import';

  @override
  String get importReview => 'Review';

  @override
  String get importLater => 'Later';

  @override
  String get importReceiving => 'Copying file…';

  @override
  String get importProcessing => 'Importing book…';

  @override
  String get importSuccess => 'The book has been saved.';

  @override
  String get importHint => 'Choose one TXT or EPUB file, up to 128 MiB.';

  @override
  String get importChoose => 'Choose file';

  @override
  String get importStart => 'Import';

  @override
  String get importRetry => 'Retry';

  @override
  String get importCancel => 'Cancel';

  @override
  String get importDone => 'Done';

  @override
  String get importTooLarge =>
      'The file exceeds 128 MiB. Choose a smaller file.';

  @override
  String get importMultiple =>
      'Only one file can be received at a time. Select again.';

  @override
  String get importBusy =>
      'Handle the pending file first, then open or share this file again.';

  @override
  String get importUnsupported =>
      'Choose a TXT or EPUB file. Web links cannot be imported.';

  @override
  String get importInvalid =>
      'The file is empty or its contents do not match the format.';

  @override
  String get importParserUnavailable =>
      'This version cannot parse this format yet. Nothing was imported. You can cancel and choose the file again later.';

  @override
  String get importStorage =>
      'The file could not be saved. Check available space and retry.';

  @override
  String get importCancelled => 'Import cancelled. The book was not saved.';

  @override
  String get importUnreadable =>
      'The file could not be read. Check access and choose it again.';

  @override
  String get importEncodingHint =>
      'Check the previews and choose the encoding that displays the text correctly.';

  @override
  String get importEncodingAuto => 'Text encoding: Automatic';

  @override
  String get importEncodingInvalid =>
      'The entire file could not be decoded with this encoding. Choose another encoding or check the original.';

  @override
  String get importDrm =>
      'This EPUB contains protected or encrypted content and cannot be imported.';

  @override
  String get importFixedLayout =>
      'Fixed-layout EPUB is not supported. Use a reflowable edition.';

  @override
  String get importParseLimit =>
      'Parsing limits exceeded: TXT 16 MiB, EPUB 64 MiB. Oversized chapters, images, or expanded content are also unsupported.';

  @override
  String get importEpubSupport =>
      'Supports ordinary reflowable EPUB text and images. Styling is simplified; scripts, external resources, and custom fonts are not loaded. Missing images keep a placeholder.';

  @override
  String get localBooksTitle => 'Local files';

  @override
  String get localBooksHint =>
      'Manage imported books. Removing a local book deletes its in-app files and reading progress. The original external file is unaffected.';

  @override
  String get localBooksEmpty => 'No local books imported yet.';

  @override
  String get localDeleteTitle => 'Delete local book?';

  @override
  String localDeleteMessage(String title) {
    return 'Delete the app-owned original, text, images, shelf entry, and reading progress for “$title”. The external original is unaffected. This cannot be undone.';
  }

  @override
  String get localDeleteConfirm => 'Delete book and progress';

  @override
  String get localDeleted => 'Local book and reading progress deleted.';

  @override
  String get localCleanupPending =>
      'Book and progress removed. Remaining files will be cleaned up at the next launch.';

  @override
  String get localShelfAdded => 'Added to bookshelf.';

  @override
  String get localReadNow => 'Read now';

  @override
  String get appAccentTitle => 'Accent color';

  @override
  String get appAccentTeal => 'Soft teal';

  @override
  String get appAccentBlueGrey => 'Blue grey';

  @override
  String get appAccentWarmBrown => 'Warm brown';

  @override
  String get appAccentSoftPink => 'Soft pink';

  @override
  String get readerChapterLoadFailed =>
      'Could not open the chapter. Your current page is still available.';

  @override
  String get localReparse => 'Reparse';

  @override
  String get localReparseConfirm =>
      'Reparse the saved original and restore your reading position where possible. Failure or cancellation keeps the previous content.';

  @override
  String get localReparseDone =>
      'Reparsed. Your reading position is preserved.';

  @override
  String get localReparseApproximate =>
      'Reparsed. Restored a nearby position; please check the current text.';

  @override
  String get localReparseReaderClosed =>
      'This book is being reparsed. Return to the library and reopen it.';
}
