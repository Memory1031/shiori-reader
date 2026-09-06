# LightNovel SRC-002 samples

采集日期 2026-09-06，Asia/Shanghai。这里只包含调查证据与合成输入，不代表生产 Source 或 Parser 已实现。

- `captured/`：独立无凭据 HTTP 响应的自动白名单投影，或正文结构统计；保留实际字段类型和选定值，但省略大量字段，不可视作完整响应。
- `browser-observations.json`：人工转录的 UI / DOM / 资源 URL 证据；不冒充 Network payload。
- `initial-http-observations.json`：早期四次 HTTP 检查的人工转录，记录成功输入与选定响应事实；不是再次访问生成的自动 capture。
- `synthetic/`：根据已观察标签与设计需求自行编写，文字全为合成。极长单段等设计 case 不表示网站返回过该形状。
- `assets/synthetic-checker.png`：程序生成的 2×2 黑白 PNG，非源站图片。

`manifest.json` 给出每个文件的 provenance、operation、校验哈希和预期用途。字段被省略不等于原响应没有该字段；不从 summary 文件反推完整 schema。请求 Header 见 manifest 的共享 profile，只有“组合成功”的证据，没有逐字段必要性证明。

后续可验证：搜索请求 page 0/1 映射响应 page 1/2，且分别匹配浏览器 ID 顺序；空结果 page_count=1 / has_next=0；四卷章节数量 2/1/1/6，总数 10；默认章 309555 属于卷 44117；API 和 DOM 都观察到 4084 个 p / 14 个 img。ID 在应用内应转换为带 source scope 的字符串；此处记录源返回类型。

不保存正文、评论、用户信息、Cookie / token / security_key 值、图片签名 query、外部下载口令、HAR 或原图。真实正文禁止未经允许转载的提示已记入调查文档。哈希用于检查文件完整性，不证明真实性、许可或网站未来稳定性。

本任务只做离线 JSON / 引用 / 哈希 / 一致性 / 脱敏检查。可执行的独立 Dart probe、Parser 回归和 live 开关属于 SRC-003 及后续任务，不能把本目录当作已实现的 Source。
