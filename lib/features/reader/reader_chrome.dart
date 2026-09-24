import 'dart:async';
import 'dart:math' as math;

import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reader chrome geometry derived from text scale, so running headers and
/// toolbars grow with accessibility sizes instead of clipping. Content
/// gutters reserve only the running header / footer; toolbars overlay the
/// page, which keeps pagination stable while they show and hide.
@immutable
class ReaderChromeMetrics {
  const ReaderChromeMetrics._({
    required this.header,
    required this.footer,
    required this.topBar,
    required this.bottomBar,
  });

  factory ReaderChromeMetrics.of(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final line = math.max(18.0, scaler.scale(12) * 1.5);
    return ReaderChromeMetrics._(
      header: line + 16,
      footer: line + 16,
      topBar: math.max(56, scaler.scale(15) * 1.5 + 32),
      bottomBar: math.max(64, scaler.scale(14) * 1.5 + 40),
    );
  }

  /// Gutters reserved above and below the page for the running header and
  /// the status footer.
  final double header, footer;

  /// Heights of the top and bottom toolbars.
  final double topBar, bottomBar;
}

/// Hides the status and navigation bars while any reader is open on touch
/// platforms. Reference-counted so a nested link reader does not restore
/// them under the outer reader. Bars stay hidden while toolbars toggle, so
/// safe-area insets, and therefore pagination, never change mid-session;
/// [ReaderStatusRow] shows the time and battery in their place.
abstract final class ReaderSystemUi {
  static int _depth = 0;

  static void enter() {
    if (_depth++ == 0) {
      unawaited(
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
      );
    }
  }

  static void exit() {
    if (_depth == 0) return;
    if (--_depth == 0) {
      unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    }
  }
}

/// Clock and battery for immersive reading. Battery is omitted when the
/// device reports none or the platform cannot read it.
class ReaderStatusRow extends StatefulWidget {
  const ReaderStatusRow({super.key, required this.progress, this.battery});

  /// Right-aligned reading progress, e.g. the current chapter percentage.
  final Widget progress;

  /// Injected for tests; defaults to the platform battery.
  final Battery? battery;

  @override
  State<ReaderStatusRow> createState() => _ReaderStatusRowState();
}

class _ReaderStatusRowState extends State<ReaderStatusRow> {
  late final Battery _battery = widget.battery ?? Battery();
  Timer? _tick;
  DateTime _now = DateTime.now();
  int? _level;
  BatteryState _state = BatteryState.unknown;

  @override
  void initState() {
    super.initState();
    _scheduleTick();
    unawaited(_readBattery());
  }

  // Wake on the next minute boundary rather than polling.
  void _scheduleTick() {
    final now = DateTime.now();
    final next = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(const Duration(minutes: 1));
    _tick = Timer(next.difference(now), () {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      unawaited(_readBattery());
      _scheduleTick();
    });
  }

  // Polled with the clock: the state stream is an EventChannel whose
  // missing-plugin errors cannot be caught, and a minute is fresh enough.
  Future<void> _readBattery() async {
    try {
      final level = await _battery.batteryLevel;
      final state = await _battery.batteryState;
      if (mounted && (level != _level || state != _state)) {
        setState(() {
          _level = level;
          _state = state;
        });
      }
    } on Object {
      // No battery or no platform implementation: keep the clock only.
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;
    final style = theme.textTheme.labelSmall?.copyWith(
      color: color,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(_now),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final level = _level;
    // Desktop emulators and PCs without a battery commonly report 0 or less.
    final showBattery =
        level != null && level > 0 && _state != BatteryState.unknown;
    final charging =
        _state == BatteryState.charging || _state == BatteryState.full;
    return DefaultTextStyle.merge(
      style: style,
      child: Row(
        children: [
          Text(time),
          if (showBattery) ...[
            const SizedBox(width: 10),
            Semantics(
              label: '$level%',
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(
                    size: Size(
                      (style?.fontSize ?? 12) * 1.7,
                      (style?.fontSize ?? 12) * .85,
                    ),
                    painter: _BatteryGlyph(
                      level: level / 100,
                      charging: charging,
                      color: color,
                      low: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text('$level%'),
                ],
              ),
            ),
          ],
          const SizedBox(width: 12),
          // Clock and battery keep their size; progress yields on narrow pages.
          Expanded(
            child: Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FittedBox(fit: BoxFit.scaleDown, child: widget.progress),
            ),
          ),
        ],
      ),
    );
  }
}

class _BatteryGlyph extends CustomPainter {
  _BatteryGlyph({
    required this.level,
    required this.charging,
    required this.color,
    required this.low,
  });
  final double level;
  final bool charging;
  final Color color, low;

  @override
  void paint(Canvas canvas, Size size) {
    // Own layer so the charging bolt can knock out of the level fill.
    canvas.saveLayer(Offset.zero & size, Paint());
    final cap = size.width * .08;
    final body = Rect.fromLTWH(0, 0, size.width - cap, size.height);
    final stroke = math.max(1.0, size.height * .1);
    final outline = Paint()
      ..color = color.withValues(alpha: .7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        body.deflate(stroke / 2),
        Radius.circular(size.height * .22),
      ),
      outline,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(body.right, size.height * .3, cap, size.height * .4),
        Radius.circular(cap / 2),
      ),
      Paint()..color = color.withValues(alpha: .7),
    );
    final inner = body.deflate(stroke * 2);
    final fill = !charging && level <= .2 ? low : color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          inner.left,
          inner.top,
          inner.width * level.clamp(0.0, 1.0),
          inner.height,
        ),
        Radius.circular(size.height * .1),
      ),
      Paint()..color = fill,
    );
    if (charging) {
      final c = body.center;
      final h = size.height * .8, w = h * .55;
      final bolt = Path()
        ..moveTo(c.dx + w * .15, c.dy - h / 2)
        ..lineTo(c.dx - w / 2, c.dy + h * .08)
        ..lineTo(c.dx - w * .02, c.dy + h * .08)
        ..lineTo(c.dx - w * .15, c.dy + h / 2)
        ..lineTo(c.dx + w / 2, c.dy - h * .08)
        ..lineTo(c.dx + w * .02, c.dy - h * .08)
        ..close();
      canvas.drawPath(
        bolt,
        Paint()
          ..color = color
          ..blendMode = BlendMode.xor,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_BatteryGlyph old) =>
      old.level != level ||
      old.charging != charging ||
      old.color != color ||
      old.low != low;
}

/// Toolbar surface over the page: a slight ink tint of the paper, a hairline
/// on the page-facing [edge] and a soft shadow, so overlaid text reads as
/// passing beneath the bar rather than being cut off.
class ReaderToolbarSurface extends StatelessWidget {
  const ReaderToolbarSurface({
    super.key,
    required this.edge,
    required this.child,
    this.padding = EdgeInsets.zero,
  });

  /// [VerticalDirection.down] for a top bar whose page edge is below it.
  final VerticalDirection edge;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = theme.colorScheme.onSurface;
    final dark = theme.brightness == Brightness.dark;
    final hairline = BorderSide(
      color: theme.colorScheme.outlineVariant.withValues(alpha: .6),
      width: .5,
    );
    return Material(
      type: MaterialType.transparency,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            ink.withValues(alpha: dark ? .07 : .035),
            theme.scaffoldBackgroundColor,
          ),
          border: edge == VerticalDirection.down
              ? Border(bottom: hairline)
              : Border(top: hairline),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .28 : .07),
              blurRadius: 12,
              offset: Offset(0, edge == VerticalDirection.down ? 2 : -2),
            ),
          ],
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}
