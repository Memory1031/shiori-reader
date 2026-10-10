# UI 设计规范

Shiori 的视觉语言与组件约定。实现以 [主题与 token](../lib/app/theme/shiori_theme.dart) 为准；
本文说明这些 token 的用途和组合方式。界面任务的工作流程（观察、实现、渲染检查）见
[shiori-ui](../.agents/skills/shiori-ui/SKILL.md)。

## 设计方向

- **纸面与墨色**：安静的阅读工具，不是内容平台。暖白纸面、深灰墨色，一个低饱和强调色；
  封面是页面上唯一大面积的色彩来源。
- **克制的层级**：靠留白、字重和浅色底区分层级，少用描边、阴影和卡片。
  容器必须表达真实的分组或层级，不为装饰加框。
- **柔和的状态**：hover、按下、选中都是强调色的低透明度底色，不用 Material 的灰色遮罩和水波纹。
- **不使用**：新字体、装饰渐变、玻璃 / 模糊效果、hero 大图、夸张动效、彩色插画。

## 颜色

所有颜色从 `Theme.of(context).colorScheme` 或 `ShioriPalette` 读取，不在组件里写死色值。

| 角色 | ColorScheme | 用途 |
| --- | --- | --- |
| paper | `scaffoldBackgroundColor` | 页面背景、AppBar、导航栏 |
| surface | `surface` | 弹窗、菜单、底部弹层等浮起表面 |
| surfaceSubtle | `surfaceContainerHighest` | 输入框、占位封面、弹窗内列表底 |
| ink | `onSurface` | 正文与标题 |
| secondary | `onSurfaceVariant` / `bodySmall` | 次要文字、元数据、未激活图标 |
| separator | `outlineVariant` | 分隔线、描边 |
| accent | `primary` | 强调色，随用户设置变化 |
| accent fill | `primaryContainer`（浅色） | 浅色主题下 FilledButton 与导航指示器的淡色底 |
| error | `error` | 破坏性动作与失败状态 |

- 强调色有青绿、蓝灰、暖棕、淡粉四种，各有明暗两套。新设计在四种强调色和明暗主题下都要成立，
  不能只针对默认青绿调色。
- 强调色的常用透明度（叠在 paper 或 surface 上）：

  | 场景 | 透明度 |
  | --- | --- |
  | hover | .05（深色 .08）；列表行 .06 |
  | 按下 / 焦点 | .08（深色 .12）；列表行按下 .12 |
  | 选中常驻 | .08，hover 时 .11 |
  | 摘要底色 `summarySurfaceColor` | .06（深色 .08） |

- 分隔线一般用 `outlineVariant` 的 .45 透明度；需要更明显时直接用 `outlineVariant`。
- 封面上的角标使用半透明黑底（.42）配白字（.90），保证在任何封面上可读。

## 字体

字号与字重来自 `textTheme`，行高统一 1.5，letterSpacing 为 0。Windows 使用 Microsoft YaHei UI，
其他平台使用系统字体。

| 样式 | 规格 | 用途 |
| --- | --- | --- |
| `headlineSmall` | 24 / w600 | 少量页面级标题 |
| `titleLarge` | 20 / w600 | AppBar 标题、弹窗标题 |
| `titleMedium` | 17 / w600 | 分区标题 |
| `titleSmall` | 15 / w600 | 书名、列表主标题、弹窗内的状态摘要 |
| `bodyMedium` | 14 | 正文、弹窗说明、列表行文字 |
| `bodySmall` | 12 / secondary | 元数据、补充说明、计数 |
| `labelLarge` | 14 / w600 | 按钮 |

`ShioriType` 提供量表外的样式：`brand`（品牌字标）、`displayTitle`（详情页书名 22 / w600）、
`badge`（封面角标 10 / w500）。数字计数用 `FontFeature.tabularFigures()` 避免跳动。
不要用颜色或字号之外的方式（如下划线、斜体）强调。

## 间距、圆角与尺寸

**ShioriSpace**：`tight` 4 · `small` 8 · `medium` 12 · `item` 16 · `page` 20 · `section` 32。

- `tight` 用于图标与文字、标题与副标题之间；`small` 用于同组控件；`medium` 用于行内边距和
  相关块之间；`item` 用于列表项、卡片内边距；`page` 用于手机页面左右边距；`section` 用于区块之间。
