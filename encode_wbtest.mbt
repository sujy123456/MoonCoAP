///|
test "encoder sorts option numbers stably without mutating caller" {
  let message = Message::new(Confirmable, Code::request(Get), 0x1234)
  message.token = b"\xaa"
  message.options = [
    { number: 15, value: b"x=1", },
    { number: 11, value: b"a", },
    { number: 11, value: b"b", },
  ]
  let wire = encode(message, Limits::default()).unwrap()
  let roundtrip = decode(wire, Limits::default()).unwrap()
  assert_eq(roundtrip.option_values(11), [b"a", b"b"])
  assert_eq(roundtrip.first_option(15), Some(b"x=1"))
  assert_eq(message.options[0].number, 15)
  assert_eq(encode(roundtrip, Limits::default()), Ok(wire))
}

///|
test "roundtrip option extension boundaries and binary payload" {
  for number in [0, 12, 13, 268, 269, 65535] {
    for length in [0, 12, 13, 268, 269] {
      let message = Message::new(NonConfirmable, { value: 69, }, 65535)
      message.options = [{ number, value: Bytes::make(length, b'x'), }]
      message.payload = b"\x00\xff\x80"
      let wire = encode(message, Limits::default()).unwrap()
      assert_eq(decode(wire, Limits::default()), Ok(message))
    }
  }
}

///|
test "outgoing malformed fields and size limits fail explicitly" {
  let message = Message::new(Reset, { value: 1, }, 0)
  assert_true(encode(message, Limits::default()) is Err(_))
  message.msg_type = Confirmable
  message.mid = -1
  assert_true(encode(message, Limits::default()) is Err(_))
  message.mid = 1
  message.token = b"123456789"
  assert_true(encode(message, Limits::default()) is Err(_))
  message.token = b""
  message.options = [{ number: 65536, value: b"", }]
  assert_true(encode(message, Limits::default()) is Err(_))
  message.options = []
  message.payload = b"xx"
  let tiny : Limits = { ..Limits::default(), max_datagram: 6, }
  assert_true(encode(message, tiny) is Err(Capacity(_)))
}
