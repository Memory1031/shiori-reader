import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// In-memory browsing only. The view owns its controller; this stores a list
/// visible row and relative pixels under matching data and layout contracts.
class CatalogBrowsingState {
  Object? _data, _layout;
  int _attachment = 0, revision = 0;
  bool _active = true;
  ({int center, double offset})? position;
  final collapsed = <String>{};

  int attach() => ++_attachment;
  bool owns(int attachment) => _active && attachment == _attachment;

  bool configure(int attachment, Object data, Object layout) {
    if (!owns(attachment)) return false;
    final changed = _data != data || _layout != layout;
    if (_data != data) collapsed.clear();
    if (changed) {
      _data = data;
      _layout = layout;
      position = null;
      revision++;
    }
    return changed;
  }

  void remember(int attachment, int version, int center, double offset) {
    if (owns(attachment) && revision == version && offset.isFinite) {
      position = (center: center, offset: offset);
    }
  }

  void invalidate() {
    _active = false;
    _attachment++;
    position = null;
    collapsed.clear();
  }
}

Object catalogBrowsingLayout(BuildContext context, Size size) => (
  size,
  MediaQuery.textScalerOf(context),
  Theme.of(context).textTheme,
  Theme.of(context).visualDensity,
  Theme.of(context).listTileTheme,
  MediaQuery.paddingOf(context),
  Localizations.localeOf(context),
  Directionality.of(context),
);

/// Inspect only laid-out children. Reopening at this row never measures the
/// unseen prefix, even if browsing moved far from the reading chapter.
({int center, double offset})? captureCatalogBrowsing(
  ScrollPosition position, {
  required int center,
  required RenderObject? before,
  required RenderObject? after,
  bool endAnchor = false,
  bool? restoreEndAnchor,
}) {
  (int, double)? visible;
  void inspect(RenderObject? sliver, bool reverse) {
    if (sliver is RenderSliverPadding) sliver = sliver.child;
    if (sliver is! RenderSliverMultiBoxAdaptor) return;
    for (
      var child = sliver.firstChild;
      child != null;
      child = sliver.childAfter(child)
    ) {
      final index =
          (child.parentData! as SliverMultiBoxAdaptorParentData).index!;
      final top =
          RenderAbstractViewport.of(child).getOffsetToReveal(child, 0).offset -
          position.pixels +
          (endAnchor && center > 0 ? position.viewportDimension : 0);
      if (top + child.size.height <= 0 || top >= position.viewportDimension) {
        continue;
      }
      if (visible == null || top < visible!.$2) {
        visible = (reverse ? center - index - 1 : center + index, top);
      }
    }
  }

  inspect(before, true);
  inspect(after, false);
  final row = visible;
  return row == null
      ? null
      : (
          center: row.$1,
          offset:
              ((restoreEndAnchor ?? endAnchor) && row.$1 > 0
                  ? position.viewportDimension
                  : 0) -
              row.$2,
        );
}
