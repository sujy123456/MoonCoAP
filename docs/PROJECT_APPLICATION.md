> AI 辅助参考草稿，供参赛者本人修改定稿。项目数据依据 2026-10-04 的 0.1.1 交付记录，本文档的后续提交另计。

# MoonCoAP 项目申报书

**基本信息**

- 项目名称：MoonCoAP：MoonBit 原生单播 CoAP 协议库
- 参赛者：苏楗轶
- 联系方式：2821775174@qq.com
- GitHub 仓库：[sujy123456/MoonCoAP](https://github.com/sujy123456/MoonCoAP)
- 项目方向：通用网络协议库 / 可复用基础软件组件
- 是否为移植项目：否，依据公开协议标准独立实现

**项目简介**

MoonCoAP 为 MoonBit 开发者提供可复用的 CoAP 客户端与服务端能力，适用于设备遥测与网关、通用配置服务、自动化测试和设备模拟等场景。调用者通过统一 API 处理报文、请求、响应和资源，自行定义业务数据与处理逻辑。

项目采用“纯 MoonBit 协议状态机＋Native UDP 适配”的技术路线，核心输入为报文字节、请求对象和时间事件，输出为发送动作、业务请求、响应及结构化错误。项目不依赖 MoonBit 编译器、包管理器内部接口，维护范围集中于协议子集及公开 API。本月已完成可运行 MVP，并发布 0.1.1 版本。

**核心功能范围**

- CoAP 报文、基础选项及 URI 的编解码与边界校验；
- 客户端与服务端交换，支持消息匹配、并发限制、重传、超时、取消、交换生命周期内去重及独立响应；
- 通用资源路由、GET/PUT/DELETE、条件更新及内容格式选择；
- RFC6690 资源发现，以及 Max-Age、ETag 和 LRU 响应缓存；
- Native IPv4 UDP 通信及可注入时间的纯协议核心，便于复现丢包、重复请求等情况。

首版不包含 DTLS、OSCORE、Observe、Blockwise、代理、多播或 TCP；IPv6 UDP 尚未验证。

**预期验收产物**

- 已公开的 MoonBit 库，可通过 `moon add sujy123456/mooncoap@0.1.1` 安装；
- 有效 MoonBit 实现源码 4,382 行，测试 1,158 行，示例及互通命令 245 行；公开仓库已有 29 次十月真实提交；
- 完整 README、四个可运行示例、协议支持矩阵、许可证与来源说明、CHANGELOG 和维护计划；
- Windows 本地及 Linux CI 已通过构建、JS 57 项和 Native 60 项测试，以及 9 项外部互通检查；发布包已在新消费项目中安装并运行；
- 后续根据使用反馈补充回归测试，持续跟踪 IPv6 UDP 验证与单调时钟适配。

**移植或参考说明**

项目依据 [RFC7252](https://www.rfc-editor.org/rfc/rfc7252) 和 [RFC6690](https://www.rfc-editor.org/rfc/rfc6690) 独立实现，开发中使用 AI 辅助，未复制或逐文件移植现有协议栈源码及测试。协议标准本身不属于本项目原创成果。

项目许可证为 **Apache-2.0**。依赖 MoonBit Core 和 [moonbitlang/async](https://github.com/moonbitlang/async)，均为 Apache-2.0；[aiocoap](https://codeberg.org/aiocoap/aiocoap) 仅用于外部互通验证，其发行许可证为 MIT AND BSD-3-Clause。详细来源、范围与验证证据保存在仓库文档中。
