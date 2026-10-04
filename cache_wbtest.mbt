///|
test "cache age expiry validation and peer isolation" {
  let cache = ResponseCache::new(2, 4096, Limits::default()).unwrap()
  let request : Request = {
    ..Request::new(Get),
    options: [option_text(11, "a")],
  }
  let response : Response = {
    ..Response::content(b"value"),
    options: [{ number: 4, value: b"v1", }, option_uint(14, 2L).unwrap()],
  }
  cache.store("p", request, response, 0L).unwrap()
  assert_eq(cache.lookup("other", request, 1L).unwrap(), Miss)
  match cache.lookup("p", request, 1000L).unwrap() {
    Fresh(value) => assert_eq(option_to_uint(value.options[1]).unwrap(), 1L)
    _ => abort("fresh")
  }
  let validation = match cache.lookup("p", request, 2000L).unwrap() {
    Stale(_, validation) => validation
    _ => abort("stale")
  }
  let valid : Response = {
    code: { value: 67, },
    options: [{ number: 4, value: b"v1", }, option_uint(14, 10L).unwrap()],
    payload: b"",
  }
  cache.validate("p", validation, valid, 2000L).unwrap()
  assert_true(cache.lookup("p", request, 2001L).unwrap() is Fresh(_))
  assert_eq(cache.stats().validations, 1L)
  assert_eq(cache.invalidate("p", "/a").unwrap(), 1)
}

///|
test "cache keys preserve query order and normalize integer encodings" {
  let a : Request = {
    ..Request::new(Get),
    options: [
      option_text(15, "x=1"),
      option_text(15, "y=2"),
      option_uint(17, 0L).unwrap(),
    ],
  }
  let b : Request = {
    ..a,
    options: [
      option_text(15, "x=1"),
      option_text(15, "y=2"),
      { number: 17, value: b"\x00", },
      { number: 4, value: b"tag", },
      { number: 28, value: b"nonkey", },
    ],
  }
  assert_eq(
    cache_key("p", a, Limits::default()).unwrap(),
    cache_key("p", b, Limits::default()).unwrap(),
  )
  let c : Request = {
    ..a,
    options: [
      option_text(15, "y=2"),
      option_text(15, "x=1"),
      option_uint(17, 0L).unwrap(),
    ],
  }
  assert_true(
    cache_key("p", a, Limits::default()).unwrap() !=
    cache_key("p", c, Limits::default()).unwrap(),
  )
}

///|
test "LRU eviction is bounded and failed insert does not discard live data" {
  let cache = ResponseCache::new(2, 4096, Limits::default()).unwrap()
  let a : Request = { ..Request::new(Get), options: [option_text(11, "a")], }
  let b : Request = { ..a, options: [option_text(11, "b")], }
  let c : Request = { ..a, options: [option_text(11, "c")], }
  cache.store("p", a, Response::content(b"a"), 0L).unwrap()
  cache.store("p", b, Response::content(b"b"), 0L).unwrap()
  cache.lookup("p", a, 1L).unwrap() |> ignore
  cache.store("p", c, Response::content(b"c"), 2L).unwrap()
  assert_eq(cache.lookup("p", b, 2L).unwrap(), Miss)
  assert_eq(cache.stats().evictions, 1L)
  assert_true(
    cache.store("p", a, Response::content(Bytes::make(2000, b'x')), 3L)
    is Err(_),
  )
  assert_true(cache.lookup("p", a, 3L).unwrap() is Fresh(_))
  assert_true(cache.lookup("p", a, 1L) is Err(Clock(_)))
}
