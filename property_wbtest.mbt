///|
test "generated messages roundtrip across option boundaries" {
  let limits = Limits::default()
  let mut state = 123456789U
  for index = 0; index < 500; index = index + 1 {
    state = state * 1664525U + 1013904223U
    let token_length = (state % 9U).reinterpret_as_int()
    let message = Message::new(
      if index % 2 == 0 {
        Confirmable
      } else {
        NonConfirmable
      },
      Code::request(Post),
      index,
    )
    message.token = Bytes::makei(token_length, fn(i) {
      ((state >> (i % 4 * 8)) & 255U).reinterpret_as_int().to_byte()
    })
    message.options = [
      { number: 11, value: Bytes::make(index % 40, b'a'), },
      { number: 11, value: Bytes::make(index % 17, b'b'), },
      option_uint(12, (index % 51).to_int64()).unwrap(),
      { number: 280 + index, value: Bytes::make(index % 19, b'c'), },
    ]
    message.payload = Bytes::makei(index % 256, fn(i) {
      ((i + index) & 255).to_byte()
    })
    let bytes = encode(message, limits).unwrap()
    assert_eq(decode(bytes, limits).unwrap(), message)
    assert_eq(encoded_size(message, limits).unwrap(), bytes.length())
  }
}

///|
test "seeded arbitrary datagrams fail safely or reencode valid messages" {
  let limits = Limits::default()
  let mut state = 987654321U
  for index = 0; index < 2000; index = index + 1 {
    let data : Array[Byte] = []
    for _i = 0; _i < index % 128; _i = _i + 1 {
      state = state * 1664525U + 1013904223U
      data.push(((state >> 24) & 255U).reinterpret_as_int().to_byte())
    }
    match decode(Bytes::from_array(data), limits) {
      Err(_) => ()
      Ok(message) =>
        assert_eq(
          decode(encode(message, limits).unwrap(), limits).unwrap(),
          message,
        )
    }
  }
}
