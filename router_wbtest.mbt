///|
test "route identity preserves encoded slash and empty segments" {
  let router = Router::new(8, Limits::default()).unwrap()
  router.add("/a%2Fb", [Get], fn(_) { Response::content(b"one") }).unwrap()
  router.add("/a/b", [Get], fn(_) { Response::content(b"two") }).unwrap()
  router.add("/a/", [Get], fn(_) { Response::content(b"trailing") }).unwrap()
  for
    (path, expected) in [
      ("/a%2Fb", b"one"),
      ("/a/b", b"two"),
      ("/a/", b"trailing"),
    ] {
    let uri = CoapUri::parse("coap://host" + path, Limits::default()).unwrap()
    let message = Message::new(Confirmable, Code::request(Get), 1)
    message.options = uri.to_options()
    assert_eq(
      router.dispatch({ id: 1, peer: "p", message, received_at: 0L, }).payload,
      expected,
    )
  }
  assert_eq(router.remove("/a%2fb").unwrap(), 1)
  assert_eq(router.routes().length(), 2)
}

///|
test "method and path errors are distinct and conflicting routes rejected" {
  let router = Router::new(1, Limits::default()).unwrap()
  router.add("/", [Get], fn(_) { Response::content(b"root") }).unwrap()
  assert_true(
    router.add("/", [Get], fn(_) { Response::content(b"") }) is Err(Conflict(_)),
  )
  let message = Message::new(Confirmable, Code::request(Put), 1)
  assert_eq(
    router.dispatch({ id: 1, peer: "p", message, received_at: 0L, }).code.value,
    133,
  )
  message.options = [option_text(11, "missing")]
  assert_eq(
    router.dispatch({ id: 1, peer: "p", message, received_at: 0L, }).code.value,
    132,
  )
}
