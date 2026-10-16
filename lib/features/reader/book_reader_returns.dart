part of 'book_reader_screen.dart';

// UI route ownership stays outside the pure return policy and dies with the book.
class _ReaderReturnSession {
  _ReaderReturnSession(this.owner);
  final _BookReaderScreenState owner;
  final history = ReaderReturnHistory();
  final surfaces = <Object, _BookReaderScreenState>{};
  final retired = <Object>{};
  bool returning = false;
  void changed() {
    final search = owner._search;
    if (owner.mounted && search != null) {
      search.canReturn.value = history.top?.kind == ReaderReturnKind.search;
    }
    for (final surface in surfaces.values.toList()) {
      if (surface.mounted) surface._searchState(() {});
    }
  }
}

class _ReaderReturnScope extends InheritedWidget {
  const _ReaderReturnScope({
    required this.session,
    required this.scope,
    required super.child,
  });
  final _ReaderReturnSession session;
  final Object scope;
  @override
  bool updateShouldNotify(_ReaderReturnScope oldWidget) => false;
}

extension _BookReaderReturns on _BookReaderScreenState {
  void _initReturns() {
    final inherited = context
        .getInheritedWidgetOfExactType<_ReaderReturnScope>();
    _returns = inherited?.session ?? _ReaderReturnSession(this);
    _returnScope = inherited?.scope ?? Object();
    _returns.surfaces[_returnScope] = this;
  }

  void _disposeReturns() {
    if (identical(_returns.surfaces[_returnScope], this)) {
      _returns.surfaces.remove(_returnScope);
    }
    if (identical(_returns.owner, this)) _returns.history.clear();
  }

  String? _returnLabel(BuildContext context) {
    final l = AppLocalizations.of(context);
    return switch (_returns.history.top?.kind) {
      ReaderReturnKind.search => l.readerSearchReturn,
      ReaderReturnKind.bookmark => l.readerBookmarkReturn,
      _ => null,
    };
  }

  void _commitReturnLocation(
    _LocationIntent intent,
    _ReturnAnchor? origin,
    _ReturnAnchor? destination,
    ReaderReturnEntry? returning,
    int ticket,
  ) {
    final history = _returns.history;
    if (origin != null && destination != null) {
      switch (intent) {
        case _LocationIntent.link:
          history.forward(ReaderReturnKind.link, origin, destination, ticket);
        case _LocationIntent.search:
          history.forward(ReaderReturnKind.search, origin, destination, ticket);
        case _LocationIntent.bookmark:
          history.forward(
            ReaderReturnKind.bookmark,
            origin,
            destination,
            ticket,
          );
        case _LocationIntent.explicit:
          history.explicit(origin, destination, ticket);
          if (!origin.sameLocation(destination)) {
            _contentsSession.invalidateBrowsing();
          }
        case _LocationIntent.returnLocation:
          if (returning != null) history.consume(returning, ticket);
        case _LocationIntent.sequential:
          break;
      }
    }
    if (intent != _LocationIntent.search) _search?.clearHighlight();
    if (intent == _LocationIntent.search) {
      _searchNavigation?.destinationScope = destination?.scope;
      if (identical(destination?.scope, _returnScope)) {
        _searchNavigation?.complete(
          _reader.pagePresentation == null
              ? ReaderSearchDestination.native
              : ReaderSearchDestination.document,
        );
      }
    }
    if (intent == _LocationIntent.returnLocation) {
      _searchNavigation?.complete(ReaderSearchDestination.native);
    }
    _returns.changed();
    if (intent == _LocationIntent.sequential ||
        intent == _LocationIntent.explicit) {
      _hideQuickReturn();
    } else {
      _chrome.value = false;
      _showQuickReturn();
    }
  }

  Future<void> _returnLocation() async {
    final entry = _returns.history.top;
    if (!_canNavigate ||
        _search?.navigating == true ||
        _returns.returning ||
        entry == null) {
      return;
    }
    final origin = _captureAnchor();
    if (origin == null) return;
    _returns.returning = true;
    try {
      await _returns.owner._returnFrom(this, entry, origin);
    } finally {
      _returns.returning = false;
    }
  }

