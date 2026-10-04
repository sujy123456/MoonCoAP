# Implementation and evidence plan

Selected project: MoonCoAP, October 2026 MoonBit hackathon.
Implementations, tests, examples and documentation are counted separately.
The user requires >4000 effective handwritten MoonBit implementation lines
and >=15 genuine public in-season commits. Target >=20; never synthesize
commit timestamps or use empty commits.

Milestones: model/limits; strict decoder; encoder; semantic options; URI;
exchange allocator; client; server; separate response; retransmission and
deduplication; resource routing; discovery; cache; real UDP; examples;
interop; adversarial tests; CI; line audit; clean consumer and release.

Before application: actual working MVP, public real commits, README,
three runnable examples, passing tests/CI, and external interoperability.
After that: package/release verification and acceptance evidence.
Research date: 2026-10-04. Official October page says October31, charter
versions conflict. Internal delivery target October24; organizer's latest
notification governs. Application wording is completed by the participant;
AI supplies facts and outline only.

Sources:
- https://moonbitlang.github.io/Hackathon2026/
- https://www.rfc-editor.org/rfc/rfc7252.html
- https://www.rfc-editor.org/rfc/rfc6690.html
- https://github.com/cghyyrrt/moonbit-pcap (adjacent offline header parser)

All evidence files distinguish planned, locally verified, publicly verified
and unverified states. Network authentication is never stored in the repo.
