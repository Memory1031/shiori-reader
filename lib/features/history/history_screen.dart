import '../reader/book_progress_label.dart';
import 'package:flutter/material.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/widgets/app_scaffold.dart';
import '../../shared/widgets/state_views.dart';
import '../../shared/widgets/book_cover.dart';
import '../bookshelf/library_controller.dart';
import '../bookshelf/library_observer.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({
    super.key,
    required this.controller,
    required this.onContinue,
  });
  final LibraryController controller;
  final ValueChanged<NovelKey> onContinue;
  @override
  Widget build(BuildContext context) => LibraryObserver(
    controller: controller,
    builder: (context, library) {
      final strings = AppLocalizations.of(context);
      return AppScaffold(
        title: strings.historyTitle,
        body: Column(
          children: [
            if (library.historyFailure != null)
              Flexible(child: FailureView(failure: library.historyFailure!)),
            if (library.writeFailure != null)
              Flexible(child: FailureView(failure: library.writeFailure!)),
            Expanded(
              flex: 3,
              child: !library.historyReady
                  ? const LoadingView()
                  : library.recent.isEmpty
                  ? EmptyView(message: strings.historyEmpty)
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      itemCount: library.recent.length,
                      itemBuilder: (context, index) {
                        final item = library.recent[index];
                        return ListTile(
                          leading: SizedBox(
                            width: 40,
                            child: BookCover(book: item.snapshot),
                          ),
                          key: ValueKey(item.novelKey),
                          title: Text(item.snapshot.title),
                          subtitle: Text(
                            bookProgressLabel(
                                  strings,
                                  item.bookProgress,
                                  descriptive: true,
                                ) ??
                                strings.readerReadingProgress,
                          ),
                          onTap: () => onContinue(item.novelKey),
                          trailing: IconButton(
                            tooltip: strings.historyClear,
                            onPressed: library.writing
                                ? null
                                : () => library.clearHistory(item.novelKey),
                            icon: const Icon(Icons.clear),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      );
    },
  );
}
