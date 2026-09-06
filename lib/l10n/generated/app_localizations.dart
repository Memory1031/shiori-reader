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

  /// No description provided for @accessRestrictedMessage.
  ///
  /// In en, this message translates to:
  /// **'Access to this content is restricted.'**
  String get accessRestrictedMessage;

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
