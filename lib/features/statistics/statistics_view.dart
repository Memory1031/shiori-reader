import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../app/theme/shiori_theme.dart';
import '../../domain/contracts/contracts.dart';
import '../../l10n/generated/app_localizations.dart';
import '../../shared/capabilities.dart';
import '../../shared/widgets/book_cover.dart';
import '../../shared/widgets/desktop_content_frame.dart';
import '../../shared/widgets/shiori_sheet.dart';
import 'reading_statistics_controller.dart';

String readingDuration(AppLocalizations l, int ms) {
  if (ms > 0 && ms < 60000) return l.statisticsUnderMinute;
  final minutes = ms ~/ 60000;
  return minutes < 60
      ? l.statisticsMinutes('$minutes')
      : l.statisticsHoursMinutes('${minutes ~/ 60}', '${minutes % 60}');
}

enum StatisticsRange { week, month, year }

Future<void> showStatisticsSettings(
  BuildContext context,
  ReadingStatisticsController controller,
) => ShioriCapabilities.of(context).pointerFirst
    ? showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: ShioriLayout.panel),
            child: Padding(
              padding: const EdgeInsets.only(top: ShioriSpace.page),
              child: _RecordSettings(controller: controller),
            ),
          ),
        ),
      )
    : showShioriSheet<void>(
        context,
        builder: (_) => _RecordSettings(controller: controller),
      );

class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({super.key, required this.controller, this.images});
  final ReadingStatisticsController controller;
  final ImageRepository? images;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            DesktopPageChrome(
              child: DesktopPageToolbar(
                title: l.statisticsTitle,
                actions: [
                  IconButton(
                    onPressed: () =>
                        showStatisticsSettings(context, controller),
                    tooltip: l.statisticsManage,
                    icon: const Icon(Icons.settings_outlined),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StatisticsView(controller: controller, images: images),
            ),
          ],
        ),
      ),
    );
  }
}

class StatisticsNotice extends StatefulWidget {
  const StatisticsNotice({super.key, required this.controller});
  final ReadingStatisticsController controller;
  @override
  State<StatisticsNotice> createState() => _StatisticsNoticeState();
}

