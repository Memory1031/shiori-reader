---
name: shiori-ui
description: Design, implement, or refine Shiori Flutter interfaces across Android, iOS, and Windows. Use for screens, components, dialogs, toolbars, interaction states, and visual polish. Preserve the existing design system and validate rendered UI.
---

# Shiori UI

这是 Shiori 自有的 Flutter 界面工作流。先完整读取固定版本的
[frontend-design](../frontend-design/SKILL.md)，再按本项目的产品约束应用其设计与自检指导。
使用已固定版本，不自动从上游 main 更新；纯解析、存储和算法任务无需加载设计技能。

## 观察现有产品

- 先查 [文档导航](../../../docs/README.md)，读取受影响模块的当前合同。
- 读取 [UI 设计规范](../../../docs/design.md)、[主题与 token](../../../lib/app/theme/shiori_theme.dart)
  及当前页面源码。
- 对照现有书架、BookListItem/BookListTile、DesktopContentFrame/DesktopPageToolbar、
  ShioriMenuItem 与实际使用的弹层；按任务需要读取其实现，不照搬旧原型。
- 在改动前用正常运行入口或生产组件的 widget 绘制观察界面。记录要改变的区域、
  要保留的正文与封面几何，以及普通／交互／处理中／失败状态的层级。
- 用现有 token 名称简短说明方向后继续实施；无业务歧义时不增加设计审批阶段。

## Flutter 适配

- 保留纸面与表面颜色、用户强调色、现有字体及中文回退。
  复用 ShioriSpace、ShioriShape、ShioriType、ShioriMotion 和主题控件，不复制常量色板。
- 通用网页的 hero、展示字体与大胆视觉建议服从 Shiori 的既定方向。
  不借 UI 任务重塑品牌，不引入网页栈、WebView、新字体、装饰渐变或玻璃效果。
- 优先组合现有 Material/Cupertino 与 Shiori 控件；容器、描边和阴影须表达真实层级，
  不给每个小状态加装饰卡片，不为风格差异重写可靠基础控件。
- 手机触摸优先，Windows 鼠标键盘优先。响应式布局保留焦点、滚动和业务状态；
  对齐既有内容轴，控制状态切换的几何跳动，考虑 SafeArea、键盘和长文本。
- 管理动作与破坏性动作区分权重。适用范围、禁用原因、删除后果与逐项失败信息
  必须可理解；保持动作命名一致，新增文案使用中英文 ARB。
- 选中、hover 和键盘焦点可同时辨识；保留图标、文字及 checked/selected 等语义，
  不只依赖颜色。交互反馈使用 ShioriMotion.of，尊重减少动态效果设置。

## 检查实际渲染

- 实现后运行真实 Flutter 组件，导出、实际打开并逐图检查代表场景。
  按风险组合手机网格／列表、桌面宽窄窗口、明暗主题、英文与较大系统文字。
- 检查层级、文字图标对齐、选中与焦点、长标题与数量、控件禁用态、正文空间、
  底栏和最后一项、删除后果以及状态切换的位移。发现问题后修正并重截受影响场景。
- 截图使用合成数据或获授权素材；本机字体只用于预览，不复制入仓库。
  截图和临时视觉记录放忽略目录，不以 HTML 仿图或生成图片替代验收。
- 按 [开发说明](../../../docs/development.md) 运行适当功能回归；截图不能替代数据、
  取消与生命周期测试。按根 AGENTS.md 恢复临时入口与构建参数。
- 交付说明实际查看的场景、修正及未运行的平台；widget 绘制不等于设备验收。
