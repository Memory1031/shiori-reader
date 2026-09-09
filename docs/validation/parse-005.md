# PARSE-005：显式重解析与位置迁移

2026-09-09。依据[已确认设计](parse-005-design.md)实施；本轮只运行离线测试，不启动设备或模拟器。

## 行为

本地文件管理菜单新增“重新解析”，确认后从托管原件解析。保留书籍 SHA-256、导入日期、书架加入日期和最后阅读时间；无阅读历史不会新建进度。旧 TXT 未记录编码时提供严格预览及手选；新 TXT manifest 保存已选编码，重解析入口允许覆盖。

位置迁移为纯 Dart 函数：同 revision/块身份、唯一语义及邻近上下文、最多三个相邻块的文本窗口，最后降级到同章比例或最近可读章节起点。文本按 Unicode code points 计数。窗口最多 16384 code points，局部锚点最多前后各 32 个，重复候选不强行当作精确。拆分/合并窗口恢复及比例恢复均显示近似提示；近似结果清 completed，所有结果清像素提示。短文本、不唯一或窗口外的修改允许降级，不承诺原行位置。

旧 EPUB 读取不再把新解析的 catalog/chapters/navigation 替换进内存记录。旧特殊页仅在对应正文 revision 相符时派生；新 bundle 内保存受限呈现 JSON，hash 进入受校验 manifest。原件与媒体仍各自校验 SHA-256。

## 发布与竞态

- 用户库 v4：local_books 增加 active_bundle、parser_version、maintenance，另增 local_chapter_revisions。NULL bundle 兼容旧根目录格式；升级不自动重新解析。
- 原件长期只保留根目录一份。暂存副本用于解析，完成后删除副本，manifest/媒体/呈现进入不可变 revisions/bundle。
- SQL 同一事务更新活动 bundle/hash、已有书架快照、进度与 generation、章节版本索引。提交前取消或 SQL 失败不切换；提交后返回真实成功，清理失败使用 cleanupPending。
- 维护期间拒绝新进度会话及旧写，发 invalidation 退役 Reader。结束后本地仓库发布 detail/catalog/chapter 更新；目录和特殊页后续读取取当前版本。即使旧内容重新申请 generation，正文/catalog revision 校验也拒绝不匹配写入。
- 迁移快照记录 generation/sequence，最终提交重新核对。期间 clearHistory 会改变 stamp 并阻止发布，不恢复用户刚清除的历史。普通进度保存被 maintenance 阻止，不覆盖待迁移快照。
- 启动先读 SQL 再清 staging/未引用 revisions，并解除遗留 maintenance。活动 manifest 缺失或校验失败时保留已有文件，不因坏指针删除旧资料。不是提供历史版本回滚 UI；正常提交后回收旧资源，避免版本无限累积。
- 文件发布仍依赖已有 flush + rename + SQLite 事务策略。测试覆盖人工构造崩溃遗留状态，未执行物理断电或真实磁盘耗尽，不宣称硬件掉电证明。

## EPUB occurrence

EPUB 3 同一规范资源路径出现多次时逐次呈现；首次章键不变，后续以独立摘要 kind 和 `[path, occurrence]` 派生，避免与路径字符串冲突。复用资源块、媒体和呈现；额外重复块预算 100000、spine 条目 10000，超限拒绝。

EPUB 2 重复引用保持拒绝；只有明确 package version=3.0 使用 EPUB 3 分支。nav/NCX href/fragment 指向首次出现，连续阅读按实际 spine 顺序。插入同资源 occurrence 可能改变后续身份，不承诺永久稳定。脚注返回 occurrence、辅助链接及 linear=no 阅读策略仍归 PARSE-008。

## 验证

新增测试覆盖：无历史、精确恢复、缩进变化、Unicode 拆分、合并、重复文字、删章、图片、旧 revision 不匹配；原件损坏、提交触发器失败、取消、预览中清历史、新/旧会话仲裁；提交前/后遗留目录、坏活动指针保护；EPUB 三次呈现和目录首目标、EPUB 2 拒绝；v1/v2/v3 升级、v3 原数据保留、v4 DDL 失败回滚；中英文入口、近似提示、取消和活跃 Reader 退役。

完整离线测试 545 项通过；补充已发布 bundle 的特殊页和图片读取后，11 项存储专项通过。静态分析无问题，数据库生成代码与快照重跑后哈希一致。未执行 Android/iOS 安装或运行、未发布版本、未修改真实电子书或用户数据库。
