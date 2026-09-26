import 'package:flutter/material.dart';

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

/// A left-aligned content frame. The caller owns scrolling and page state.
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
      final width = (bounds.maxWidth - 2 * gutter).clamp(0.0, maxWidth);
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: gutter),
        child: Align(
          alignment: AlignmentDirectional.topStart,
          child: SizedBox(width: width, child: child),
        ),
      );
    },
  );
}

/// A naturally sized page toolbar; actions wrap instead of squeezing the title.
class DesktopPageToolbar extends StatelessWidget {
  const DesktopPageToolbar({
    super.key,
    required this.title,
    this.actions = const [],
  });
  final String title;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ShioriSpace.item),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (canPop) ...[
                const BackButton(),
                const SizedBox(width: ShioriSpace.small),
              ],
              Expanded(
                child: Semantics(
                  header: true,
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: ShioriSpace.small),
            Wrap(
              spacing: ShioriSpace.small,
              runSpacing: ShioriSpace.small,
              children: actions,
            ),
          ],
        ],
      ),
    );
  }
}
