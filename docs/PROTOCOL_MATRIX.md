# 0.1.0 协议与验收边界

| 项目 | 状态 | 验证方式/限制 |
| --- | --- | --- |
| RFC7252 二进制格式 | 支持 | 边界案例、500 个生成报文、2000 个任意报文、前缀截断 |
| Token 0–8 字节与 MID 16位 | 支持 | 值域、租约与匹配测试 |
| CON/NON/ACK/RST | 支持 | 客户端、服务端及 Native UDP 测试 |
| GET/POST/PUT/DELETE | 支持协议层 | 表示存储不替业务实现 POST |
| 同节点 NSTART | 支持 | 请求与独立回复共用额度，默认 1 |
| 重传与期限 | 支持 | 指数退避、span/wait 边界、时间跳跃不突发 |
| 重复请求执行保护 | 支持限定范围 | 有界内存、交换生命周期内；重启后不保留 |
| 错误 critical/elective 选项 | 支持基础选项 | critical 拒绝；错误 elective 接收时忽略；发送严格验证 |
| Uri-*、Location-* | 支持 | 百分号、UTF-8、空段、点段限制；不做跨源链接解析 |
| ETag、If-Match、If-None-Match | 支持 | 条件读写、2.03、4.12及字节验证 |
| Accept 与 Content-Format | 支持单表示 | 不实现编码转换或多表示内容协商算法 |
| Max-Age 缓存 | 支持客户端缓存 | 只接纳 2.05、GET；不实现代理或缓存错误响应 |
| RFC6690 | 支持本地目录子集 | 单过滤、rt/if/ct/sz等属性；目录无 anchor |
| IPv4 UDP | 支持，需平台实测 | 真实回环与 aiocoap 双向互通 |
| IPv6 URI | 支持 | 压缩与 IPv4 嵌入格式测试 |
| IPv6 UDP | 尚未验证 | 不在已验证网络平台承诺内 |
| DTLS/OSCORE | 不支持 | 首版无传输加密认证 |
| Observe/Blockwise | 不支持 | 关键扩展选项拒绝，不能表示已支持扩展 |
| Proxy/Multicast/TCP | 不支持 | 显式边界；不实现 UDP 多播发现 |

验收命令为 `python scripts/validate.py --interop`。干净检出运行和新消费项目安装发布包的结果分别记录于 VALIDATION.md。编解码和传输互通不代表安全审计、吞吐量基准或官方协议认证；没有未经测量的性能结论。