  void _retireAbove(_BookReaderScreenState target) {
    for (final surface in _returns.surfaces.values.toList()) {
      if (surface != target &&
          surface.widget.linkDepth > target.widget.linkDepth) {
        _returns.retired.add(surface._returnScope);
      }
    }
    Navigator.of(context).popUntil((r) => identical(r, target._route));
  }

  void _retireOtherAuxiliaries(Object destinationScope) {
    for (final surface in _returns.surfaces.values.toList()) {
      if (surface != this &&
          !identical(surface._returnScope, destinationScope) &&
          surface._route?.isActive == true) {
        _returns.retired.add(surface._returnScope);
        surface._route!.navigator!.removeRoute(surface._route!);
      }
    }
  }

  Future<void> _returnFrom(
    _BookReaderScreenState source,
    ReaderReturnEntry entry,
    _ReturnAnchor origin,
  ) async {
    final ticket = _returns.history.version;
    bool live() =>
        mounted &&
        !_invalidated &&
        _foreground &&
        identical(_returns.history.top, entry) &&
        _returns.history.version == ticket;
    if (!live()) return;
    var target = _returns.surfaces[entry.origin.scope];
    if (target != null &&
        target != source &&
        target._reader.chapter == entry.origin.chapter &&
        !target._validAnchor(entry.origin, target._reader.content!)) {
      source._discardReturn(entry);
      return;
    }
    target ??= this;
    if (!live() || !target.mounted || target._changing) return;
    bool ownsSource() =>
        live() && source.mounted && source._route?.isCurrent == true;
    final opened = await target._returnOnSurface(
      entry,
      origin,
      ticket,
      live,
      owner: target != source ? ownsSource : null,
    );
    if (!opened || !mounted || _invalidated) return;
    if (identical(target._returnScope, entry.origin.scope)) {
      if (target != source) _retireAbove(target);
    } else {
      // A retired document was rebuilt above the old surfaces. Remove only
      // those old routes after the replacement has confirmed its position.
      _retireOtherAuxiliaries(entry.origin.scope);
    }
  }

  Future<bool> _returnOnSurface(
    ReaderReturnEntry entry,
    _ReturnAnchor origin,
    int ticket,
    bool Function() accepts, {
    bool Function()? owner,
  }) async {
    final anchor = entry.origin;
    if (!identical(anchor.scope, _returnScope)) {
      final navigation = _SearchNavigation(null, anchor, accepts);
      _searchNavigation = navigation;
      try {
        unawaited(
          _openAuxiliary(
            anchor.chapter,
            anchor.position.blockKey,
            null,
            intent: _LocationIntent.returnLocation,
            search: navigation,
            origin: origin,
            returning: entry,
            scope: anchor.scope,
            returnTicket: ticket,
            owner: owner,
          ),
        );
        return await navigation.result.future != ReaderSearchDestination.failed;
      } finally {
        if (identical(_searchNavigation, navigation)) _searchNavigation = null;
      }
    }
    if (anchor.chapter == _reader.chapter) {
      if (!_validAnchor(anchor, _reader.content!)) {
        _discardReturn(entry);
        return false;
      }
      if (_reader.pagePresentation != null) {
        _commitLocation(_LocationIntent.returnLocation, origin, entry, ticket);
        return true;
      } else {
        return await _restorePosition(
          anchor.position,
          intent: _LocationIntent.returnLocation,
          returning: entry,
          accepts: owner ?? accepts,
          origin: origin,
          returnTicket: ticket,
        );
      }
    } else {
      final confirmation = Completer<_ChapterConfirmation>();
      await _switch(
        anchor.chapter,
        navigationPosition: anchor.position,
        fromStart: true,
        intent: _LocationIntent.returnLocation,
        origin: origin,
        returning: entry,
        confirmation: confirmation,
        owner: owner,
      );
      if (identical(_operation?.confirmation, confirmation) ||
          confirmation.isCompleted) {
        return (await confirmation.future).committed;
      }
    }
    return false;
  }
}
