import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../app/theme/shiori_theme.dart';
import '../capabilities.dart';

/// Shell width before navigation takes its share. Standalone routes use the
/// window width. This is layout information only, not navigation state.
class DesktopLayoutScope extends InheritedWidget {
  const DesktopLayoutScope({
    super.key,
    required this.width,
    required super.child,
  });
  final double width;

  static double widthOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DesktopLayoutScope>()?.width ??
      MediaQuery.sizeOf(context).width;

  static bool useDesktopPage(BuildContext context) =>
      ShioriCapabilities.of(context).pointerFirst &&
      widthOf(context) >= ShioriLayout.page;

  @override
  bool updateShouldNotify(DesktopLayoutScope oldWidget) =>
      width != oldWidget.width;
}

/// Geometry in the Workspace's coordinates, before optional row tint bleed.
({double contentWidth, double inset}) desktopContentGeometry({
  required double availableWidth,
  required double gutter,
  required double maxWidth,
}) {
  final width = (availableWidth - 2 * gutter).clamp(0.0, maxWidth);
  return (contentWidth: width, inset: (availableWidth - width) / 2);
}

/// A centered frame whose contents remain start-aligned. The caller owns
/// scrolling and page state.
class DesktopContentFrame extends StatelessWidget {
  const DesktopContentFrame({
    super.key,
    required this.maxWidth,
    required this.child,
    this.gutter,
  });
  final double maxWidth;
  final Widget child;
  final double? gutter;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final gutter =
          this.gutter ??
          ShioriLayout.gutter(DesktopLayoutScope.widthOf(context));
      final geometry = desktopContentGeometry(
        availableWidth: bounds.maxWidth,
        gutter: gutter,
        maxWidth: maxWidth,
      );
      return Align(
        alignment: Alignment.topCenter,
        child: SizedBox(width: geometry.contentWidth, child: child),
      );
    },
  );
}

/// A naturally sized page toolbar; actions wrap instead of squeezing the title.
class DesktopPageToolbar extends StatelessWidget {
  const DesktopPageToolbar({
    super.key,
    required this.title,
    this.leading,
    this.secondary,
    this.actions = const [],
  });
  final String title;
  final Widget? leading;
  final Widget? secondary;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: Padding(
        padding: const EdgeInsets.only(
          top: ShioriSpace.item,
          bottom: ShioriSpace.medium,
        ),
        child: _ToolbarLayout(
          direction: Directionality.of(context),
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: ShioriSpace.small),
                ],
                Flexible(
                  child: Wrap(
                    spacing: ShioriSpace.medium,
                    runSpacing: ShioriSpace.tight,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      ?secondary,
                    ],
                  ),
                ),
              ],
            ),
            Wrap(
              spacing: ShioriSpace.medium,
              runSpacing: ShioriSpace.small,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: actions,
            ),
          ],
        ),
      ),
    );
  }
}

/// Two persistent slots: only their offsets change when actions wrap below the
/// title. Focus, menu anchors and child state survive the layout change.
class _ToolbarLayout extends MultiChildRenderObjectWidget {
  const _ToolbarLayout({required this.direction, required super.children});
  final TextDirection direction;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderToolbar(direction);

  @override
  void updateRenderObject(BuildContext context, _RenderToolbar renderObject) {
    renderObject.direction = direction;
  }
}

class _ToolbarParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderToolbar extends RenderBox
    with
        ContainerRenderObjectMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        >,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          ContainerBoxParentData<RenderBox>
        > {
  _RenderToolbar(this._direction);
  TextDirection _direction;
  set direction(TextDirection value) {
    if (_direction == value) return;
    _direction = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! ContainerBoxParentData<RenderBox>) {
      child.parentData = _ToolbarParentData();
    }
  }

  ({Size size, Offset title, Offset actions}) _geometry(
    BoxConstraints constraints,
    Size title,
    Size actions,
  ) {
    final width = constraints.maxWidth;
    final inline = title.width + ShioriSpace.item + actions.width <= width;
    final height = actions.isEmpty
        ? title.height
        : inline
        ? (title.height > actions.height ? title.height : actions.height)
        : title.height + ShioriSpace.small + actions.height;
    final size = constraints.constrain(Size(width, height));
    final titleX = _direction == TextDirection.ltr ? 0.0 : width - title.width;
    final actionsX = (_direction == TextDirection.ltr) == inline
        ? width - actions.width
        : 0.0;
    return (
      size: size,
      title: Offset(titleX, inline ? (size.height - title.height) / 2 : 0),
      actions: Offset(
        actionsX,
        inline
            ? (size.height - actions.height) / 2
            : title.height + ShioriSpace.small,
      ),
    );
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final loose = BoxConstraints(maxWidth: constraints.maxWidth);
    return _geometry(
      constraints,
      firstChild!.getDryLayout(loose),
      lastChild!.getDryLayout(loose),
    ).size;
  }

  @override
  void performLayout() {
    final loose = BoxConstraints(maxWidth: constraints.maxWidth);
    firstChild!.layout(loose, parentUsesSize: true);
    lastChild!.layout(loose, parentUsesSize: true);
    final result = _geometry(constraints, firstChild!.size, lastChild!.size);
    size = result.size;
    (firstChild!.parentData! as ContainerBoxParentData<RenderBox>).offset =
        result.title;
    (lastChild!.parentData! as ContainerBoxParentData<RenderBox>).offset =
        result.actions;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
