import '../domain/contracts/local_book_decoder.dart';
import '../l10n/generated/app_localizations.dart';

String localNavigationTitle(LocalNavigationEntry entry, AppLocalizations l) =>
    switch (entry.generatedLabel) {
      LocalNavigationLabel.cover => l.localNavigationCover,
      LocalNavigationLabel.titlePage => l.localNavigationTitlePage,
      LocalNavigationLabel.credits => l.localNavigationCredits,
      LocalNavigationLabel.synopsis => l.localNavigationSynopsis,
      LocalNavigationLabel.author => l.localNavigationAuthor,
      LocalNavigationLabel.illustrator => l.localNavigationIllustrator,
      LocalNavigationLabel.illustrations => l.localNavigationIllustrations,
      LocalNavigationLabel.contents => l.localNavigationContents,
      LocalNavigationLabel.preface => l.localNavigationPreface,
      LocalNavigationLabel.dedication => l.localNavigationDedication,
      null => entry.title,
    };
