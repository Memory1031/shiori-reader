import 'dart:async';
import 'package:flutter/material.dart';
import '../../domain/contracts/import_source.dart';
import '../../l10n/generated/app_localizations.dart';
import 'import_controller.dart';

/// Root overlay preserves the Navigator and the currently open reading route.
class ImportOverlay extends StatefulWidget {
  const ImportOverlay({
    super.key,
    required this.controller,
    required this.child,
  });
  final ImportController controller;
  final Widget child;
  @override
  State<ImportOverlay> createState() => _ImportOverlayState();
}

class _ImportOverlayState extends State<ImportOverlay>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.refresh());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final l = AppLocalizations.of(context);
      final show =
          c.panelOpen ||
          !c.snoozed && (c.candidate != null || c.problem != null || c.busy);
      return Stack(
        children: [
          widget.child,
          if (show)
            Positioned.fill(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: 560,
                        maxHeight: MediaQuery.sizeOf(context).height * .65,
                      ),
                      child: Material(
                        elevation: 8,
                        borderRadius: BorderRadius.circular(20),
                        color: Theme.of(context).colorScheme.surfaceContainer,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                c.panelOpen ? l.importTitle : l.importIncoming,
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              if (c.candidate case final input?)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  child: Text(
                                    input.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              if (!c.panelOpen)
                                Wrap(
                                  spacing: 12,
                                  children: [
                                    FilledButton(
                                      onPressed: c.open,
                                      child: Text(l.importReview),
                                    ),
                                    TextButton(
                                      onPressed: c.later,
                                      child: Text(l.importLater),
                                    ),
                                  ],
                                )
                              else ...[
                                const SizedBox(height: 12),
                                if (c.busy) ...[
                                  Text(
                                    c.phase == ImportPhase.receiving
                                        ? l.importReceiving
                                        : l.importProcessing,
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(
                                    value:
                                        c.phase == ImportPhase.importing &&
                                            (c.candidate?.size ?? 0) > 0
                                        ? (c.copiedBytes / c.candidate!.size)
                                              .clamp(0, 1)
                                        : null,
                                  ),
                                ] else if (c.result != null)
                                  Text(l.importSuccess)
                                else if (c.problem case final problem?)
                                  Text(
                                    _problem(l, problem),
                                    key: const ValueKey('import-error'),
                                  )
                                else
                                  Text(l.importHint),
                                const SizedBox(height: 16),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    if (!c.busy &&
                                        c.result == null &&
                                        c.candidate == null)
                                      FilledButton(
                                        onPressed: c.pick,
                                        child: Text(l.importChoose),
                                      ),
                                    if (!c.busy &&
                                        c.candidate != null &&
                                        c.result == null)
                                      FilledButton(
                                        onPressed: c.submit,
                                        child: Text(
                                          c.phase == ImportPhase.failed
                                              ? l.importRetry
                                              : l.importStart,
                                        ),
                                      ),
                                    if (c.result != null)
                                      FilledButton(
                                        onPressed: c.finish,
                                        child: Text(l.importDone),
                                      )
                                    else
                                      TextButton(
                                        onPressed: c.cancel,
                                        child: Text(l.importCancel),
                                      ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    },
  );
  String _problem(AppLocalizations l, ImportProblem p) => switch (p) {
    ImportProblem.tooLarge => l.importTooLarge,
    ImportProblem.multiple => l.importMultiple,
    ImportProblem.busy => l.importBusy,
    ImportProblem.unsupported => l.importUnsupported,
    ImportProblem.invalidContent => l.importInvalid,
    ImportProblem.parserUnavailable => l.importParserUnavailable,
    ImportProblem.storage => l.importStorage,
    ImportProblem.cancelled => l.importCancelled,
    ImportProblem.unreadable => l.importUnreadable,
  };
}
