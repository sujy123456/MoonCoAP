///|
test "conditional updates preserve representation on failed preconditions" {
  let store = ResourceStore::new(4, 128, [0, 50], true, Limits::default()).unwrap()
  let original = store.put("/config", b"old", 0, 30L, true).unwrap()
  let message = Message::new(Confirmable, Code::request(Put), 1)
  message.options = [option_text(11, "config"), { number: 1, value: b"wrong", }]
  message.payload = b"new"
  assert_eq(store.handle(message).code.value, 140)
  assert_eq(store.get("/config").unwrap(), original)
  message.replace_option(1, original.etag)
  assert_eq(store.handle(message).code.value, 68)
  let revised = store.get("/config").unwrap()
  assert_eq(revised.payload, b"new")
  assert_true(revised.etag != original.etag)
  message.code = Code::request(Get)
  message.remove_option(1)
  message.replace_option(4, revised.etag)
  assert_eq(store.handle(message).code.value, 67)
  assert_eq(store.handle(message).payload, b"")
}

///|
test "creation deletion formats and capacity are bounded" {
  let store = ResourceStore::new(1, 4, [0], true, Limits::default()).unwrap()
  let message = Message::new(Confirmable, Code::request(Put), 1)
  message.options = [option_text(11, "a"), { number: 5, value: b"", }]
  message.payload = b"abcd"
  assert_eq(store.handle(message).code.value, 65)
  assert_eq(store.handle(message).code.value, 140)
  message.options = [option_text(11, "b")]
  assert_eq(store.handle(message).code.value, 163)
  assert_eq(store.byte_size(), 4)
  message.options = [option_text(11, "a"), option_uint(12, 50L).unwrap()]
  assert_eq(store.handle(message).code.value, 143)
  message.options = [option_text(11, "a")]
  message.code = Code::request(Delete)
  assert_eq(store.handle(message).code.value, 66)
  assert_eq(store.inventory().length(), 0)
  message.code = Code::request(Put)
  assert_eq(store.handle(message).code.value, 65)
}
