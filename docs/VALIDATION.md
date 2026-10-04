# 验证与发布记录

记录日期：2026-10-04（Asia/Shanghai）。以下为实际执行结果；申报与赛事验收由本人提交，未代为提交问卷。

## 版本、源码与公开地址

- [GitHub 公开仓库](https://github.com/sujy123456/MoonCoAP)。
- [Mooncakes 包](https://mooncakes.io/docs/sujy123456/mooncoap)：`sujy123456/mooncoap@0.1.1`；页面已实际读取，显示版本 0.1.1、Apache-2.0 和对应仓库。
- 0.1.0 首次发布及注册表安装成功；0.1.1 修正文档初始化标题，增加消费验证脚本；协议实现没有变化。
- 0.1.1 发布时源提交：`f06406186ac7456f424be9690bb966bcf847f520`。发布后补充的验收记录是文档改动，不将其声称为归档中已有的记录。
- 归档：`_build/publish/sujy123456-mooncoap-0.1.1.zip`。
- 归档 SHA256：`42bc95c2d5f95141b836658b4cc6a4a327701ab2a808243c1b82134b1ea90916`。
- 公开下载：[0.1.1.zip](https://download.mooncakes.io/user/sujy123456/mooncoap/0.1.1.zip)。

## 构建、测试与 CI

工具链：`moonc v0.10.14+7d59c7ec9`、`moon 0.1.20260920`、`moonrun 0.1.20260920`。CI 固定该编译器版本。外部互通工具为 `aiocoap==0.4.17`。

| 实际环境 | 格式/类型/构建 | 测试 | 示例 | 外部互通 |
| --- | --- | --- | --- | --- |
| 本机 Windows x64，MSVC/Windows SDK，JS/Node 与 Native | 通过 | JS 57/57；Native 60/60 | 前三例在 JS/Native 通过；UDP 例 Native 通过 | 9 项通过 |
| GitHub Ubuntu 干净 checkout，Python 3.12、Node 22、C 编译器 | 通过 | JS 57/57；Native 60/60 | 同上 | 9 项通过 |

发布源提交的 [checks CI 实际通过记录](https://github.com/sujy123456/MoonCoAP/actions/runs/37204366841)：2026-10-04T13:05:54Z 完成，所有步骤 success。检查包含格式、类型、测试、构建、示例、源码下限、互通和生成接口一致性。最新 main 的状态见 [checks 工作流](https://github.com/sujy123456/MoonCoAP/actions/workflows/ci.yml)。不能将其他 copilot-setup 工作流的成功替代此检查。

随机行为测试包含 500 次合法消息往返和 2000 个任意字节输入；它们属于 JS/Native 测试项内部的数据样本，不将样本数量冒充独立测试项数量。测试也覆盖非法输入、peer/MID/Token 匹配、重传时限、排队、去重、业务只执行一次、条件请求、缓存容量、发现和网络生命周期。

外部互通 9 项：GET；RFC6690 发现及 Content-Format 40；条件 PUT/过期 ETag；2.03 缓存重验证；Accept 4.06；独立响应 ACK/CON；4.04；重复 POST 返回同一缓存响应且业务执行一次；MoonBit 客户端访问 Python 服务端。前三个离线示例和 UDP 示例的预期输出见 README。

## 新消费项目验证

通过 `python scripts/verify_release.py --version 0.1.1` 在全新目录创建消费项目；实际执行 `moon update`、`moon add sujy123456/mooncoap@0.1.1`。从注册表下载发布版本，没有本地路径覆盖。

本机保存目录：`_build/verification/consumer-d5equvxe`。依赖中的 `moon.mod` 版本已校验为 0.1.1。消费项目在 JS/Native 均完成类型检查、构建与基础示例运行，Native 真实 UDP 独立响应示例通过：

```text
GET /status -> 2.05 ready
Native UDP: separate response received and acknowledged
Published 0.1.1 registry installation verified
```

发布命令先检查项目及解包后的发布归档，之后返回 `Server status: 200 OK`。0.1.0 也已通过独立消费安装；最终默认使用 0.1.1。注册表安装验证实测于 Windows；Linux 的源仓库构建/网络互通已经 CI 验证，Linux 消费项目安装未另外执行。

## 规模与提交

有效 MoonBit 实现 **4382 行**；测试 **1158 行**；示例和互通命令 **245 行**。通过 `python scripts/count_lines.py --json` 可得到每文件明细与最新文档/其他语言统计。文档按物理行统计，其他语言按非空行统计；二者不混入有效 MoonBit 实现。

| 实现模块 | 有效行 |
| --- | ---: |
| 数据模型与公开 traits | 291 |
| 报文解码/编码 | 247 |
| 选项校验/接收处理 | 263 |
| URI 与地址 | 425 |
| 配置与限制 | 135 |
| MID/Token 分配 | 141 |
| Endpoint/客户端计时与接收/服务端交换 | 1181 |
| 路由与资源表示 | 469 |
| RFC6690 发现 | 491 |
| 响应缓存 | 408 |
| Native UDP 驱动 | 331 |
| 合计 | 4382 |

统计排除空行、注释、生成 `.mbti`、依赖、构建产物、第三方源码；没有以拆行、无用包装、复制数据补足规模。Python 脚本只负责验证与统计，不承担协议核心。

交付记录提交后的公开 main 共 **29 次真实可追踪提交**，含保留的原始初始提交及一次正常合并；其余为功能、测试、修复与文档工作。作者与提交者日期均为 2026-10-04，属于十月；没有空提交、补造日期、强制覆盖或改写已公开历史。计数依据 GitHub commits API 与 `git rev-list --count HEAD`；赛期认定与有效贡献最终仍由主办方审核。

维护工单：[IPv6 UDP](https://github.com/sujy123456/MoonCoAP/issues/1)、[公开单调时钟适配](https://github.com/sujy123456/MoonCoAP/issues/2)。独立协议复核后修复了非法响应类、重传截止、执行前状态检查与缓存元数据容量等问题，回归测试已通过。本次直接开发与正常合并不另造无实际审阅用途的 PR。

## 已解决失败与实际限制

- 首次公共 checks 失败原因是新运行器未初始化注册表；验证脚本补 `moon update` 后通过，失败记录仍可追踪。
- 首次消费验证的临时清单缺少逗号，添加依赖后加载失败；修正消费脚本后重新建目录并通过。最终消费者没有初版包名/导入别名冲突。
- Windows 构建官方 async 的 C 依赖时有非阻断 `EINVAL` 宏重定义提示；MoonBit 类型检查、测试和构建均返回成功。
- 实测支持 Windows 与 Linux，JS 纯核心、Native IPv4 UDP。macOS、Wasm、IPv6 UDP 未验证。
- 不支持 DTLS/OSCORE/Observe/Blockwise/代理/多播/TCP；Native 默认计时受系统回拨影响。没有发布性能或完整协议认证结论。
- 完整飞书后半部仍未读取；本人须在赛事群确认当期通知、身份资料与报名操作。无法保证不存在未公开同类项目或保证赛事通过。

复现源码全量检查：`python scripts/validate.py --interop`；发布包消费检查：`python scripts/verify_release.py --version 0.1.1`。来源与许可证见 THIRD_PARTY.md，后续维护见 MAINTENANCE.md；最终申报本人根据 APPLICATION_FACTS.md 五项提纲撰写。