class _StatisticsNoticeState extends State<StatisticsNotice> {
  bool _shown = false, _visible = false;
  ReadingStatisticsController get controller => widget.controller;
  void _close() {
    setState(() => _visible = false);
    unawaited(controller.dismissNotice());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!_shown && controller.notice) {
        _shown = _visible = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) unawaited(controller.dismissNotice());
        });
      }
      if (!_visible || !controller.enabled) return const SizedBox.shrink();
      final l = AppLocalizations.of(context), theme = Theme.of(context);
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          ShioriSpace.page,
          ShioriSpace.medium,
          ShioriSpace.page,
          0,
        ),
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(ShioriShape.control),
          child: Padding(
            padding: const EdgeInsets.all(ShioriSpace.medium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.statisticsNoticeTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    IconButton(
                      onPressed: _close,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(l.statisticsNoticeBody, style: theme.textTheme.bodySmall),
                TextButton(
                  onPressed: () async {
                    _close();
                    if (context.mounted) {
                      await showStatisticsSettings(context, controller);
                    }
                  },
                  child: Text(l.statisticsManage),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class StatisticsView extends StatefulWidget {
  const StatisticsView({super.key, required this.controller, this.images});
  final ReadingStatisticsController controller;
  final ImageRepository? images;
  @override
  State<StatisticsView> createState() => _StatisticsViewState();
}

class _StatisticsViewState extends State<StatisticsView> {
  StatisticsRange _range = StatisticsRange.week;
  StatisticsRange _snapshotRange = StatisticsRange.week;
  DateTime? _snapshotToday;
  Timer? _dayTimer;
  ReadingStatisticsSnapshot? _snapshot;
  bool _loading = true, _failed = false;
  int _request = 0, _selected = 0;
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    unawaited(_load());
  }

  @override
  void dispose() {
    ++_request;
    _dayTimer?.cancel();
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  void didUpdateWidget(StatisticsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      unawaited(_load());
    }
  }

  void _changed() => unawaited(_load());
  Future<void> _load() async {
    final request = ++_request, range = _range;
    await widget.controller.ready;
    if (!mounted || request != _request) return;
    if (widget.controller.settings == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    final now = widget.controller.clock.now;
    final today = DateTime(now.year, now.month, now.day);
    final start = switch (range) {
      StatisticsRange.week => DateTime(today.year, today.month, today.day - 6),
      StatisticsRange.month => DateTime(
        today.year,
        today.month,
        today.day - 29,
      ),
      StatisticsRange.year => DateTime(today.year, today.month - 11),
    };
    _dayTimer?.cancel();
    _dayTimer = Timer(
      DateTime(now.year, now.month, now.day + 1).difference(now) +
          const Duration(seconds: 1),
      _changed,
    );
    final result = await widget.controller.repository.read(
      firstDay: readingDay(start),
      lastDay: readingDay(today),
      today: readingDay(today),
    );
    if (!mounted || request != _request) return;
    setState(() {
      _loading = false;
      switch (result) {
        case Success(:final value):
          if (value.settings.epoch != widget.controller.settings?.epoch) {
            _snapshot = null;
            _failed = true;
            return;
          }
          final changedRange = _snapshot == null || _snapshotRange != range;
          _snapshot = value;
          _snapshotRange = range;
          _snapshotToday = today;
          if (changedRange) {
            _selected = switch (range) {
              StatisticsRange.week => 6,
              StatisticsRange.month => 29,
              StatisticsRange.year => 11,
            };
          }
          _failed = false;
        case Failure():
          _failed = true;
      }
    });
  }

  void _selectRange(StatisticsRange value) {
    if (_range == value) return;
    setState(() {
      _range = value;
      _loading = true;
      _selected = 0;
    });
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context),
        theme = Theme.of(context),
        data = _snapshot?.settings.epoch == widget.controller.settings?.epoch
            ? _snapshot
            : null;
    final error = _failed || widget.controller.failure != null;
    if (data == null) {
      return Center(
        child: error
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(l.statisticsError),
                  TextButton(
                    onPressed: () =>
                        widget.controller.retry().then((_) => _load()),
                    child: Text(l.retryAction),
                  ),
                ],
              )
            : CircularProgressIndicator(semanticsLabel: l.loadingSettings),
      );
    }
    final today = _snapshotToday!;
    final shownRange = _snapshotRange;
    final first = switch (shownRange) {
      StatisticsRange.week => DateTime(today.year, today.month, today.day - 6),
      StatisticsRange.month => DateTime(
        today.year,
        today.month,
        today.day - 29,
      ),
      StatisticsRange.year => DateTime(today.year, today.month - 11),
    };
    final dates = List.generate(
      switch (shownRange) {
        StatisticsRange.week => 7,
        StatisticsRange.month => 30,
        StatisticsRange.year => 12,
      },
      (i) => shownRange == StatisticsRange.year
          ? DateTime(first.year, first.month + i)
          : DateTime(first.year, first.month, first.day + i),
    );
    final values = dates
        .map(
          (date) => shownRange == StatisticsRange.year
              ? data.days.entries
                    .where((e) => e.key ~/ 100 == readingDay(date) ~/ 100)
                    .fold(0, (a, e) => a + e.value)
              : data.days[readingDay(date)] ?? 0,
        )
        .toList();
    final locale = MaterialLocalizations.of(context);
    final todayMetric = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l.statisticsToday, style: theme.textTheme.bodyMedium),
        Text(
          readingDuration(l, data.today),
          style: theme.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w500,
            fontSize: 40,
          ),
        ),
      ],
    );
    Widget totalMetric(bool wide) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wide) ...[
          Text(l.statisticsLifetime, style: theme.textTheme.bodyMedium),
          Text(
            readingDuration(l, data.lifetime),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: ShioriSpace.small),
        ] else
          Text(
            '${l.statisticsLifetime} ${readingDuration(l, data.lifetime)}',
            style: theme.textTheme.bodySmall,
          ),
        if (data.settings.startedDay case final day?)
          Text(
            l.statisticsSince(locale.formatShortDate(readingDate(day))),
            style: theme.textTheme.bodySmall,
          ),
      ],
    );
    Widget summary(bool wide) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error)
          Padding(
            padding: const EdgeInsets.only(bottom: ShioriSpace.item),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.statisticsError,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      widget.controller.retry().then((_) => _load()),
                  child: Text(l.retryAction),
                ),
              ],
            ),
          ),

        if (wide)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: todayMetric),
              const SizedBox(width: ShioriSpace.page),
              Expanded(flex: 2, child: totalMetric(true)),
            ],
          )
        else ...[
          todayMetric,
          const SizedBox(height: ShioriSpace.small),
          totalMetric(false),
        ],
        if (!data.settings.enabled) ...[
          const SizedBox(height: ShioriSpace.small),
          Text(l.statisticsPaused),
          TextButton(
            onPressed: () => widget.controller.setEnabled(true),
            child: Text(l.statisticsEnable),
          ),
        ],
      ],
    );
    Widget trend(bool wide) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wide)
          Row(
            children: [
              Text(l.statisticsDuration, style: theme.textTheme.titleMedium),
              const SizedBox(width: ShioriSpace.item),
              Expanded(child: _rangeControl(context)),
            ],
          )
        else ...[
          Text(l.statisticsDuration, style: theme.textTheme.titleMedium),
          const SizedBox(height: ShioriSpace.small),
          _rangeControl(context),
        ],
        const SizedBox(height: ShioriSpace.item),
        Text(
          '${readingDuration(l, data.total)} · ${l.statisticsTotal}',
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: ShioriSpace.tight),
        Text(
          '${locale.formatShortDate(first)} – ${locale.formatShortDate(today)} · ${l.statisticsUntilToday}',
          style: theme.textTheme.bodySmall,
        ),
        if (_loading) const LinearProgressIndicator(),
        const SizedBox(height: ShioriSpace.medium),
        _ReadingChart(
          dates: dates,
          values: values,
          monthly: shownRange == StatisticsRange.year,
          selected: _selected,
          onSelect: (i) => setState(() => _selected = i),
        ),
      ],
    );
    Widget booksHeading(bool wide) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: wide ? kMinInteractiveDimension : 0,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(l.statisticsBooks, style: theme.textTheme.titleMedium),
          ),
        ),
        if (data.books.isEmpty && data.anonymous == 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: ShioriSpace.item),
            child: Text(
              !data.settings.enabled
                  ? l.statisticsPaused
                  : shownRange == StatisticsRange.week && data.lifetime == 0
                  ? l.statisticsEmpty
                  : l.statisticsPeriodEmpty,
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, bounds) {
        final gutter = bounds.maxWidth >= ShioriLayout.page
            ? ShioriLayout.gutter(bounds.maxWidth)
            : ShioriSpace.page;
        final wide =
            bounds.maxWidth >= 1000 &&
            MediaQuery.textScalerOf(context).scale(12) <= 18;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!wide) ...[
              summary(false),
              const SizedBox(height: ShioriSpace.section),
              trend(false),
              const SizedBox(height: ShioriSpace.section),
            ],
            booksHeading(wide),
          ],
        );
        final list = CustomScrollView(
          key: const PageStorageKey('reading-statistics'),
          shrinkWrap: wide,
          primary: wide ? false : null,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                wide ? 0 : gutter,
                wide ? 0 : ShioriSpace.item,
                wide ? 0 : gutter,
                0,
              ),
              sliver: SliverToBoxAdapter(child: heading),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: wide ? 0 : gutter),
              sliver: SliverList.builder(
                itemCount: data.books.length,
                itemBuilder: (context, index) =>
                    _book(context, data.books[index]),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                wide ? 0 : gutter,
                ShioriSpace.item,
                wide ? 0 : gutter,
                ShioriSpace.section,
              ),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (data.anonymous > 0)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          l.statisticsAnonymous,
                          style: theme.textTheme.bodyMedium,
                        ),
                        subtitle: Text(l.statisticsAnonymousHint),
                        trailing: Text(readingDuration(l, data.anonymous)),
                      ),
                    if (!wide) ...[
                      const SizedBox(height: ShioriSpace.item),
                      Text(
                        l.statisticsLocalOnly,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
        if (!wide) return list;
        Widget surface(Widget child) => Material(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(ShioriShape.card),
          child: Padding(
            padding: const EdgeInsets.all(ShioriSpace.page),
            child: child,
          ),
        );
        return Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              gutter,
              ShioriSpace.item,
              gutter,
              ShioriSpace.page,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: ShioriLayout.detail),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ShioriSpace.page,
                    ),
                    child: summary(true),
                  ),
                  const SizedBox(height: ShioriSpace.section),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: SingleChildScrollView(
                            primary: false,
                            child: surface(trend(true)),
                          ),
                        ),
                        const SizedBox(width: ShioriSpace.page),
                        Expanded(
                          flex: 2,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: surface(list),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: ShioriSpace.item),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: ShioriSpace.page,
                    ),
                    child: Text(
                      l.statisticsLocalOnly,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _rangeControl(BuildContext context) {
    final l = AppLocalizations.of(context), theme = Theme.of(context);
    final labels = [l.statisticsSeven, l.statisticsThirty, l.statisticsYear];
    final large = MediaQuery.textScalerOf(context).scale(12) > 15;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Container(
          height: kMinInteractiveDimension + (large ? ShioriSpace.item : 0),
          padding: const EdgeInsets.all(ShioriSpace.tight / 2),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(ShioriShape.control),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedAlign(
                  duration: ShioriMotion.of(context, ShioriMotion.transition),
                  alignment: Alignment(-1 + _range.index.toDouble(), 0),
                  child: FractionallySizedBox(
                    widthFactor: 1 / 3,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(
                          ShioriShape.control,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (final range in StatisticsRange.values)
                    Expanded(
                      child: Semantics(
                        selected: range == _range,
                        child: TextButton(
                          onPressed: () => _selectRange(range),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: ShioriSpace.tight,
                            ),
                            minimumSize: const Size(
                              0,
                              kMinInteractiveDimension,
                            ),
                            foregroundColor: range == _range
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          child: Text(
                            labels[range.index],
                            textAlign: TextAlign.center,
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: range == _range
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _book(BuildContext context, ReadingBookTime time) {
    final l = AppLocalizations.of(context), theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ShioriSpace.medium),
      child: Row(
        children: [
          SizedBox(
            width: ShioriSpace.section,
            height: kMinInteractiveDimension,
            child: time.summary == null
                ? const CoverPlaceholder()
                : BookCover(
                    book: time.summary!,
                    images: widget.images,
                    readMode: ReadMode.cacheOnly,
                  ),
          ),
          const SizedBox(width: ShioriSpace.medium),
          Expanded(
            child: Text(
              time.summary?.title ?? l.statisticsMissingBook,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ),
          const SizedBox(width: ShioriSpace.medium),
          Flexible(
            child: Text(
              readingDuration(l, time.milliseconds),
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadingChart extends StatelessWidget {
  const _ReadingChart({
    required this.dates,
    required this.values,
    required this.monthly,
    required this.selected,
    required this.onSelect,
  });
  final List<DateTime> dates;
  final List<int> values;
  final bool monthly;
  final int selected;
  final ValueChanged<int> onSelect;
  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context),
        locale = MaterialLocalizations.of(context),
        theme = Theme.of(context);
    final selected = this.selected.clamp(0, values.length - 1),
        maximum = values.fold(0, math.max);
    String date(int i) => monthly
        ? locale.formatMonthYear(dates[i])
        : locale.formatMediumDate(dates[i]);
    String label(int i) => '${date(i)} · ${readingDuration(l, values[i])}';
    void move(int direction) =>
        onSelect((selected + direction).clamp(0, values.length - 1));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          monthly ? l.statisticsHoursUnit : l.statisticsMinutesUnit,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: ShioriSpace.small),
        Semantics(
          label: l.statisticsChart,
          value: label(selected),
          slider: true,
          increasedValue: selected < values.length - 1
              ? label(selected + 1)
              : null,
          decreasedValue: selected > 0 ? label(selected - 1) : null,
          onIncrease: selected < values.length - 1 ? () => move(1) : null,
          onDecrease: selected > 0 ? () => move(-1) : null,
          child: CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
                  move(-1),
              const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
                  move(1),
            },
            child: Focus(
              child: LayoutBuilder(
                builder: (context, bounds) {
                  void pick(double x) => onSelect(
                    (x / bounds.maxWidth * values.length).floor().clamp(
                      0,
                      values.length - 1,
                    ),
                  );
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (e) => pick(e.localPosition.dx),
                    onHorizontalDragUpdate: (e) => pick(e.localPosition.dx),
                    child: SizedBox(
                      width: double.infinity,
                      height: 160,
                      child: CustomPaint(
                        painter: _Bars(
                          values: values,
                          maximum: maximum,
                          selected: selected,
                          color: theme.colorScheme.primary,
                          line: theme.colorScheme.outlineVariant.withValues(
                            alpha: .45,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        ExcludeSemantics(
          child: values.length == 30
              ? SizedBox(
                  height: math.max(
                    ShioriSpace.page,
                    MediaQuery.textScalerOf(
                          context,
                        ).scale(theme.textTheme.bodySmall!.fontSize!) *
                        (theme.textTheme.bodySmall!.height ?? 1.5),
                  ),
                  child: CustomMultiChildLayout(
                    delegate: _DateLabelLayout(values.length),
                    children: [
                      for (final i in [0, 14, 29])
                        LayoutId(
                          id: i,
                          child: Text(
                            '${dates[i].month}/${dates[i].day}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                )
              : Row(
                  children: [
                    for (var i = 0; i < dates.length; i++)
                      Expanded(
                        child: SizedBox(
                          height: ShioriSpace.page,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                monthly
                                    ? '${dates[i].month}'
                                    : '${dates[i].month}/${dates[i].day}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: ShioriSpace.small),
        Text(label(selected), style: theme.textTheme.bodySmall),
      ],
    );
  }
}

class _DateLabelLayout extends MultiChildLayoutDelegate {
  _DateLabelLayout(this.count);
  final int count;
  @override
  void performLayout(Size size) {
    for (final i in [0, 14, 29]) {
      final label = layoutChild(i, BoxConstraints.loose(size));
      final center = size.width * (i + .5) / count;
      positionChild(
        i,
        Offset(
          (center - label.width / 2).clamp(0, size.width - label.width),
          (size.height - label.height) / 2,
        ),
      );
    }
  }

  @override
  bool shouldRelayout(_DateLabelLayout oldDelegate) =>
      count != oldDelegate.count;
}

class _Bars extends CustomPainter {
  _Bars({
    required this.values,
    required this.maximum,
    required this.selected,
    required this.color,
    required this.line,
  });
  final List<int> values;
  final int maximum, selected;
  final Color color, line;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = line;
    for (var i = 0; i < 4; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    if (maximum == 0) return;
    final slot = size.width / values.length, width = math.min(24.0, slot * .64);
    for (var i = 0; i < values.length; i++) {
      if (values[i] == 0) continue;
      final height = (size.height - ShioriSpace.small) * values[i] / maximum;
      paint.color = i == selected ? color : color.withValues(alpha: .55);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            slot * i + (slot - width) / 2,
            size.height - height,
            width,
            height,
          ),
          const Radius.circular(ShioriShape.indicator),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_Bars old) =>
      old.values != values ||
      old.selected != selected ||
      old.color != color ||
      old.line != line;
}

class _RecordSettings extends StatefulWidget {
  const _RecordSettings({required this.controller});
  final ReadingStatisticsController controller;
  @override
  State<_RecordSettings> createState() => _RecordSettingsState();
}

class _RecordSettingsState extends State<_RecordSettings> {
  bool _busy = false, _failed = false;
  Future<void> _run(Future<bool> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await task();
    if (mounted) {
      setState(() {
        _busy = false;
        _failed = !ok;
      });
    }
  }

  Future<void> _clear() async {
    final l = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        title: Text(l.statisticsClearConfirm),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l.statisticsClearBody),
            if (widget.controller.enabled) ...[
              const SizedBox(height: ShioriSpace.medium),
              Text(l.statisticsClearEnabled),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(MaterialLocalizations.of(context).cancelButtonLabel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l.statisticsClear),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) await _run(widget.controller.clear);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final l = AppLocalizations.of(context),
          theme = Theme.of(context),
          c = widget.controller;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          ShioriSpace.page,
          0,
          ShioriSpace.page,
          ShioriSpace.page,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.statisticsManage,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                CloseButton(),
              ],
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l.statisticsRecording),
              subtitle: Text(
                c.enabled ? l.statisticsLocalOnly : l.statisticsPauseHint,
              ),
              value: c.enabled,
              activeTrackColor: theme.colorScheme.primary,
              onChanged: _busy || c.settings == null
                  ? null
                  : (value) => _run(() => c.setEnabled(value)),
            ),
            const SizedBox(height: ShioriSpace.medium),
            Text(l.statisticsRetention, style: theme.textTheme.bodySmall),
            if (_failed || c.failure != null) ...[
              const SizedBox(height: ShioriSpace.medium),
              Text(
                l.statisticsError,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              TextButton(
                onPressed: _busy
                    ? null
                    : () => _run(() async {
                        await c.retry();
                        return c.failure == null;
                      }),
                child: Text(l.retryAction),
              ),
            ],
            const SizedBox(height: ShioriSpace.item),
            TextButton(
              onPressed: _busy ? null : _clear,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.error,
              ),
              child: Text(l.statisticsClear),
            ),
          ],
        ),
      );
    },
  );
}
