# MoonCoAP

MoonBit-native unicast CoAP protocol library. Work in progress: the initial
commit establishes the package, license and build checks; functionality is
added in subsequent commits. The repository URL in the manifest is the
intended destination and is not a claim that a public repository exists yet.

Core scope: RFC7252 datagram codec, options, client/server exchange machines,
bounded retransmission and duplicate handling, conditional resources, caching,
and RFC6690 discovery. Transport adapters consume explicit actions so callers
can inject clocks and reproduce packet-loss scenarios.

This is a reusable protocol component. Application payloads and resource
handlers belong to callers. DTLS, OSCORE, Observe, Blockwise, multicast,
proxying and CoAP over TCP are outside version 0.1.

Planned license: Apache-2.0; see LICENSE. Protocol definitions are based on
RFC7252 and RFC6690. Reference implementations are interoperability tools,
not wrapped implementations of this package.
