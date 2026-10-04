# MoonCoAP

[![checks](https://github.com/sujy123456/MoonCoAP/actions/workflows/ci.yml/badge.svg)](https://github.com/sujy123456/MoonCoAP/actions/workflows/ci.yml)

MoonBit 原生单播 CoAP 协议库。提供可复用的报文编解码、客户端与服务端交换状态机、资源路由、条件请求、响应缓存和资源发现。核心逻辑由 MoonBit 实现，Native UDP 使用官方公开 socket API。

- 仓库：[sujy123456/MoonCoAP](https://github.com/sujy123456/MoonCoAP)。
- 包名：`sujy123456/mooncoap`，版本 `0.1.0`；注册表发布与安装验证结果见 [VALIDATION.md](docs/VALIDATION.md)。
- 依据：[RFC7252](https://www.rfc-editor.org/rfc/rfc7252)、[RFC6690](https://www.rfc-editor.org/rfc/rfc6690)。实现有明确边界的单播子集，不宣称完整协议认证。
- Apache-2.0 许可证，来源与依赖见 [THIRD_PARTY.md](docs/THIRD_PARTY.md)。

## 通用价值

1. 设备遥测与网关：客户端获取表示，Max-Age 与 ETag 验证减少重复传输。
2. 通用配置服务：PUT/DELETE、条件更新和格式选择，调用者自行定义数据。
3. 自动化服务或设备模拟器：注册资源 handler，通过发现接口列出资源；显式时钟与报文动作可复现丢包、重复请求。

库接收 CoAP 字节、请求/响应对象和时钟事件，输出发送动作、业务请求、响应或结构化错误。业务示例不构成核心边界，不依赖 MoonBit 编译器或包管理器的内部接口。

## 支持范围

| 模块 | 首版能力 |
| --- | --- |
| 编解码 | Version 1、CON/NON/ACK/RST、0–8 字节 Token、扩展选项 delta/length、负载标记、边界检查 |
| URI/选项 | coap://、百分号处理、路径段身份、点段消除、IPv6 字面量验证、基础 RFC7252 选项 |
| 客户端 | peer+MID 控制匹配、peer+Token 响应匹配、Empty ACK、独立响应、退避重传、超时、取消、NSTART |
| 服务端 | 登记后交业务、重复请求重放、延迟 ACK、独立 CON 响应、ACK/RST |
| 资源 | 路径/方法路由、有界表示存储、GET/PUT/DELETE、ETag、If-Match、If-None-Match、Accept |
| 缓存 | 无负载 GET、2.05 表示、Max-Age、LRU、ETag 2.03 重验证、节点隔离和失效 |
| 发现 | Link Format 解析/序列化、/.well-known/core、单个精确/前缀/存在性过滤条件 |
| UDP | Native IPv4 单播，request/step 双向事件驱动与单请求 exchange |

不支持 DTLS、OSCORE、Observe、Blockwise、多播、代理或 TCP。只有 `coap://`，无加密与认证。IPv6 URI 已测试，IPv6 UDP 未验证。发现本地目录不支持 anchor 或跨源链接；多条件查询返回 4.00。缓存只存 2.05，不实现代理。

去重保护只在交换生命周期内有效；容量满时回压，不提前淘汰活记录；重启后记录丢失。跨重启业务幂等需要业务持久化键。应持续驱动 `poll`/`step` 并及时取走动作。限制详见 [PROTOCOL_MATRIX.md](docs/PROTOCOL_MATRIX.md)。

## 工具链与安装

开发版本：`moonc v0.10.14+7d59c7ec9`、`moon 0.1.20260920`。CI 固定该编译器版本。Native UDP 依赖公开 `moonbitlang/async@0.22.4`，核心包只导入 MoonBit Core。实测平台结果见 [VALIDATION.md](docs/VALIDATION.md)。

发布成功后，在新项目执行：

```sh
moon add sujy123456/mooncoap@0.1.0
```

核心 `moon.pkg`：

```moonbit
import { "sujy123456/mooncoap" @coap }
```

Native UDP `moon.pkg`：

```moonbit
supported_targets = "native"
import {
  "sujy123456/mooncoap" @coap,
  "sujy123456/mooncoap/udp" @udp,
  "moonbitlang/async" @async,
}
```

## 最小使用

```moonbit
fn main raise {
  let message = @coap.Message::new(@coap.Confirmable, @coap.Code::request(@coap.Get), 123)
  message.options = [@coap.option_text(11, "status")]
  let wire = @coap.encode(message, @coap.Limits::default()).unwrap()
  assert_eq(@coap.decode(wire, @coap.Limits::default()).unwrap(), message)
  println(@coap.bytes_to_hex(wire))
}
```

默认报文 1152 字节、负载 1024 字节、32 个选项、选项值合计 512 字节，可通过 `Limits` 调整。生产代码应处理 `Result::Err`；例子的 `unwrap` 面向已知有效数据。

## 运行示例

克隆仓库后：

```sh
moon run examples/basic --target js
moon run examples/loss --target js
moon run examples/discovery_cache --target js
moon run examples/udp_loopback --target native
```

依次得到：

```text
GET /status -> 2.05 ready

Drop first response
POST retried; business executions=1; cached reply replayed

Discovery: 2 reusable resources
Cache: fresh -> stale -> ETag validated -> fresh

Native UDP: separate response received and acknowledged
```

前三个例子也支持 `--target native`。每个示例包含断言，失败返回非零状态。丢包例子丢弃第一次响应，再推进时间验证 POST 没有再次执行业务。

## 状态机与资源 API

`Endpoint::new(config)` 创建端点；`request(peer, request, now, sample)` 返回请求 ID。`now` 是调用者提供的单调毫秒数，`sample` 为 0..1,000,000 的均匀随机样本。默认固定 MID/Token 种子适合确定性测试，网络运行应随机初始化。

1. `drain()` 取出 `SendDatagram`、`RequestReceived`、`ResponseReceived`、`Failed`、`Cancelled` 动作。
2. 收包调用 `receive(peer, bytes, now)`；peer 必须同时标识节点及安全上下文。
3. `poll(now)` 处理计时，`next_deadline()` 给出下次驱动时间。跳跃时钟不会连续补发遗漏重传。
4. `respond(id, response, now, sample)` 回复。先 `acknowledge(id, now)` 可随后发送独立响应。
5. `Router::add(path, verbs, handler)` 注册通用业务；`serve` 在执行 handler 前检查身份、期限、容量与执行状态。非法 handler 响应可以手动 `respond` 修复，不允许重跑 handler。
6. `ResourceStore::put/get/handle` 提供表示与条件 CRUD；`Discovery::add/handle` 提供发现；`ResponseCache::store/lookup/validate/invalidate` 提供客户端表示缓存。

协议错误可能同时产生 RST 动作，因此返回 `Err` 后仍需取走动作。完整设计见 [ARCHITECTURE.md](docs/ARCHITECTURE.md)。

UDP 使用 `UdpEndpoint::bind(address, network_config(config))`；循环 `step(maximum_wait_ms)` 取得 `UdpEvent`，使用 `request/respond/acknowledge` 发送。`exchange` 用于独占空闲客户端，多请求或同时提供服务时使用 `request/step`；结束后 `close`。

UDP 由公开 `@async.now()` 计算并夹持递增相对时间，不是独立 OS 单调计时器；系统时钟回拨可能延长等待。严格计时部署应使用纯核心与自有单调时钟适配器。

## 构建与验证

```sh
moon fmt --check
moon check --target js --deny-warn
moon test --target js --deny-warn
moon build --target js --deny-warn
moon test --target native --deny-warn
moon build --target native --deny-warn
python scripts/count_lines.py
```

完整检查：

```sh
python -m venv .venv
# Linux/macOS 用 .venv/bin/python；Windows 用 .venv/Scripts/python.exe
.venv/bin/python -m pip install -r scripts/requirements-interop.txt
.venv/bin/python scripts/validate.py --interop
```

支持 `--moon /path/to/moon` 指定工具链。Windows Native 使用 MSVC/Windows SDK；Linux CI 使用 C 编译器。互通测试占用 UDP 56830/56831，只启动和终止自己的测试子进程。

测试覆盖非法和随机报文、选项边界、MID/Token/peer 匹配、重传、超时、队列、重复执行、条件更新、发现、缓存和真实 UDP。aiocoap 双向互通脚本是外部验证工具，Python 不实现本库核心。

## 规模、记录与维护

`python scripts/count_lines.py --json` 分别统计实现、测试、示例、文档及其他语言。实现排除空行、注释、生成接口、构建输出、依赖及第三方代码，每行只计一次。CI 检查有效实现超过 4000 行；行数不等于复杂度或协议完整性。

实际开发历史、Actions、[CHANGELOG.md](CHANGELOG.md) 与 [VALIDATION.md](docs/VALIDATION.md) 保留验证证据。[公开查重与规则记录](docs/RULES_AND_DUPLICATION.md) 说明检索范围及限制，[维护计划](docs/MAINTENANCE.md) 说明功能边界。申报材料请由参赛者依据 [事实与提纲](docs/APPLICATION_FACTS.md) 本人完成。
