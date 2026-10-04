# 来源、许可证和实现性质

本库是由协议标准设计并以 MoonBit 编写的独立实现，开发中使用 AI 辅助。没有逐文件移植 libcoap、aiocoap 或 pcap，没有复制这些项目的实现源码或测试用例。语言骨架和 Apache-2.0 LICENSE 由 `moon new` 生成。测试场景和互通脚本为本项目新增。

| 来源 | 用途与范围 | 许可证/权利说明 |
| --- | --- | --- |
| [RFC7252](https://www.rfc-editor.org/rfc/rfc7252) | 报文与基础交换行为规范；无规范代码片段复制 | IETF Trust/BCP78；不以本项目 Apache 许可证重新授权规范文本 |
| [RFC6690](https://www.rfc-editor.org/rfc/rfc6690) | 资源发现语法与过滤语义；无规范代码片段复制 | IETF Trust/BCP78 |
| [MoonBit Core](https://github.com/moonbitlang/core) | UTF-8、字节/集合、随机源、断言和调试，随工具链提供 | Apache-2.0；源码不纳入本项目有效行数 |
| [moonbitlang/async](https://github.com/moonbitlang/async) 0.22.4 | 官方公开 UDP 与 async API，Native 传输依赖 | Apache-2.0；依赖由包管理器取得，不复制源码 |
| [aiocoap](https://codeberg.org/aiocoap/aiocoap) 0.4.17 | Python 外部互通测试端，非产品主体 | 已安装发行元数据为 `MIT AND BSD-3-Clause`；本项目不再分发其源码 |
| [libcoap](https://github.com/obgm/libcoap) | 选题阶段成熟 CoAP 实现的功能参考 | 不复制、不绑定、不发布其代码；本次互通实际使用 aiocoap |
| [moonbit-pcap](https://github.com/cghyyrrt/moonbit-pcap) | 查重阅读对象 | 不导入或复制；功能差异记录于 RULES_AND_DUPLICATION.md |

GitHub Actions 使用 actions/checkout、setup-python、setup-node 与 MoonBit 官方安装脚本，仅作开发工程配置。它们不是本包的协议实现依赖。

第三方许可证由各发行包保留；`.mooncakes` 与 `.venv` 不进入仓库/发布包。项目 Apache-2.0 LICENSE 只覆盖本项目原创代码与文档。后续若复制、翻译或移植第三方代码/测试，必须新增路径、版权、许可证及修改范围记录，不可延用本次“独立实现”的说明遮盖来源。
