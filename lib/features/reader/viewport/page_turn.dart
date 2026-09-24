import 'package:flutter/material.dart';

import '../../../domain/models/models.dart';
import 'paper_turn.dart';

export '../../../domain/models/models.dart' show PageTurnStyle;
export 'paper_turn.dart' show PaperTurnMotion;

/// A page's part in a turn: [leaving] is the page being turned away from,
/// [entering] the page being turned to.
enum PageTurnRole { leaving, entering }

/// One frame of a page turn, shared by every page change in the reader
/// (pages within a chapter, chapter boundaries and the completion page) so
/// they all follow the reader's chosen [style].
///
/// [progress] runs 0 → 1 as the turn completes; [direction] is 1 towards
/// the next page and -1 towards the previous one; [grip] is where the page
/// is held, as a fraction of its height, so a dragged curl lifts from the
/// finger. All styles move live widgets: nothing is captured to a bitmap,
/// so the same frames cover native text pages and platform-view pages.
@immutable
class PageTurnFrame {
  const PageTurnFrame({
    required this.style,
    required this.progress,
    required this.direction,
    this.grip = pageTurnCentreGrip,
  });
  final PageTurnStyle style;
  final double progress;
  final int direction;
  final double grip;

  static const rest = PageTurnFrame(
    style: PageTurnStyle.curl,
    progress: 0,
    direction: 1,
  );

  double get _p => progress.clamp(0.0, 1.0);
  bool get turning => _p > 0 && _p < 1;

  /// Cover slides the later page over the earlier one: forward it enters
  /// on top, backward the leaving page slides off the top. Every other
  /// style keeps the leaving page above the entering one.
  bool get enteringOnTop => style == PageTurnStyle.cover && direction > 0;

  /// Horizontal offset of a page of [width] in this frame.
  double offset(PageTurnRole role, double width) {
    final p = _p;
    return switch (style) {
      PageTurnStyle.cover => switch ((role, direction > 0)) {
        (PageTurnRole.entering, true) => width * (1 - p),
        (PageTurnRole.leaving, false) => width * p,
        _ => 0,
      },
      PageTurnStyle.slide => switch (role) {
        PageTurnRole.leaving => -width * p * direction,
        PageTurnRole.entering => width * direction * (1 - p),
      },
      PageTurnStyle.curl || PageTurnStyle.none => 0,
    };
  }

  /// Settling curve: the curl keeps the paper's decelerating settle; the
  /// flat styles use a snappier ease so a sliding sheet does not drift.
  Curve get curve => switch (style) {
    PageTurnStyle.curl => Curves.easeOutCubic,
    _ => Curves.easeOutQuart,
  };

  /// Whether the change should animate at all.
  bool get animates => style != PageTurnStyle.none;

  @override
  bool operator ==(Object other) =>
      other is PageTurnFrame &&
      other.style == style &&
      other.progress == progress &&
      other.direction == direction &&
      other.grip == grip;

  @override
  int get hashCode => Object.hash(style, progress, direction, grip);
}

/// Wraps one page of a turn. The widget structure is identical for every
/// style and role, only its parameters change, so a keyed page keeps its
/// state (decoded images, text layout) across the turn and its commit.
class PageTurnSlot extends StatelessWidget {
  const PageTurnSlot({
    super.key,
    required this.frame,
    required this.role,
    required this.child,
    this.paper,
    this.pageSize,
    this.contentOrigin = Offset.zero,
  });
  final PageTurnFrame frame;
  final PageTurnRole role;
  final Widget child;

  /// Opaque backing so the page hides whatever lies beneath it.
  final Color? paper;

  /// Full reader page and this slot's origin within it, when the slot is
  /// laid out inside page gutters but the curl spans the whole page.
  final Size? pageSize;
  final Offset contentOrigin;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final width = pageSize?.width ?? bounds.maxWidth;
      final curl =
          frame.style == PageTurnStyle.curl &&
          role == PageTurnRole.leaving &&
          frame.turning;
      // A page that has fully left stays mounted (a host may hold the turn
      // at its end, e.g. the completion page) but is neither painted nor
      // hit-tested.
      final gone = role == PageTurnRole.leaving && frame.progress >= 1;
      return Offstage(
        offstage: gone,
        child: Transform.translate(
          offset: Offset(frame.offset(role, width), 0),
          child: ClipPath(
            clipper: curl
                ? PaperTurnClipper(
                    frame.progress,
                    frame.direction,
                    pageSize: pageSize,
                    contentOrigin: contentOrigin,
                    grip: frame.grip,
                  )
                : null,
            clipBehavior: curl ? Clip.antiAlias : Clip.none,
            child: ColoredBox(
              color: paper ?? const Color(0x00000000),
              child: child,
            ),
          ),
        ),
      );
    },
  );
}

/// Soft shadow cast by the sliding sheet's edge in a cover turn. Place it
/// between the lower and upper slot, sized like them; [pageSize] matches
/// the slots so the shadow follows the sheet edge exactly. Paints nothing
/// for other styles; the curl draws its own shading in [PageTurnOverlay].
class PageTurnShade extends StatelessWidget {
  const PageTurnShade({super.key, required this.frame, this.pageSize});
  final PageTurnFrame frame;
  final Size? pageSize;

  @override
  Widget build(BuildContext context) {
    if (frame.style != PageTurnStyle.cover || !frame.turning) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final width = pageSize?.width ?? bounds.maxWidth;
          // The sheet's leading edge, in the same coordinates as the slots.
          final edge = frame.direction > 0
              ? frame.offset(PageTurnRole.entering, width)
              : frame.offset(PageTurnRole.leaving, width);
          return Stack(
            fit: StackFit.expand,
            clipBehavior: Clip.none,
            children: [
              Positioned(
                top: 0,
                bottom: 0,
                left: edge - 18,
                width: 18,
                child: const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0x00000000), Color(0x2E000000)],
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Paints the curl's folded back, cast shadow and crease highlight over the
/// whole reader page. Paints nothing for the flat styles.
class PageTurnOverlay extends StatelessWidget {
  const PageTurnOverlay({super.key, required this.frame, required this.paper});
  final PageTurnFrame frame;
  final Color paper;

  @override
  Widget build(BuildContext context) => frame.style == PageTurnStyle.curl
      ? PaperTurnFold(
          progress: frame.progress,
          direction: frame.direction,
          paper: paper,
          grip: frame.grip,
        )
      : const SizedBox.shrink();
}

/// Vertical grip for gestures without a pointer (taps, keys).
const pageTurnCentreGrip = .5;

/// Clamps a pointer's y within a page to a usable grip fraction; grips at
/// the very edge would fold along the page border and read as a glitch.
double pageTurnGrip(double y, double height) =>
    height <= 0 ? pageTurnCentreGrip : (y / height).clamp(.15, .85);
