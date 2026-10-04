# Changelog

## 0.1.0 — 2026-10-04（发布候选）

- 独立MoonBit RFC7252单播编解码、基础选项与URI支持。
- 客户端/服务端有界交换、NSTART、退避重传、超时、取消、去重、独立响应。
- 通用路径/方法路由、条件表示存储、RFC6690本地发现、LRU/Max-Age/ETag缓存。
- 官方公开socket API的Native UDP适配与四个可运行示例。
- 明确源代码计数、CI、随机/异常输入与生命周期回归测试。
- aiocoap双向实际UDP互通与重复POST验证。
- 限制：无DTLS/OSCORE/Observe/Blockwise/代理/多播/TCP；IPv6 UDP未验证；默认网络计时受系统回拨影响。

本次从新项目启动；保留公开仓库原始初始提交，正常合并开发历史。正式发布与安装验证结果见docs/VALIDATION.md，不将发布候选视为已经发布。
