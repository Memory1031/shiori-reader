// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get readerImagePlaceholder => '插图';

  @override
  String get hideReaderControls => '隐藏阅读操作栏';

  @override
  String get showReaderControls => '显示阅读操作栏';

  @override
  String get readerExperimentAction => '视口实验';

  @override
  String get accessRestrictedMessage => '此内容的访问受到限制。';

  @override
  String get catalogTitle => '目录';

  @override
  String get loadMoreAction => '加载更多';

  @override
  String get openReaderAction => '打开阅读器';

  @override
  String get pagedReading => '左右翻页';

  @override
  String get scrollReading => '上下滚动';

  @override
  String get appTitle => 'Shiori';

  @override
  String get backAction => '返回';

  @override
  String get cacheFailureMessage => '缓存暂时不可用，内容可能尚未保存到本地。';

  @override
  String get cacheMissMessage => '暂无可用缓存，请联网后再试。';

  @override
  String get connectionFailureMessage => '无法连接，请检查网络后重试。';

  @override
  String get databaseFailureMessage => '本地存储发生问题，暂时无法完成操作。';

  @override
  String get featurePending => '此功能尚在开发中。';

  @override
  String get loading => '正在加载…';

  @override
  String get loadingSettings => '正在读取设置';

  @override
  String get notFoundMessage => '未找到这项内容。';

  @override
  String get novelDetailsTitle => '小说详情';

  @override
  String get parseFailureMessage => '内容格式可能已变化，暂时无法读取。';

  @override
  String get rateLimitedMessage => '请求过于频繁，请稍后再试。';

  @override
  String get readCacheAction => '读取缓存';

  @override
  String get readerTitle => '阅读';

  @override
  String get readingFeaturesPending => '阅读功能正在准备中。';

  @override
  String get retryAction => '重试';

  @override
  String get searchTitle => '搜索';

  @override
  String get sessionFailureMessage => '访问会话不可用，请稍后再试。';

  @override
  String get sourceUnavailableMessage => '内容服务暂时不可用，请稍后再试。';

  @override
  String get tooLargeMessage => '内容超出当前可处理的大小。';

  @override
  String get unsupportedMessage => '暂不支持此功能。';
}