- 需要不在量表中的值时，由 token 推导（如 `ShioriSpace.tight / 2`），不引入新的魔法数。

**ShioriShape**：`indicator` 2（进度条、细指示）· `tag` 4（角标）· `cover` 8（封面）·
`control` 12（按钮、输入框、列表行底色、菜单、弹窗内的列表底）· `card` 16（成组表面）·
`sheet` 20（底部弹层顶角）。封面比例固定 2:3（`coverRatio`）。

**触控尺寸**：按钮、图标按钮最小 48×48。桌面菜单项可以紧凑，触摸平台保留触控高度。

**ShioriLayout**：`page` 840 是手机底栏与桌面 rail 的分界，`sidebarBreakpoint` 1200 起
rail 变为带文字的侧栏；`list` 760 限制单列内容宽度，`panel` 560 限制弹窗与面板宽度；
书架、详情页的宽度与 gutter 见源码注释。

## 动效

- 只有两个时长：`feedback` 180ms（hover、选中、展开等小反馈），`transition` 240ms（页面级切换）。
- 时长一律经过 `ShioriMotion.of(context, …)`，系统开启“减少动态效果”时变为 0。
- 曲线以 `Curves.easeOut` 为主；勾选标记这类小元素可用 `easeOutBack` 轻微回弹。
- 状态切换不应改变布局几何：焦点框、选中标记用 `foregroundDecoration` 或叠加层绘制，
  不增减 padding。

## 交互状态

| 状态 | 表现 |
| --- | --- |
| hover | 强调色淡底；列表行同时把书名染为强调色 |
| 按下 | 底色加深，无水波纹（主题已设 `NoSplash`） |
| 键盘焦点 | 底色 + 1.5px 强调色描边（封面卡片用更粗的描边） |
| 选中 | 常驻淡底 + 圆形勾选标记；书名保持墨色 |
| 禁用 | 主题默认的降低不透明度；用 Tooltip 说明禁用原因 |

- 选中、hover 和焦点必须能同时看出来，且不只依赖颜色：选中有勾选图标，
  并通过 `Semantics(checked/selected)` 暴露给辅助功能。
- 底色从内容边缘内缩并带圆角（`BookListItem.inset`、`ShioriMenuItem`），不画通栏色带。
  相邻两行的底色之间留出间隙（`BookListItem.gap`），连续选中时仍能分辨每一行。

## 组件

### 书籍封面与列表

- `BookCover`：圆角 `cover`、2:3 比例。没有封面时使用 `CoverPlaceholder`，书脊处有一条强调色竖线，
  `tinted` 可区分格式。封面网格保持几何稳定，选择模式不改变卡片尺寸。
- `BookListTile`：64 宽的封面 + 最多两行书名 + 可选副标题 + 底部元数据 + 与书名对齐的尾部动作。
- `BookListItem`：列表行的交互外壳，负责内缩圆角底色、焦点描边和底部分隔线。
  行处于激活或选中状态时分隔线变透明，让底色成为一个完整的表面。新的书籍列表复用这两个组件。

### 按钮与动作权重

- `FilledButton`：页面或弹窗的主要动作。浅色主题下是强调色淡底配墨色字，不用饱和实色。
- `FilledButton.tonal`：管理类动作（如重新解析）。
- `OutlinedButton`：次要动作；破坏性动作在工具栏中用 error 色描边与文字，不作为视觉重点。
- `TextButton`：取消、完成等低权重动作。
- 弹窗中确认破坏性操作时，确认按钮用 error 底色的 `FilledButton`。
- 动作名称在入口按钮、弹窗标题和确认按钮之间保持一致。

### 菜单

使用 `ShioriMenuItem`（可带前置图标）。菜单表面为 surface、`control` 圆角、细描边和轻阴影，
从锚点下方弹出。桌面书籍菜单支持右键、Menu 键与 Shift+F10。

### 弹窗

- 面板类交互（选择、确认、进度、结果）在触摸平台用底部弹层，在桌面（pointer-first）用居中弹窗，
  由 `ShioriCapabilities.of(context).pointerFirst` 决定，同一份内容两种外壳（如 `showAppAppearance`、
  `BookBatchPanel`）。底部弹层的动作按钮在底部等分整行，次要动作用 `OutlinedButton`；
  弹窗的动作靠右，次要动作用 `TextButton`。
