// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get readerImagePreview => 'View image';

  @override
  String readerFootnote(String number) {
    return 'Footnote $number';
  }

  @override
  String get localBookContents => 'Book contents';

  @override
  String get localNavigationCover => 'Cover';

  @override
  String get localNavigationTitlePage => 'Title page';

  @override
  String get localNavigationCredits => 'Credits';

  @override
  String get localNavigationSynopsis => 'Synopsis';

  @override
  String get localNavigationAuthor => 'About the author';

  @override
  String get localNavigationIllustrator => 'About the illustrator';

  @override
  String get localNavigationIllustrations => 'Illustrations';

  @override
  String get localNavigationContents => 'Contents';

  @override
  String get localNavigationPreface => 'Preface';

  @override
  String get localNavigationDedication => 'Dedication';

  @override
  String get articleContents => 'In-volume contents';

  @override
  String get articleContentsEmpty =>
      'No in-volume contents. Use the volume list instead.';

  @override
  String get volumesTitle => 'Volumes';

  @override
  String get volumesLoad => 'Browse volumes and chapters';

  @override
  String get volumesDescription =>
      'Choose a volume or chapter to start reading.';

  @override
  String get discoverTagline => 'Find your next chapter.';

  @override
  String get offlineEnvironment => 'Offline demo · sample books only';

  @override
  String get historyTitle => 'Reading history';

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
  String get homeContinueAction => 'Resume';

  @override
  String get detailAddShelf => 'Add to bookshelf';

  @override
  String get detailRemoveShelf => 'Remove from bookshelf';

  @override
  String get shelfDelete => 'Delete';

  @override
  String get onlineRemoveConfirm => 'Remove';

  @override
  String get localDeleteBook => 'Delete local book';

  @override
  String get onlineRemoveMessage =>
      'Remove this book from your bookshelf and clear its cache, progress and bookmarks. Reading will restart from the beginning.';

  @override
  String get onlineBookRemoved =>
      'Book removed. Its cache, progress and bookmarks were cleared.';

  @override
  String get bookDeleteAndRemove => 'Remove';

  @override
  String get detailActionsPending =>
      'Unavailable reading and bookshelf actions are still in development.';

  @override
  String get detailSynopsis => 'Synopsis';

  @override
  String get detailOnShelf => 'In bookshelf';

  @override
  String get detailShowMore => 'Show more';

  @override
  String get detailShowLess => 'Show less';

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
      'Your keywords have changed. Choose Search to update the results.';

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
  String get readerAudioPlay => 'Play audio';

  @override
  String get readerAudioPause => 'Pause audio';

  @override
  String get readerAudioUnavailable => 'Audio unavailable';

  @override
  String get readerAudioFailed => 'Audio playback failed. Tap to retry.';

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
  String get catalogRefresh => 'Refresh contents';

  @override
  String catalogLastFetched(String time) {
    return 'Last fetched: $time';
  }

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
  String get appClosing => 'Closing Shiori…';

  @override
  String get backAction => 'Back';

  @override
  String get connectionFailureMessage =>
      'Unable to connect. Check your network and try again.';

  @override
  String get databaseFailureMessage =>
      'Could not read or save local data. The operation did not finish.';

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
      'Could not read the content returned by the source.';

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
      'Could not access the source. Try again later.';

  @override
  String get sourceUnavailableMessage =>
      'The content service is temporarily unavailable. Try again later.';

  @override
  String get tooLargeMessage => 'This content is too large to process.';

  @override
  String get unsupportedMessage => 'This feature is not supported yet.';

  @override
  String get unrecognizedSourceResponseMessage =>
      'The source could not complete this request.';

  @override
  String get readerSettings => 'Reading settings';

  @override
  String get readerFontSize => 'Font size';

  @override
  String get readerLineHeight => 'Line height';

  @override
  String get readerParagraphSpacing => 'Paragraph spacing';

  @override
  String get readerHorizontalPadding => 'Side margins';

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
  String get readerProgressNotSaved => 'Not saved';

  @override
  String get readerProgressSavingPaused => 'Saving paused';

  @override
  String get readerRetrySaveProgress => 'Retry saving progress';

  @override
  String get readerRetryReadProgress => 'Retry reading progress';

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
  String get labProgress => 'Chapter 36%';

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
      'Could not load saved progress. Saving is paused. Tap to retry.';

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
  String get readerPageTurn => 'Page turn';

  @override
  String get readerPageTurnCurl => 'Curl';

  @override
  String get readerPageTurnCover => 'Cover';

  @override
  String get readerPageTurnSlide => 'Slide';

  @override
  String get readerPageTurnNone => 'None';

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
  String readerChapterProgress(String percent) {
    return 'Chapter $percent%';
  }

  @override
  String get moreActions => 'More';

  @override
  String get readerProgressLabel => 'Progress';

  @override
  String readerShortcutTooltip(String action, String shortcut) {
    return '$action ($shortcut)';
  }

  @override
  String get shelfGrid => 'Grid';

  @override
  String get shelfList => 'List';

  @override
  String get homeShelf => 'My bookshelf';

  @override
  String get homeNavigation => 'Main navigation';

  @override
  String get homeSettingsTitle => 'Settings';

  @override
  String get homeSettingsAppearance => 'Appearance';

  @override
  String get homeSettingsStorage => 'Books and storage';

  @override
  String get homeSettingsAbout => 'About';

  @override
  String get homeSettingsAppearanceDescription =>
      'Theme and display preferences';

  @override
  String get homeSettingsLocalBooksDescription => 'Manage imported books';

  @override
  String get homeSettingsOfflineDescription => 'Manage cached reading content';

  @override
  String get homeSettingsAboutDescription => 'Version details and app updates';

  @override
  String get allChapters => 'All chapters';

  @override
  String get onlineSource => 'Online source';

  @override
  String get shelfDetails => 'Details';

  @override
  String get shelfRemove => 'Remove';

  @override
  String shelfBookCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count books',
      one: '1 book',
    );
    return '$_temp0';
  }

  @override
  String get launchTagline => 'Your story continues';

  @override
  String get launchLoading => 'Preparing your library…';

  @override
  String get cacheTitle => 'Offline content';

  @override
  String cacheUsage(String text, String images) {
    return 'Text and book details $text MiB · Images $images MiB';
  }

  @override
  String get cacheOfflineHint =>
      'Read cached online chapters offline. Cached content may be cleared to free up space.';

  @override
  String cacheChapterStatus(int saved, int total) {
    return 'Text cached · Images $saved/$total';
  }

  @override
  String get cacheStored => 'Cached storage';

  @override
  String get cacheBooks => 'Cached books';

  @override
  String cacheCounts(int books, int chapters) {
    String _temp0 = intl.Intl.pluralLogic(
      books,
      locale: localeName,
      other: '$books books',
      one: '1 book',
    );
    String _temp1 = intl.Intl.pluralLogic(
      chapters,
      locale: localeName,
      other: '$chapters chapters',
      one: '1 chapter',
    );
    return '$_temp0 · $_temp1';
  }

  @override
  String cacheBookImages(int chapters, int saved, int total) {
    String _temp0 = intl.Intl.pluralLogic(
      chapters,
      locale: localeName,
      other: '$chapters chapters',
      one: '1 chapter',
    );
    return '$_temp0 · Images $saved/$total';
  }

  @override
  String cacheBookNoImages(int chapters) {
    String _temp0 = intl.Intl.pluralLogic(
      chapters,
      locale: localeName,
      other: '$chapters chapters',
      one: '1 chapter',
    );
    return '$_temp0 · No illustrations';
  }

  @override
  String get cacheNoChapters => 'Metadata only · No offline chapters';

  @override
  String get cacheClearAll => 'Clear all cache';

  @override
  String get cacheEmpty => 'No cached chapters yet';

  @override
  String get cacheClearTitle => 'Clear all cache?';

  @override
  String get cacheClearBookTitle => 'Clear this book\'s cache?';

  @override
  String get cacheUnnamedBook => 'This book';

  @override
  String cacheClearBookCount(int chapters) {
    String _temp0 = intl.Intl.pluralLogic(
      chapters,
      locale: localeName,
      other: '$chapters chapters',
      one: '1 chapter',
      zero: '0 chapters',
    );
    return 'Currently cached: $_temp0.';
  }

  @override
  String cacheClearAllCount(int books, int chapters) {
    String _temp0 = intl.Intl.pluralLogic(
      books,
      locale: localeName,
      other: '$books books',
      one: '1 book',
      zero: '0 books',
    );
    String _temp1 = intl.Intl.pluralLogic(
      chapters,
      locale: localeName,
      other: '$chapters chapters',
      one: '1 chapter',
      zero: '0 chapters',
    );
    return '$_temp0 and $_temp1 cached.';
  }

  @override
  String get cacheClearAllExplanation =>
      'Clear cached chapters, contents, book details and images. Keep your bookshelf, progress and settings. Reopening cleared content may need an internet connection.';

  @override
  String get cacheClearExplanation =>
      'Keep your bookshelf, progress and settings. Reopening cleared content may need an internet connection.';

  @override
  String get cacheClearBook => 'Clear book cache';

  @override
  String get cacheCancel => 'Cancel';

  @override
  String get cacheClear => 'Clear cache';

  @override
  String get prefetchTitle => 'Reading cache';

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
  String get prefetchRunning => 'Caching images and the next article';

  @override
  String get prefetchPaused => 'Caching paused';

  @override
  String get prefetchBudget =>
      'Cache limit reached. Continue to save more content.';

  @override
  String get prefetchPartial =>
      'Some content could not be cached. Retry to save it.';

  @override
  String get prefetchComplete =>
      'Caching finished. View saved chapters in Offline content.';

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
  String get importCancel => 'Cancel';

  @override
  String get importReceiving => 'Copying file…';

  @override
  String get importProcessing => 'Importing book…';

  @override
  String get importFileReading => 'Reading file…';

  @override
  String get importBookProcessing => 'Processing book…';

  @override
  String get importSuccess => 'Book imported.';

  @override
  String get importHint => 'Supports TXT (≤16 MiB) and EPUB (≤64 MiB).';

  @override
  String get importChoose => 'Choose file';

  @override
  String get importStart => 'Import';

  @override
  String get importRetry => 'Retry';

  @override
  String get importDone => 'Done';

  @override
  String get importImportAll => 'Import all';

  @override
  String get importRetryFailed => 'Retry failed';

  @override
  String get importResume => 'Continue importing';

  @override
  String get importStop => 'Stop importing';

  @override
  String get importStopReceiving => 'Stop receiving';

  @override
  String get importDiscardFiles => 'Discard files';

  @override
  String get importDiscardRemaining => 'Discard remaining files';

  @override
  String get importDiscardTitle => 'Discard pending files?';

  @override
  String get importDiscardRemainingTitle => 'Discard remaining files?';

  @override
  String get importDiscardMessage =>
      'This will remove Shiori’s temporary import copies. Original files and already imported books will not be affected.';

  @override
  String get importKeepFiles => 'Keep files';

  @override
  String get importWaiting => 'Waiting';

  @override
  String get importItemImporting => 'Importing';

  @override
  String get importItemImported => 'Imported';

  @override
  String get importAlreadyExists =>
      'Already in your library. No duplicate was created.';

  @override
  String get importItemExisting => 'Already exists; no duplicate created';

  @override
  String importBatchReady(int count) {
    return 'Ready to import $count books';
  }

  @override
  String importBatchProgress(int current, int total) {
    return 'Importing $current of $total';
  }

  @override
  String get importBatchComplete => 'Import finished';

  @override
  String importBatchCreated(int count) {
    return '$count added';
  }

  @override
  String get importBatchStopped => 'Import stopped';

  @override
  String importBatchExisting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count already exist',
      one: '1 already exists',
    );
    return '$_temp0';
  }

  @override
  String importBatchFailed(int count) {
    return '$count failed';
  }

  @override
  String importBatchAllExisting(int count) {
    return '$count already exist. No books were added.';
  }

  @override
  String importBatchRemaining(int count) {
    return '$count not imported yet';
  }

  @override
  String get importTooLarge =>
      'The file exceeds 128 MiB. Choose a smaller file.';

  @override
  String get importBatchLimit =>
      'The selection exceeds the batch import limit. Choose fewer or smaller files.';

  @override
  String get importMultiple =>
      'Only one file can be received at a time. Select again.';

  @override
  String get importBusy =>
      'Receiving other files. Try again shortly, or review pending imports.';

  @override
  String get importUnsupported =>
      'Choose a TXT or EPUB file. Web links cannot be imported.';

  @override
  String get importInvalid =>
      'The file is empty or its contents do not match the format.';

  @override
  String get importParserUnavailable =>
      'This version cannot read this format. The file was not imported.';

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
      'Could not read the entire file using this encoding. Choose another encoding or check the original file.';

  @override
  String get importDrm =>
      'This EPUB contains protected or encrypted content and cannot be imported.';

  @override
  String get importFixedLayout =>
      'Fixed-layout EPUB is not supported. Use a reflowable edition.';

  @override
  String get importParseLimit =>
      'The book file or its contents are too large to import.';

  @override
  String get importParseStructureLimit =>
      'This TXT has too many paragraphs or chapters. Split it into volumes before importing.';

  @override
  String get importParseTimeout =>
      'Processing this book took too long and was stopped. Try again, or split it into volumes before importing.';

  @override
  String get importEpubSupport => 'Supports EPUB text and images.';

  @override
  String localBooksCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count books',
      one: '1 book',
    );
    return '$_temp0';
  }

  @override
  String get localBooksSubtitle =>
      'Your imported books, ready to read offline.';

  @override
  String localBooksImportedOn(String date) {
    return 'Imported $date';
  }

  @override
  String get localBooksTitle => 'Local files';

  @override
  String get localBooksHint => 'Manage your imported EPUB and TXT books.';

  @override
  String get localBooksEmpty => 'No local books imported yet.';

  @override
  String get localDeleteTitle => 'Delete local book?';

  @override
  String localDeleteMessage(String title) {
    return 'Permanently delete the imported copy, progress and bookmarks for “$title”. Keep the original file.';
  }

  @override
  String get localDeleteConfirm => 'Delete book and progress';

  @override
  String get localDeleted => 'Local book and reading progress deleted.';

  @override
  String get localCleanupPending =>
      'Book and progress removed. Remaining files will be cleaned up at the next launch.';

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
  String get localReparseAll => 'Reparse all';

  @override
  String get localFilterAll => 'All';

  @override
  String localReparseAllConfirm(int count) {
    return 'Reparse all $count local books one at a time and restore reading positions where possible. Failures keep the previous content and do not stop other books. You can stop at any time.';
  }

  @override
  String localReparseAllProgress(int current, int total, String title) {
    return 'Reparsing $current of $total: $title';
  }

  @override
  String get localReparseStop => 'Stop reparsing';

  @override
  String localReparseAllSummary(int succeeded, int failed, int remaining) {
    return 'Succeeded: $succeeded · Failed: $failed · Not processed: $remaining';
  }

  @override
  String localReparseAllApproximate(int count) {
    return 'Restored nearby positions for $count books. Please check them when you resume reading.';
  }

  @override
  String get localReparse => 'Reparse';

  @override
  String get localReparseConfirm =>
      'Reparse the saved original, keeping your reading position where possible. Keep the previous content if this fails or is cancelled.';

  @override
  String get localReparseDone =>
      'Reparsed. Your reading position is preserved.';

  @override
  String get localReparseApproximate =>
      'Reparsed. Restored a nearby position; please check the current text.';

  @override
  String get localReparseReaderClosed =>
      'This book is being reparsed. Return to the library and reopen it.';

  @override
  String get readerLinks => 'Chapter notes';

  @override
  String get readerNotesFootnotes => 'Notes';

  @override
  String get readerNotesLinks => 'Links';

  @override
  String get readerLinkHere => 'In this chapter';

  @override
  String get readerLinkElsewhere => 'Elsewhere in this book';

  @override
  String get readerPreviousLocation => 'Back to previous location';

  @override
  String get readerLinkReturn => 'Return to reading';

  @override
  String get readerLinkUnavailable =>
      'Cannot open this link. Only links to documents or positions within this book are supported.';

  @override
  String get readerLinkDepth =>
      'Too many book links are open. Return to the previous location first.';

  @override
  String get readerMarginVeryNarrow => 'Narrowest';

  @override
  String get readerMarginNarrow => 'Narrow';

  @override
  String get readerMarginMedium => 'Medium';

  @override
  String get readerMarginWide => 'Wide';

  @override
  String get readerMarginVeryWide => 'Widest';

  @override
  String get readerFollowSystem => 'Follow system';

  @override
  String get readerFollowSystemHint =>
      'Switches to Night while the system is dark';

  @override
  String get readerUndo => 'Undo';

  @override
  String readerDecrease(String label) {
    return 'Decrease $label';
  }

  @override
  String readerIncrease(String label) {
    return 'Increase $label';
  }

  @override
  String get bookFinished => 'Finished';

  @override
  String get bookCaughtUp => 'Caught up';

  @override
  String get bookCurrentEnd => 'End of available chapters';

  @override
  String bookProgressPercent(String percent) {
    return 'Reading progress $percent%';
  }

  @override
  String readerChapterPercent(String percent) {
    return 'Chapter $percent%';
  }

  @override
  String get readerReadingProgress => 'Reading progress';

  @override
  String get readerBackToShelf => 'Back to bookshelf';

  @override
  String get readerViewCatalog => 'View contents';

  @override
  String get readerRestart => 'Read again';

  @override
  String get bookOnline => 'Online';

  @override
  String get updateTitle => 'About & updates';

  @override
  String updateInstalled(String version) {
    return 'Installed: $version';
  }

  @override
  String get updateDevelopment =>
      'Development builds do not check for release updates.';

  @override
  String get updateUnsupported =>
      'Update using your original installation method. For a self-signed IPA, sign and install the new version.';

  @override
  String get updateInvalidIdentity =>
      'Unable to verify the installed version. Update checks are unavailable.';

  @override
  String get updateAutomatic => 'Check automatically';

  @override
  String get updateAutomaticHint =>
      'You choose when to download and install updates.';

  @override
  String get updateCheckOnlyAutomaticHint =>
      'Notify me when a new release is available.';

  @override
  String get updateManualInstallHint =>
      'Install the new version using your original signing method, such as AltStore or another signing tool.';

  @override
  String get updateOpenReleasePage => 'Open release page';

  @override
  String get updateTestFlightHint =>
      'This version updates through TestFlight. Check TestFlight for available builds.';

  @override
  String get updateChannel => 'Update channel';

  @override
  String get updateStable => 'Stable';

  @override
  String get updateBeta => 'Beta';

  @override
  String get updateChannelHint =>
      'Switching channels will not downgrade the app.';

  @override
  String get updateNeverChecked => 'Not checked yet';

  @override
  String updateLastChecked(String time) {
    return 'Last checked: $time';
  }

  @override
  String get updateCheck => 'Check for updates';

  @override
  String get updateCancel => 'Cancel';

  @override
  String get updateChecking => 'Checking…';

  @override
  String get updateNetworkError =>
      'Could not connect. Check your connection and try again.';

  @override
  String updateRateLimited(String time) {
    return 'Request limit reached. Try again after $time.';
  }

  @override
  String get updateIncomplete =>
      'Release files are incomplete. Check again later.';

  @override
  String get updateVerificationError =>
      'Update verification failed. Check for updates again.';

  @override
  String get updatePackageInvalid =>
      'The downloaded package is no longer valid. Download it again.';

  @override
  String get updateStorageError =>
      'Could not access update files. Check free space and folder permissions, then retry.';

  @override
  String get updateCancelled => 'Cancelled';

  @override
  String get updateNoUpdate => 'No newer release is available on this channel.';

  @override
  String updateSize(String size) {
    return 'Download size: $size MB';
  }

  @override
  String updateProgress(int percent) {
    return '$percent% downloaded';
  }

  @override
  String get updateDownload => 'Download update';

  @override
  String get updateVerifying => 'Verifying update package…';

  @override
  String get updateDownloaded =>
      'Download verified. Visit the release page for installation instructions.';

  @override
  String get updateExpandNotes => 'Read full notes';

  @override
  String get updateCollapseNotes => 'Collapse notes';

  @override
  String get updateLinkCopied => 'Could not open the browser. Link copied.';

  @override
  String updateAvailable(String version) {
    return 'Update available: $version';
  }

  @override
  String get updateView => 'View';

  @override
  String get updateInstall => 'Install update';

  @override
  String get updateInstallHint =>
      'Shiori will close to install the update. Your bookshelf, reading position and settings will be kept.';

  @override
  String get updateInstallPermission =>
      'Allow Shiori to install app updates. Return to this page after granting permission, then tap Install update.';

  @override
  String get updateInstallSettings => 'Open installation settings';

  @override
  String get updateInstalling =>
      'Waiting for the system installer. Confirm or cancel in the system dialog.';

  @override
  String get updateInstallCancelled =>
      'Installation cancelled. The downloaded package is kept for retry.';

  @override
  String get updateInstallFailed =>
      'The system could not complete installation. Check free space and installation permission, then retry.';

  @override
  String get updateRestartInstall => 'Restart to update';

  @override
  String get updateInstallFailedMacOS =>
      'The update did not finish. Retry, or download the complete app from GitHub and replace Shiori. Reading data is stored separately.';

  @override
  String get updateInstallLocationMacOS =>
      'Updates are unavailable at this location. Quit Shiori, move the complete app to a writable Applications folder (such as ~/Applications), then open it again.';

  @override
  String get updateInstallHintWindows =>
      'Shiori will close, update its program files and restart. Your bookshelf, reading position and settings will be kept.';

  @override
  String get updateRestarting =>
      'Closing Shiori to install the update. It will start again when installation finishes.';

  @override
  String get updateInstallFailedWindows =>
      'Update did not finish. Retry, or download the full package from the release page: run the EXE for an installed edition, or extract the ZIP for a portable edition. Reading data is stored separately.';

  @override
  String get updateInstallInstances =>
      'Close other Shiori windows, then retry.';

  @override
  String get updateInstallLocation =>
      'Cannot update in this folder. For the installed edition, reinstall from the release page. For the portable edition, extract the full ZIP to a writable folder on a local drive.';

  @override
  String get updateWorkspaceConflict =>
      'The .update folder beside Shiori cannot be used safely. If it contains an unfinished update or backup, complete recovery first. Alternatively, quit Shiori, keep and move that folder aside, then manually install the complete new version. Do not delete its contents.';

  @override
  String get updateInstallBusy =>
      'Wait for the current operation to finish before installing.';

  @override
  String get updateReturnToLibrary =>
      'Return to your bookshelf and finish importing, then open About & updates.';

  @override
  String get updateSection => 'Updates';

  @override
  String get updateProject => 'Project';

  @override
  String get updateChooseChannel => 'Choose update channel';

  @override
  String get updateStableHint => 'Receive stable releases only';

  @override
  String get updateBetaHint => 'Receive beta and stable releases';

  @override
  String get updateNewVersion => 'New version available';

  @override
  String get updateLicenses => 'Open-source licenses';

  @override
  String get updateCopyVersion => 'Copy version info';

  @override
  String get updateVersionCopied => 'Version info copied';

  @override
  String get imageExportSave => 'Save original image';

  @override
  String get imageExportSaving => 'Saving image…';

  @override
  String get imageExportSavedPhotos => 'Saved to Photos / Gallery';

  @override
  String get imageExportSavedFile => 'Saved to file';

  @override
  String get imageExportPermissionDenied =>
      'Photo access was denied. You can allow adding photos in system settings.';

  @override
  String get imageExportUnsupported =>
      'Photos / Gallery does not support this original format. You can save it as a file.';

  @override
  String get imageExportAsFile => 'Save as file';

  @override
  String get imageExportInvalidFormat =>
      'The original image format could not be verified. Keep the original file extension when saving.';

  @override
  String get imageExportStorageFailure =>
      'Could not write the image. Check available space and the save location, then retry.';

  @override
  String get imageExportSourceUnavailable =>
      'The original image is unavailable. Check that it is downloaded, then retry.';

  @override
  String get imageExportExists =>
      'A file already exists at this location. Please choose a different name.';

  @override
  String get imageExportUnavailable =>
      'Image saving is currently unavailable. Please try again.';

  @override
  String importPendingCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count files awaiting import',
      one: '1 file awaiting import',
    );
    return '$_temp0';
  }

  @override
  String get importInboxFull =>
      'The inbox is full (64 files / 512 MiB). Import or discard pending files in Shiori, then share again.';

  @override
  String get importPublicationUncertain =>
      'Files may have been received. Check pending files in Shiori before sharing again.';

  @override
  String get importLater => 'Later';

  @override
  String get readerChapterProgressLoading => 'Chapter progress loading';

  @override
  String get readerCurrentDocument => 'Current document';

  @override
  String readerDocumentPercent(String percent) {
    return 'Document $percent%';
  }

  @override
  String get bookMultiSelect => 'Multi-select';

  @override
  String bookSelectedCount(int count) {
    return '$count selected';
  }

  @override
  String get bookSelectAll => 'Select all';

  @override
  String get bookDeselectAll => 'Deselect all';

  @override
  String get bookRemoveSelected => 'Remove';

  @override
  String get bookDeleteSelected => 'Delete selected';

  @override
  String bookReparseSelected(int count) {
    return 'Reparse ($count)';
  }

  @override
  String get bookNoReparse =>
      'Only available local EPUB and TXT books can be reparsed.';

  @override
  String bookReparseAction(int count) {
    return 'Reparse ($count)';
  }

  @override
  String bookReparseAvailable(int count) {
    return '$count selected books can be reparsed.';
  }

  @override
  String get bookNoSelection => 'Select books first.';

  @override
  String bookReparseSelectedConfirm(int count, int excluded) {
    String _temp0 = intl.Intl.pluralLogic(
      excluded,
      locale: localeName,
      other: '\n$excluded other selected books will be skipped.',
      zero: '',
    );
    return 'Reparse $count selected local books. Keep the previous content if parsing fails.$_temp0';
  }

  @override
  String get bookBatchRemoveTitle => 'Remove selected books';

  @override
  String get bookBatchLocalTitle => 'Delete local books';

  @override
  String get bookBatchOnlineTitle => 'Remove from bookshelf';

  @override
  String bookBatchRemoveConfirm(int count) {
    return 'Remove these $count selected books?';
  }

  @override
  String bookBatchOnline(int count) {
    return '$count online books: remove from bookshelf and clear cache, progress and bookmarks. Read again from the beginning.';
  }

  @override
  String bookBatchLocal(int count) {
    return '$count local books: permanently delete imported copies, progress and bookmarks. Keep original files.';
  }

  @override
  String bookBatchProgress(int index, int total, String title) {
    return '$index / $total · $title';
  }

  @override
  String bookBatchSummary(
    int success,
    int failed,
    int unprocessed,
    int missing,
    int excluded,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      failed,
      locale: localeName,
      other: '\nFailed: $failed',
      zero: '',
    );
    String _temp1 = intl.Intl.pluralLogic(
      unprocessed,
      locale: localeName,
      other: '\nNot processed: $unprocessed',
      zero: '',
    );
    String _temp2 = intl.Intl.pluralLogic(
      missing,
      locale: localeName,
      other: '\nNo longer present: $missing',
      zero: '',
    );
    String _temp3 = intl.Intl.pluralLogic(
      excluded,
      locale: localeName,
      other: '\nExcluded: $excluded',
      zero: '',
    );
    return '$success books completed$_temp0$_temp1$_temp2$_temp3';
  }

  @override
  String get bookBatchResults => 'Batch results';

  @override
  String bookBatchSuccessDetails(int count) {
    return 'View completed books ($count)';
  }

  @override
  String get bookBatchRemaining =>
      'Failed, unprocessed and excluded books remain selected for your next action.';

  @override
  String get bookBatchSucceeded => 'Completed';

  @override
  String get bookBatchMissing => 'Skipped: book no longer exists';

  @override
  String get bookBatchUnprocessed => 'Not processed after stopping';

  @override
  String get bookBatchInapplicable => 'Excluded from reparse';

  @override
  String bookToggleSelection(String title) {
    return 'Select or deselect $title';
  }

  @override
  String get bookReparseCleanupPending =>
      'Updated book saved. Remaining old files will be cleaned up at the next launch.';

  @override
  String localAutoReparseUnfinished(int count) {
    return '$count books could not update automatically';
  }

  @override
  String get localAutoReparseApproximate =>
      'Skipped: could not preserve the exact reading position';

  @override
  String get localAutoReparseEncoding => 'Skipped: TXT encoding is uncertain';

  @override
  String get localAutoReparseOriginal => 'Failed: original file is damaged';

  @override
  String get localAutoReparseStorage => 'Deferred: storage space is low';

  @override
  String get localAutoReparseWrite =>
      'Waiting to retry: file read or write failed';

  @override
  String get localAutoReparseInterrupted =>
      'Waiting to retry: the previous update was interrupted';

  @override
  String get localAutoReparseTimeout => 'Waiting to retry: parsing timed out';

  @override
  String get localAutoReparseOther =>
      'Automatic update failed; manual reparsing is available';

  @override
  String get readerSearchBook => 'Search this book';

  @override
  String get readerSearchHint => 'Enter a word or phrase, then search';

  @override
  String get readerSearchSubmit => 'Search';

  @override
  String get readerSearchLoading => 'Searching…';

  @override
  String get readerSearchPaused =>
      'Search paused. You can still view the matches found.';

  @override
  String get readerSearchTooLong =>
      'Search text is too long. Please shorten it and try again.';

  @override
  String get readerSearchInvalid => 'Use another word or phrase.';

  @override
  String get readerSearchExpired =>
      'The book changed or was removed. Search again.';

  @override
  String get readerSearchFailed => 'Search did not finish. Search again.';

  @override
  String get readerSearchEmpty => 'No matching text found.';

  @override
  String readerSearchFound(int count) {
    return 'Found $count matches so far';
  }

  @override
  String readerSearchTotal(int count) {
    return '$count matches';
  }

  @override
  String readerSearchDraft(String query) {
    return 'Showing results for “$query”';
  }

  @override
  String get readerSearchResume => 'Continue search';

  @override
  String get readerSearchRetry => 'Search again';

  @override
  String get readerSearchEnd => 'All results shown';

  @override
  String get readerSearchRebuilding => 'Restore these results';

  @override
  String get readerSearchFootnote => 'Note';

  @override
  String get readerSearchReturn => 'Back to search start';

  @override
  String get readerSearchDocument =>
      'Opened the document containing the match. This page does not support exact positioning or highlighting.';

  @override
  String get readerSearchClear => 'Clear search';

  @override
  String get readerBookmarkAdd => 'Add bookmark';

  @override
  String get readerBookmarkRemove => 'Remove bookmark';

  @override
  String get readerBookmarks => 'My bookmarks';

  @override
  String get bookmarkAdded => 'Bookmark added';

  @override
  String get bookmarkRemoved => 'Bookmark removed';

  @override
  String get bookmarkEmpty => 'No bookmarks yet. Add one from the reader menu.';

  @override
  String get bookmarkDelete => 'Delete bookmark';

  @override
  String get bookmarkPositionUnavailable =>
      'Cannot locate the saved position after the content changed. Your bookmark is kept.';

  @override
  String get bookmarkUnsupported => 'Bookmarks are not supported on this page.';

  @override
  String get bookmarkLoadFailed =>
      'Could not load bookmarks. Close and try again.';

  @override
  String get bookmarkSaveFailed =>
      'Could not save the bookmark. Please try again.';

  @override
  String get bookmarkOpenFailed =>
      'Could not open this bookmark. Please try again later.';

  @override
  String get bookmarkChanged => 'Bookmarks have changed. Please try again.';

  @override
  String get readerBookmarkReturn => 'Back to previous reading position';

  @override
  String get statisticsTitle => 'Reading statistics';

  @override
  String get statisticsTab => 'Statistics';

  @override
  String get statisticsManage => 'Manage records';

  @override
  String get statisticsNoticeTitle => 'Reading statistics are on';

  @override
  String get statisticsNoticeBody =>
      'Reading time stays on this device. You can pause or clear it at any time.';

  @override
  String get statisticsToday => 'Today’s reading';

  @override
  String get statisticsLifetime => 'Total reading';

  @override
  String get statisticsDuration => 'Reading time';

  @override
  String get statisticsSeven => '7 days';

  @override
  String get statisticsThirty => '30 days';

  @override
  String get statisticsYear => '12 months';

  @override
  String get statisticsBooks => 'Read in this period';

  @override
  String statisticsShowAllBooks(int count) {
    return 'Show all $count books';
  }

  @override
  String get statisticsAnonymous => 'Removed books';

  @override
  String get statisticsAnonymousHint => 'Only total reading time is retained';

  @override
  String get statisticsMissingBook => 'Book details unavailable';

  @override
  String get statisticsLocalOnly => 'Reading records stay on this device.';

  @override
  String get statisticsEmpty =>
      'Start reading to see today’s reading time here.';

  @override
  String get statisticsPeriodEmpty => 'No reading recorded in this period.';

  @override
  String get statisticsPaused => 'Recording is paused.';

  @override
  String get statisticsEnable => 'Resume recording';

  @override
  String get statisticsRecording => 'Record reading time';

  @override
  String get statisticsPauseHint =>
      'Pause new records and keep existing statistics.';

  @override
  String get statisticsRetention =>
      'Removing a book keeps only its total reading time.';

  @override
  String get statisticsClear => 'Clear statistics';

  @override
  String get statisticsClearConfirm => 'Clear statistics?';

  @override
  String get statisticsClearBody =>
      'Clear reading time and per-book statistics without affecting your bookshelf, reading position or bookmarks.';

  @override
  String get statisticsClearEnabled =>
      'New reading time will continue to be recorded.';

  @override
  String get statisticsError =>
      'Reading statistics are temporarily unavailable. Please retry.';

  @override
  String get statisticsUnderMinute => 'Less than 1 minute';

  @override
  String get statisticsMinutesUnit => 'min';

  @override
  String get statisticsHoursUnit => 'h';

  @override
  String get statisticsChart =>
      'Reading time chart. Adjust left or right to read each date and duration';

  @override
  String get statisticsUntilToday => 'Through today';

  @override
  String get statisticsTotal => 'Total';

  @override
  String statisticsMinutes(String count) {
    return '$count min';
  }

  @override
  String statisticsHours(String count) {
    return '$count h';
  }

  @override
  String statisticsHoursMinutes(String hours, String minutes) {
    return '$hours h $minutes min';
  }

  @override
  String get readerTxtBlankLines => 'TXT blank lines';

  @override
  String get readerTxtBlankLinesMerge => 'Use spacing';

  @override
  String get readerTxtBlankLinesPreserve => 'Keep blank lines';

  @override
  String statisticsSince(String date) {
    return 'Recording since $date';
  }
}
