///|
test "RFC header Token and repeated Uri-Path decoding" {
  let packet = b"\x41\x01\x12\x34\xaa\xb1a\x01b"
  let decoded = decode(packet, Limits::default()).unwrap()
  assert_eq(decoded.mid, 4660)
  assert_eq(decoded.token, b"\xaa")
  assert_eq(decoded.option_values(11), [b"a", b"b"])
  assert_eq(decoded.payload, b"")
}

///|
test "extended options, payload marker and malformed input" {
  let decoded = decode(b"\x40\x01\x00\x01\xd1\x00x\xffok", Limits::default()).unwrap()
  assert_eq(decoded.options[0].number, 13)
  assert_eq(decoded.payload, b"ok")
  for
    packet in [
      b"", b"\x40", b"\x40\x01\x00", b"\x49\x01\x00\x01", b"\x41\x01\x00\x01", b"\x00\x01\x00\x01",
      b"\x40\x01\x00\x01\xff", b"\x40\x01\x00\x01\xf0", b"\x40\x01\x00\x01\x0f",
      b"\x40\x01\x00\x01\xe0\x00", b"\x60\x01\x00\x01", b"\x70\x45\x00\x01", b"\x40\x00\x00\x01\xffx",
    ] {
    assert_true(decode(packet, Limits::default()) is Err(_))
  }
}

///|
test "every packet prefix returns a result and limits are enforced" {
  let packet = b"\x44\x01\x00\x7f\x01\x02\x03\x04\xb6health\xffabc"
  for end = 0; end <= packet.length(); end = end + 1 {
    ignore(decode(slice_bytes(packet, 0, end), Limits::default()))
  }
  let limits = Limits::default()
  let tiny : Limits = { ..limits, max_payload: 1, }
  assert_true(decode(packet, tiny) is Err(Capacity(_)))
}
