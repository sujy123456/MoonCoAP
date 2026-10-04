# MoonCoAP

Reusable unicast CoAP protocol library implemented in MoonBit.

The pure core provides RFC7252 message and option codecs, client/server exchange
state machines, bounded duplicate suppression, resource routing, conditional
representations, response caching and RFC6690 discovery. The native `udp` package
uses the public `moonbitlang/async` socket API.

See the [repository README](https://github.com/sujy123456/MoonCoAP#readme) for
installation, four runnable examples, API usage and reproducible validation.
The [protocol support matrix](https://github.com/sujy123456/MoonCoAP/blob/main/docs/PROTOCOL_MATRIX.md)
defines the implemented subset. DTLS, OSCORE, Observe, Blockwise, multicast,
proxying and TCP are outside this release. IPv6 UDP has not been validated.

Licensed under Apache-2.0. Standards and dependency provenance are documented in
[THIRD_PARTY.md](https://github.com/sujy123456/MoonCoAP/blob/main/docs/THIRD_PARTY.md).
