// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get historyTitle => '最近阅读';

  @override
  String get historyClear => '清除此书阅读记录';

  @override
  String get chapterFallback => '原章节已不在目录中，已打开相邻章节。';

  @override
  String get historyEmpty => '暂无阅读记录。';

  @override
  String get shelfTitle => '书架';

  @override
  String get noSources => '暂无可用书源，已保存书籍仍保留在书架。';

  @override
  String get discoverEmpty => '暂无推荐内容。';

  @override
  String get importTitle => '导入';

  @override
  String get importPending => 'TXT / EPUB 导入及通过其他应用打开已纳入规划，仍在开发中。';

  @override
  String get discoverUnsupported => '该书源不提供推荐，请使用搜索查找小说。';

  @override
  String get discoverTitle => '发现';

  @override
  String get shelfEmpty => '书架暂无书籍。';

  @override
  String get shelfUndo => '撤销移除';

  @override
  String get shelfLayout => '切换书架布局';

  @override
  String get nextChapter => '下一章';

  @override
  String get previousChapter => '上一章';

  @override
  String get catalogUnnamedVolume => '未命名卷';

  @override
  String get catalogStale => '已保存的目录可能不是最新内容。';

  @override
  String get catalogEmpty => '暂无章节。';

  @override
  String get detailRefresh => '刷新详情';

  @override
  String get detailStale => '已保存的详情可能不是最新信息。';

  @override
  String get detailStart => '开始阅读';

  @override
  String get detailContinue => '继续阅读';

  @override
  String get detailAddShelf => '加入书架';

  @override
  String get detailRemoveShelf => '移出书架';

  @override
  String get detailActionsPending => '暂不可用的阅读和书架操作仍在开发中。';

  @override
  String get detailSynopsis => '简介';

  @override
  String get detailNoSynopsis => '暂无简介。';

  @override
  String get detailCover => '书籍封面';

  @override
  String get detailStatusUnknown => '连载状态未知';

  @override
  String get detailStatusOngoing => '连载中';

  @override
  String get detailStatusCompleted => '已完结';

  @override
  String get detailStatusHiatus => '暂停连载';

  @override
  String get searchKeyword => '书名或关键词';

  @override
  String get searchInitial => '输入关键词后，点击搜索。';

  @override
  String get searchNoResults => '没有找到小说，试试其他关键词。';

  @override
  String get searchNoMore => '已显示全部结果';

  @override
  String get searchDraftNotice => '当前为上次搜索结果，请提交修改后的关键词重新搜索。';

  @override
  String searchResultsFor(String query) {
    return '“$query”的搜索结果';
  }

  @override
  String get devSearchTitle => '离线搜索';

  @override
  String get devSearchHint => '搜索“a”可体验分页并查看离线小说详情。';

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

  @override
  String get readerSettings => '阅读设置';

  @override
  String get readerFontSize => '字号';

  @override
  String get readerLineHeight => '行高';

  @override
  String get readerParagraphSpacing => '段间距';

  @override
  String get readerHorizontalPadding => '横向边距';

  @override
  String get readerThemeSystem => '跟随系统';

  @override
  String get readerThemeLight => '浅色';

  @override
  String get readerThemeDark => '深色';

  @override
  String get readerSettingsFailure => '无法读取或保存阅读设置。';

  @override
  String get readerReset => '恢复默认';

  @override
  String get readerProgressUnsaved => '阅读进度暂未保存，点按重试。';

  @override
  String get labTitle => '视觉样板';

  @override
  String get labNotice => '离线视觉样板 · 不修改书架数据';

  @override
  String get labShelf => '书架';

  @override
  String get labDetail => '小说详情';

  @override
  String get labReader => '阅读器';

  @override
  String get labContinue => '继续阅读';

  @override
  String get labMyBooks => '我的书架';

  @override
  String get labDiscover => '发现';

  @override
  String get labChapter => '第一章 · 末班列车';

  @override
  String get labProgress => '本章约 36%';

  @override
  String get labAuthor => '栞文库编辑室';

  @override
  String get labBook1 => '夏日尽头的车站';

  @override
  String get labBook2 => '寄往月亮的信';

  @override
  String get labBook3 => '雨中的城市';

  @override
  String get labBook4 => '海风起时';

  @override
  String get labLongTitle => '那个夏天，我们追着末班列车来到世界尽头，发现了一封寄给明天的信';

  @override
  String get labSynopsis =>
      '没有名字的车站，每到夏天都会收到一封信。这一次，寄信人却尚未出生。沿着海岸线，少女与少年寻找信中的地址，也寻找那些来不及说出口的约定。';

  @override
  String get labParagraph =>
      '站台上很安静。铁轨的另一边，海面收拢了午后最后的光。她小心地拆开信封，仿佛整个夏天都会从那道窄窄的缝隙里溜走。\n信的开头，写着明天的日期。身后的某个地方，铃声轻轻响了一次。';

  @override
  String get labCatalog => '目录';

  @override
  String get labSave => '加入书架';

  @override
  String get labSaved => '已加入书架';

  @override
  String get labEmpty => '下一段故事，正在等你。';

  @override
  String get labSearch => '去找一本书';

  @override
  String get labImport => '导入文件';

  @override
  String get labNormal => '正常内容';

  @override
  String get labLong => '长标题';

  @override
  String get labMissing => '缺封面';

  @override
  String get labEmptyState => '空状态';

  @override
  String get labLoading => '加载';

  @override
  String get labError => '错误';

  @override
  String get labPreviewAction => '仅为样板，此操作将在对应功能任务接通。';

  @override
  String get labSize => '画布宽度';

  @override
  String get labScale => '文字缩放';

  @override
  String get labNight => '深色';

  @override
  String get labIllustration => '自制几何封面插画';

  @override
  String get labSettings => '阅读设置';

  @override
  String get labFullscreen => '全屏预览';

  @override
  String get readerRestoreNearby => '内容更新，已恢复到附近位置';

  @override
  String get readerRestoreReadFailed => '暂时无法读取旧进度，已暂停保存；点按重试恢复';

  @override
  String get appAppearance => '应用外观';

  @override
  String get appAppearanceDescription => '仅影响应用页面；阅读配色单独设置。';

  @override
  String get readerColors => '阅读配色';

  @override
  String get readerPaper => '纸白';

  @override
  String get readerWarm => '暖纸';

  @override
  String get readerNight => '夜间';

  @override
  String get readerControlsHint =>
      '点按正文中间显示或隐藏工具栏。分页模式点按两侧翻页，滚动模式上下拖动；模式在排版设置中切换。';

  @override
  String get readerGotIt => '知道了';

  @override
  String get readerPreviousPage => '上一页';

  @override
  String get readerNextPage => '下一页';

  @override
  String readerChapterProgress(int percent) {
    return '本章约 $percent%';
  }
}
