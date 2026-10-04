///|
test "unsigned options use minimal encoding and cover uint32" {
  for value in [0L, 1L, 255L, 256L, 65535L, 4294967295L] {
    let option = option_uint(14, value).unwrap()
    assert_eq(option_to_uint(option), Ok(value))
    if value == 0L {
      assert_eq(option.value, b"")
    } else {
      assert_true(option.value[0] != b'\x00')
    }
  }
  assert_true(option_uint(14, -1L) is Err(_))
  assert_true(option_uint(14, 4294967296L) is Err(_))
}

///|
test "unknown elective allowed, unknown critical explicitly supported" {
  let request = Message::new(Confirmable, Code::request(Get), 1)
  request.options = [{ number: 100, value: b"x", }]
  assert_eq(validate_options(request, []), Ok(()))
  request.options = [{ number: 101, value: b"x", }]
  assert_true(validate_options(request, []) is Err(Unsupported(_)))
  assert_eq(validate_options(request, [101]), Ok(()))
  assert_true(option_is_critical(101))
  assert_true(option_is_unsafe(35))
  assert_true(!option_is_cache_key(60))
}

///|
test "option lengths, direction, duplicates and conditions" {
  let request = Message::new(Confirmable, Code::request(Get), 1)
  for
    options in [
      [{ number: 4, value: b"", }],
      [{ number: 5, value: b"x", }],
      [option_text(3, "a"), option_text(3, "b")],
      [{ number: 14, value: b"", }],
      [{ number: 1, value: b"", }, { number: 5, value: b"", }],
      [{ number: 11, value: b"\xff", }],
    ] {
    request.options = options
    assert_true(validate_options(request, []) is Err(_))
  }
  request.options = [option_text(11, "设备"), option_text(11, "status")]
  assert_eq(validate_options(request, []), Ok(()))
  assert_eq(request_path(request), Ok("/设备/status"))
}