- 弹窗使用 `AlertDialog`，最大宽度 `ShioriLayout.panel`，内容可能变长时设置 `scrollable: true`。
- 结构从上到下：标题（动作名）→ 一句话说明 → 后果提示 → 涉及对象 → 补充说明 → 动作按钮。
- **后果提示**：20px 图标 + 文字的一行。破坏性后果用 error 色图标，可撤销的后果用 secondary 色。
- **对象列表**：放在 `surfaceContainerHighest` .6 透明度、`control` 圆角的浅底区域中，
  与上方说明文字分开。每行是 18px 图标 + 文字；图标表示格式（EPUB / TXT / 在线）或结果
  （成功 primary、失败 error、未处理 / 跳过 secondary）。行之间用对齐文字起点的细分隔线。
  三项以内按内容高度显示，更多时在固定高度内滚动。
- 内容列使用 `CrossAxisAlignment.stretch`，列表区域与弹窗内最宽的文字同宽。
  不要让列表固定在较窄宽度，在右侧留出空白。
- **结果摘要**：状态图标 + `titleSmall` 摘要。已完成的对象默认折叠；
  失败和需要关注的对象直接列出，并在每行下方写明原因。
- **补充说明**：`bodySmall` secondary 小字（如清理将在下次启动时进行），不和正文同字号。
- **进度**：当前对象名与 `当前 / 总数` 在同一行，下方是 4px 高、圆角的线性进度条。
- 可展开的区块（`ExpansionTile`）：头部的 hover 底色左右要有内边距，与列表行文字对齐；
  展开内容与头部之间留间隙，避免两块底色相接。

### 底部弹层与状态页

- 底部弹层统一用 `showShioriSheet`：在 root navigator 打开，顶角圆角 `sheet`，带拖动把手，
  处理底部安全区，尊重减少动态效果。高度用 `fit` / `half` / `tall`。需要自己移除路由的流程用
  `shioriSheetRoute`；进行中不可中断的弹层设为不可关闭（无把手、不可拖动和点遮罩关闭）。
- 加载、空、失败使用 `LoadingView`、`EmptyView`、`FailureView`。空状态插画使用代码绘制的
  简单图形（`EmptyBooks`），不使用远程资源或加载动画。

### 选择模式

- 手机端由更多菜单进入，桌面端由工具栏的多选按钮进入；标题栏替换为“已选 N 本”加退出、全选，高度与原标题栏一致；
  按钮位置不随选中数量变化。
- 手机端动作放在底部栏，底部栏带一行固定的范围提示；桌面端动作放在页面工具栏右侧。
- 网格中被选中的封面加强调色描边和淡色叠层，勾选标记带 paper 色光晕以便在封面上可读。
  列表中被选中的行使用常驻底色，勾选标记放在尾部。
- 勾选标记只是指示器，不是第二个点击目标；整行或整张卡片负责点击和语义。

## 平台与响应式

- 手机触摸优先：48 触控尺寸、底部操作栏、SafeArea，左右边距 `page`。
- Windows 鼠标键盘优先：hover 反馈、键盘焦点、右键菜单、Esc 返回，菜单和行可以更紧凑。
  桌面页面框架与工具栏使用 `DesktopContentFrame`、`DesktopPageToolbar`，
  布局规则见[架构与数据规则](architecture.md#桌面工作区)。
- 跨越断点时保留滚动位置、焦点和业务状态；工具栏动作换行而不挤压标题。

## 文案与可访问性

- 所有可见文字放在 `app_zh.arb` / `app_en.arb`，英文通常更长，布局要能容纳。
- 书名最多两行，超出时省略；数量、状态必须用文字表达，图标只作为辅助。
- 只用图标表达的状态要提供 `semanticLabel` 或 `Semantics`；图标按钮要有 tooltip。
- 失败信息说明原因和用户能做什么，不展示站点原始响应。

## 交付前自检

- 四种强调色、明暗主题、中英文、手机与桌面宽窄窗口下，层级和对齐是否一致。
- 长书名、大数量、禁用态、最后一项与底栏的距离，以及状态切换时有无位移。
- 相邻底色是否粘连，底色与边缘、与其他表面之间是否有呼吸空间。
- 是否只用了已有 token；新增值能否由已有 token 推导。
