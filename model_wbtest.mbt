///|
test "code classes and verb boundaries" {
  assert_eq(Code::request(Get).value, 1)
  assert_eq(Code::request(Delete).verb(), Some(Delete))
  assert_eq(Code::response(2, 5), Ok({ value: 69, }))
  assert_true(Code::response(6, 0) is Err(_))
  assert_true(Code::response(2, 32) is Err(_))
  assert_true(({ value: 69, } : Code).is_success())
  assert_true(!({ value: 0, } : Code).is_request())
}

///|
test "hex conversion handles arbitrary bytes and malformed input" {
  assert_eq(bytes_to_hex(b"\x00\xff\x80"), "00ff80")
  assert_eq(hex_to_bytes("00Ff80"), Ok(b"\x00\xff\x80"))
  assert_true(hex_to_bytes("abc") is Err(_))
  assert_true(hex_to_bytes("0g") is Err(_))
}

///|
test "limits and message copying do not alias mutable arrays" {
  assert_eq(Limits::default().validate(), Ok(()))
  let message = Message::new(Confirmable, Code::request(Get), 7)
  message.options.push({ number: 11, value: b"health", })
  let copied = message.copy()
  copied.options.push({ number: 15, value: b"x=1", })
  copied.replace_option(11, b"other")
  assert_eq(message.options.length(), 1)
  assert_eq(message.first_option(11), Some(b"health"))
  assert_eq(copied.first_option(11), Some(b"other"))
}
