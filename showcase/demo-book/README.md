# 《蓝色借书卡的最后一栏》

Shiori 的独立原创展示小说。中文与完整英文版各七章，共用一张女主封面与三张剧情彩插。故事发生在日本濑户内海沿岸的架空汐见町，主要人物为七濑澪、藤原律与秋山澄。

女主七濑澪为17岁的高二女生，身高约150厘米、黑长直；插画采用清晰线条与平涂的萌系风格，统一夏季水手服。

这篇青春日常与轻悬疑故事使用可搜索、可重排的 Unicode 正文，适合演示普通分页、宽屏双页、插图、目录、全文搜索、用户书签和位置回跳。

## 文件

- `dist/shiori-demo-zh.epub`：完整简体中文版。
- `dist/shiori-demo-en.epub`：完整英文版，人物、情节和章节顺序与中文一致。
- `dist/cover-zh.jpg`、`dist/cover-en.jpg`：共用的日文竖排主标题封面，不额外标注语种。
- `dist/SHA256SUMS.txt`：成品摘要；`build-info.json` 记录影响封面编码的工具与字体摘要。
- `story/zh/`、`story/en/`：UTF-8 正文，每章一个纯文本文件，第一行为章名。
- `story/continuity.json`：人物、时间线、悬念事实与中英术语表，包含剧透。
- `artwork/cover/`、`artwork/illustrations/`：四张无字 PNG 原图。
- `artwork/fonts/`：封面标题专用 Mochiy Pop One 原字体与 SIL OFL 1.1 许可。
- `artwork/art-direction.json`：统一人物设定、逐图场景提示、原图摘要、替代文本及插入位置。
- `epub/styles/book.css`：简洁的流式排版样式。
- `tools/`：打包、独立结构校验及 Shiori 组件验收入口。

## 重新生成 EPUB

使用 Python 3.11+，安装锁定的 Pillow：

```sh
python3 -m pip install -r showcase/demo-book/tools/requirements.txt
python3 showcase/demo-book/tools/build.py
python3 showcase/demo-book/tools/validate.py
```

默认使用随源文件保留的日文字体 **Mochiy Pop One**。它的粗圆轮廓配合蓝白粗描边与错位阴影，用于醒目的萌系轻小说封面标题「青い貸出カードの最後の空欄」。两列从右到左排列，使用真正的竖排字形替换，包含「カード」的长音符。Pillow 需支持 libraqm；官方常见平台 wheel 已包含，可用 `python3 -c 'from PIL import features; print(features.check_feature("raqm"))'` 检查。

其他系统也可指定有权使用、支持日文竖排的标题字体，例如：

```sh
python3 showcase/demo-book/tools/build.py --cover-font /path/to/Japanese-font.otf --font-index 0
```

字体来自 [Google Fonts 的 Mochiy Pop One](https://github.com/google/fonts/tree/main/ofl/mochiypopone)，原样随打包源文件保留，遵循旁置的 SIL OFL 1.1；仅用于在封面光栅图上排标题，不嵌入 EPUB。无字原图始终保留；三张彩插只做 JPEG 编码，不裁切、拉伸或覆盖正文。字体、字体索引、Pillow 及字体渲染库相同时，固定元数据、文件顺序和 ZIP 时间戳可生成字节一致的成品。更换字体会改变封面及 EPUB 摘要。`build-info.json` 保留对应版本与字体摘要。

修改正文时同步维护另一语言的对应章节；修改章名时也更新 `metadata.json`。插画在章节内通过文本锚点定位，锚点变动会使构建明确失败，不会静默漏图。第五章有一处指向第一章卡片描述的普通书内链接，用于读者对照线索。

## 校验与阅读检查

`validate.py` 独立检查 ZIP 与 `mimetype`、XML、OPF、spine、七章目录、全部资源与 fragment 引用、图片字节、语言、替代文本、每一段正文及成品摘要，并检查没有脚本、嵌入字体或外部资源依赖。另可使用官方 EPUBCheck：

```sh
java -jar /path/to/epubcheck.jar showcase/demo-book/dist/shiori-demo-zh.epub
java -jar /path/to/epubcheck.jar showcase/demo-book/dist/shiori-demo-en.epub
```

从仓库根目录使用固定 Flutter 工具链运行实际文件的组件验收：

```sh
fvm flutter test --no-pub showcase/demo-book/tools/shiori_smoke_test.dart
```

该入口使用真实 `BookDecoder`、托管文件、SQLite、阅读仓库、封面组件及 Reader，在线依赖明确禁止访问；其接口基于 Shiori v1.4.0，后续应用接口变化时可单独维护，不影响 Python 打包。可用 `SHIORI_DEMO_FONT` 指定本地 CJK 阅读检查字体，`SHIORI_DEMO_EVIDENCE` 指定少量诊断渲染输出目录；这些不写入小说，也不是 README 产品截图流水线。

组件验收不能代替 Android、iOS、Windows、macOS 发布安装包的真实系统运行。新版本重做产品图前，仍应在对应版本中实际导入这两个文件，检查书架封面、目录、正文与插图、搜索命中及多个书签跳转。

## 创作与素材边界

本套内容由 AI 辅助完成小说创作、编辑、英文翻译与插画制作，是 Shiori 的原创示例内容，不是第三方出版作品。插图由 ImageGen 生成，后三张参考封面原图保持同一女主形象；没有使用私人 EPUB 内容、网络动漫图片、既有作品角色或指定在世画师的模仿提示。

本目录供 Shiori 产品展示、中文与英文界面示例、后续官网与版本截图复用，未加入 Flutter 生产 assets，也不随阅读器安装。

小说与插图未另设 CC0、CC BY 等独立开放许可。仓库代码的 MIT 许可不自动适用于这些展示素材；第三方使用授权由项目维护者另行明确。标题字体保留其自身的 SIL OFL 许可。AI 辅助制作及初步相似性检查不等于绝对不存在权利争议。
