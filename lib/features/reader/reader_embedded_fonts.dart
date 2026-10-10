import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../domain/contracts/contracts.dart';
import '../../domain/models/models.dart';
import '../../shared/widgets/state_views.dart';

/// Application-owned registration budget. Flutter cannot unregister fonts;
/// therefore registrations are content-addressed and never grow past this cap.
class ReaderFontRegistry {
  final _loads = <String, Future<void>>{};
  final _lifetime = CancellationSource();
  void dispose() => _lifetime.cancel();
  int _bytes = 0;
  Future<void> load(EmbeddedFontFamily family, ImageRepository repository) {
    final existing = _loads[family.familyName];
    if (existing != null) return existing;
    if (_loads.length >= 128) return Future.value();
    final future = _load(family, repository, _lifetime.token);
    _loads[family.familyName] = future;
    return future;
  }

  Future<void> _load(
    EmbeddedFontFamily family,
    ImageRepository repository,
    CancellationToken token,
  ) async {
    final loader = FontLoader(family.familyName);
    var count = 0;
    for (final ref in family.sources) {
      if (token.isCancelled) break;
      final result = await repository.load(
        ref,
        mode: ReadMode.cacheOnly,
        cancellation: token,
      );
      if (result case Success(:final value)) {
        final lease = value.value;
        try {
          final data = lease.data;
          final Uint8List bytes;
          switch (data) {
            case MemoryMedia():
              bytes = data.bytes;
            case LocalMedia():
              final file = File(data.path);
              if (await file.length() > 8 * 1024 * 1024) continue;
              bytes = await file.readAsBytes();
          }
          if (token.isCancelled ||
              bytes.length > 8 * 1024 * 1024 ||
              _bytes + bytes.length > 64 * 1024 * 1024) {
            continue;
          }
          _bytes += bytes.length;
          loader.addFont(Future.value(ByteData.sublistView(bytes)));
          count++;
        } on Exception {
          // Optional fonts fall back; media leases must still be released.
        } finally {
          await lease.close();
        }
      }
    }
    if (count > 0 && !token.isCancelled) {
      try {
        await loader.load();
      } on Exception {
        /* Platform rejected this family. */
      }
    }
    if (token.isCancelled) _loads.remove(family.familyName);
  }
}

class ReaderFontScope extends InheritedWidget {
  const ReaderFontScope({
    super.key,
    required this.registry,
    required super.child,
  });
  final ReaderFontRegistry registry;
  @override
  bool updateShouldNotify(ReaderFontScope oldWidget) =>
      registry != oldWidget.registry;
}

/// Wait before the first native measurement; a late font must never change
/// glyph geometry underneath an already paginated chapter or saved anchor.
class ReaderFontGate extends StatefulWidget {
  const ReaderFontGate({
    super.key,
    required this.content,
    this.repository,
    required this.child,
  });
  final ChapterContent content;
  final ImageRepository? repository;
  final Widget child;
  @override
  State<ReaderFontGate> createState() => _ReaderFontGateState();
}

class _ReaderFontGateState extends State<ReaderFontGate> {
  final _localRegistry = ReaderFontRegistry();
  bool _loaded = false;
  Future<void>? _ready;
  List<EmbeddedFontFamily> _families = [];
  ReaderFontRegistry? _registry;
  void _load() {
    final registry =
        context
            .dependOnInheritedWidgetOfExactType<ReaderFontScope>()
            ?.registry ??
        _localRegistry;
    final families = widget.content.blocks
        .expand((b) => b.inlineStyles)
        .expand((s) => s.fonts)
        .toSet()
        .toList();
    if (registry == _registry &&
        families.length == _families.length &&
        families.every(_families.contains) &&
        _loaded) {
      return;
    }
    _loaded = true;
    _families = families;
    _registry = registry;
    _ready = widget.repository == null || families.isEmpty
        ? null
        : Future.wait(
            families.map((f) => registry.load(f, widget.repository!)),
          );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(ReaderFontGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.repository != oldWidget.repository) {
      _loaded = false;
    }
    _load();
  }

  @override
  void dispose() {
    _localRegistry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _ready == null
      ? widget.child
      : FutureBuilder<void>(
          future: _ready,
          builder: (context, snapshot) =>
              snapshot.connectionState == ConnectionState.done
              ? widget.child
              : const Center(child: LoadingView()),
        );
}
