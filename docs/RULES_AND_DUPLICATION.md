# 规则与查重记录

核对日期：2026-10-04（Asia/Shanghai）。这是资料摘记与公开检索证据，不是主办方审核承诺。

## 官方资料读取范围

- [十月官网](https://moonbitlang.github.io/Hackathon2026/) 已实际读取：当前十月赛，报名与验收 2026-10-31 截止；本月最多申报3次，每队不超过3人，沿用报名表，按通过审核前最后一次有效修改时间认定；公开仓库、MoonBit 为主、README、可运行示例、测试和开源来源说明。允许 AI 辅助，参赛者须理解目标/技术/质量。
- [飞书章程](https://bxup9uklfcb.feishu.cn/wiki/Dx4Bwd6D1i3GfHkajQCcF7SznEd) 只读取到5.1的开头，未完整加载后续章节：页面显示9月28日修改，正文仍写9月30日申报截止。已读4.1要求不重复已存在且维护良好的高度重合成熟生态项目。本次提取没有读取到用户提及的10月24日时间表，不声称已核对该表。
- [申报样板](https://bxup9uklfcb.feishu.cn/wiki/PdFww3ZWbi1osWkqt6rc9sWVnNf) 已读取 Moon ELK 示例；样板表达通用内核价值、功能范围、来源/许可证与简化范围。最终使用用户要求的五项 Markdown 结构。
- [历届 OSC2026](https://moonbitlang.github.io/OSC2026/) 已读取13个获奖项目、公示与方向；它是旧赛事资料，不能将4~10k参考范围、旧报名日期和全部规则当十月新增硬性规定。
- 作品墙可访问展示不等于全部已报名项目；私有项目和未公开申报无法检索。

当期官网已明确10月31日，章程旧正文冲突仍不能代表已获得赛事群确认。用户提出的更早10月24日作为保守交付点，10月17日前准备本人申报，预留修改时间；用户应在群内确认当期口径，9月30日已过去，不能据此安排本期工作。

## 要求来源区分

| 来源 | 项目约束 |
| --- | --- |
| 十月官方已读 | MoonBit 为主、真实可用、公开记录、可运行示例/测试、许可证和来源、可解释的 AI 辅助、不高度重复成熟项目 |
| 用户要求/历史反馈 | >4000有效实现行、≥15公开赛期提交、目标20+；MVP后申报；CI、Mooncakes发布和新项目安装；不做MoonBit自身工具；本人写最终申报 |
| 自设质量目标 | 有界状态与回压、跨实现双向UDP、随机报文、独立协议复核、全量验证脚本、协议矩阵 |

旧 OSC 页面明确 CI 与 Mooncakes 发布、OSI 认可许可证等要求，本项目主动满足；由于飞书章程后半部分未完整读取，不把这些写成已在本期飞书逐条核实。

## 公开查重

初查与 MVP 后复查均为2026-10-04。关键词：CoAP、MoonCoAP、Constrained Application Protocol、RFC7252、RFC6690、受限应用协议、单播、ACK/Token/NSTART、encode/decode、well-known/core。覆盖官方公示/可访问作品墙、Mooncakes注册表和 moon search、GitHub仓库搜索，及近似包的 README/源码。索引可能滞后，检索不包含未公开报名和私有仓库。

| 项目 | 已有核心能力 | 本项目实质差异 | 判断 |
| --- | --- | --- | --- |
| [cghyyrrt/moonbit-pcap](https://github.com/cghyyrrt/moonbit-pcap)、[Mooncakes](https://mooncakes.io/docs/cghyyrrt/moonbit-pcap) 0.1.2 | PCAP/PCAPNG 与多协议分析；CoAP层解析4字节头、Token，将后续字节作为负载 | 完整选项边界编解码、peer+MID/Token交换、重传/NSTART、请求去重、独立响应、资源发现/缓存、UDP端点 | 相邻但互补，不依赖该解析器 |
| [moonbitlang/async](https://github.com/moonbitlang/async) | 异步任务和通用UDP socket | 复用公开传输API，实现CoAP语义 | 相邻基础依赖 |
| [libcoap](https://github.com/obgm/libcoap)、[aiocoap](https://codeberg.org/aiocoap/aiocoap) | C/Python成熟CoAP协议栈 | MoonBit独立实现；首版范围更小；外部aiocoap只作互通验证 | 同协议其他语言，不声称发明CoAP |
| 官方公开作品和GitHub MoonBit检索 | 初查与复查没有检索到已公开的同等MoonBit主动CoAP端点库 | 补足MoonBit可调用端点能力 | 公开检索暂未发现同类，不能保证绝对不重复 |

MVP复查：`moon search coap` 仅返回 moonbit-pcap@0.1.2；GitHub `coap language:MoonBit` 返回0。自身仓库尚未被搜索索引收录，说明该结果不是绝对完整覆盖。申报前须再次检索并保存日期与结果。

## 历史驳回点的回应

- 通用性：提供协议内核与公开API，资源payload/handler不绑定业务；遥测、通用配置、模拟/自动化至少三类用途。
- 提交/MVP：实际实现、示例、测试、CI与公开提交达到后再由本人申报，不把凑够提交当功能完成。
- MoonBit自身工具：不改动编译器、包管理器或官方私有接口；只依赖Core与官方async公开API。
- 高度重复：已有pcap为被动分析，不具备本库主动交换与服务端执行语义；保持MVP后、申报前复查，发现成熟同类需重新评估。

不能承诺主办方一定通过；申报时应以实际运行、通用API与可核实证据说明适配方向。
