import 'dart:async';
import 'package:flutter/material.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../l10n/generated/app_localizations.dart';

const readerAudioExtent = ShioriSpace.section + ShioriSpace.item;

/// A chapter owns one player, opened lazily by a tap. Cached pages never create
/// a player, and only the active page is allowed to send commands.
class ReaderAudioController extends ChangeNotifier {
  ReaderAudioController(this.factory);
  final AudioPlaybackFactory? factory;
  AudioPlayback? _player;
  StreamSubscription<AudioPlaybackState>? _subscription;
  AudioBlock? selected;
  var state = AudioPlaybackState.stopped, loading = false, _closed = false;
  AppFailure? failure;
  var _generation = 0;
  Future<void> toggle(AudioBlock block) async {
    if (_closed || loading || factory == null || block.media == null) return;
    final generation = ++_generation;
    final same = selected?.blockKey == block.blockKey;
    final oldState = state;
    selected = block;
    failure = null;
    loading = true;
    notifyListeners();
    Result<void> result;
    try {
      final player = _player ??= factory!.createAudioPlayback();
      _subscription ??= player.states.listen((next) {
        if (_closed) return;
        state = next;
        notifyListeners();
      });
      result = await (same && oldState == AudioPlaybackState.playing
          ? player.pause()
          : same && oldState == AudioPlaybackState.paused
          ? player.resume()
          : player.play(block.media!, block.format!));
    } catch (_) {
      result = Failure(
        AppFailure(
          kind: FailureKind.parse,
          operation: Operation.media,
          retryPolicy: RetryPolicy.manual,
        ),
      );
    }
    if (_closed || generation != _generation) return;
    loading = false;
    if (result case Failure(:final failure)) {
      if (!failure.isCancellation) this.failure = failure;
      state = AudioPlaybackState.stopped;
    } else {
      state = same && oldState == AudioPlaybackState.playing
          ? AudioPlaybackState.paused
          : AudioPlaybackState.playing;
    }
    notifyListeners();
  }

  void stop() {
    if (_closed || selected == null) return;
    _generation++;
    selected = null;
    loading = false;
    failure = null;
    state = AudioPlaybackState.stopped;
    unawaited(_player?.stop());
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _generation++;
    unawaited(_subscription?.cancel());
    unawaited(_player?.close());
    super.dispose();
  }
}

class ReaderAudioControl extends StatelessWidget {
  const ReaderAudioControl({
    super.key,
    required this.block,
    required this.controller,
    required this.enabled,
  });
  final AudioBlock block;
  final ReaderAudioController controller;
  final bool enabled;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final l = AppLocalizations.of(context);
      final selected = controller.selected?.blockKey == block.blockKey;
      final loading = selected && controller.loading;
      final failed = selected && controller.failure != null;
      final unavailable = block.media == null || controller.factory == null;
      final playing =
          selected && controller.state == AudioPlaybackState.playing;
      final tooltip = unavailable
          ? l.readerAudioUnavailable
          : failed
          ? l.readerAudioFailed
          : playing
          ? l.readerAudioPause
          : l.readerAudioPlay;
      return SizedBox(
        height: readerAudioExtent,
        child: Align(
          alignment: switch (block.alignment) {
            ParagraphAlignment.center => Alignment.center,
            ParagraphAlignment.end => AlignmentDirectional.centerEnd,
            ParagraphAlignment.start => AlignmentDirectional.centerStart,
          },
          child: Semantics(
            label: block.label,
            child: IconButton.filledTonal(
              tooltip: tooltip,
              // Busy commands are rejected by the controller. Keep the visual
              // enabled state so fast play/pause operations do not flash gray.
              onPressed: !enabled || unavailable
                  ? null
                  : () => unawaited(controller.toggle(block)),
              icon: SizedBox.square(
                dimension: ShioriSpace.page,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(
                      unavailable
                          ? Icons.volume_off_outlined
                          : failed
                          ? Icons.replay
                          : playing
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                    _AudioPendingIndicator(active: loading),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// Only slow preparation needs an indicator; retain the icon underneath it.
class _AudioPendingIndicator extends StatefulWidget {
  const _AudioPendingIndicator({required this.active});
  final bool active;
  @override
  State<_AudioPendingIndicator> createState() => _AudioPendingIndicatorState();
}

class _AudioPendingIndicatorState extends State<_AudioPendingIndicator> {
  Timer? _delay;
  var _visible = false;

  void _update() {
    _delay?.cancel();
    _visible = false;
    if (widget.active) {
      _delay = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _visible = true);
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(_AudioPendingIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _update();
  }

  @override
  Widget build(BuildContext context) => _visible
      ? const Positioned.fill(
          child: IgnorePointer(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        )
      : const SizedBox.shrink();

  @override
  void dispose() {
    _delay?.cancel();
    super.dispose();
  }
}
