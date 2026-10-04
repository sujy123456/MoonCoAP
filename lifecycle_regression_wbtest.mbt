///|
test "serve checks execution record before invoking side-effecting handler" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  endpoint.receive("p", incoming_post(10), 0L).unwrap()
  let incoming = match endpoint.drain()[0] {
    RequestReceived(value) => value
    _ => abort("request")
  }
  let mut executions = 0
  let router = Router::new(2, Limits::default()).unwrap()
  router
  .add("/jobs", [Post], fn(_) {
    executions = executions + 1
    Response::content(b"done")
  })
  .unwrap()
  assert_true(
    endpoint.serve(router, { ..incoming, id: 999, }, 1L) is Err(NotFound(_)),
  )
  assert_eq(executions, 0)
  endpoint.serve(router, incoming, 1L).unwrap()
  endpoint.drain() |> ignore
  assert_true(endpoint.serve(router, incoming, 2L) is Err(Conflict(_)))
  assert_eq(executions, 1)
}

///|
test "invalid handler response can be repaired without executing handler again" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  endpoint.receive("p", incoming_post(10), 0L).unwrap()
  let incoming = match endpoint.drain()[0] {
    RequestReceived(value) => value
    _ => abort("request")
  }
  let mut executions = 0
  let router = Router::new(2, Limits::default()).unwrap()
  router
  .add("/jobs", [Post], fn(_) {
    executions = executions + 1
    Response::error(0)
  })
  .unwrap()
  assert_true(endpoint.serve(router, incoming, 1L) is Err(Invalid(_)))
  assert_true(endpoint.serve(router, incoming, 2L) is Err(Conflict(_)))
  endpoint.respond(incoming.id, Response::content(b"repaired"), 2L, 0).unwrap()
  assert_eq(executions, 1)
}

///|
test "cache replaces repeatable metadata as a group and validates merged limits" {
  let limits = { ..Limits::default(), max_options: 4, }
  let cache = ResponseCache::new(4, 4096, limits).unwrap()
  let request : Request = {
    ..Request::new(Get),
    options: [{ number: 4, value: b"v", }],
  }
  let response : Response = {
    ..Response::content(b"data"),
    options: [
      { number: 4, value: b"v", },
      option_uint(14, 0L).unwrap(),
      { number: 100, value: b"old", },
    ],
  }
  cache.store("p", request, response, 0L).unwrap()
  let valid : Response = {
    code: { value: 67, },
    options: [
      { number: 4, value: b"v", },
      { number: 100, value: b"a", },
      { number: 100, value: b"b", },
    ],
    payload: b"",
  }
  cache.validate("p", request, valid, 1L).unwrap()
  match cache.lookup("p", request, 2L).unwrap() {
    Fresh(response) =>
      assert_eq(
        response.options
        .filter(fn(o) { o.number == 100 })
        .map(fn(o) { o.value }),
        [b"a", b"b"],
      )
    _ => abort("fresh")
  }
  let overflowing : Response = {
    ..valid,
    options: [{ number: 4, value: b"v", }, { number: 104, value: b"extra", }],
  }
  assert_true(cache.validate("p", request, overflowing, 3L) is Err(Capacity(_)))
  assert_eq(cache.stats().validations, 1L)
}

///|
test "cache reserves generated Max-Age and validation option capacity" {
  let limits = { ..Limits::default(), max_options: 2, }
  let cache = ResponseCache::new(4, 4096, limits).unwrap()
  let request : Request = {
    ..Request::new(Get),
    options: [option_text(11, "a"), { number: 100, value: b"x", }],
  }
  let response : Response = {
    ..Response::content(b"data"),
    options: [{ number: 4, value: b"v", }, { number: 100, value: b"x", }],
  }
  assert_true(cache.store("p", request, response, 0L) is Err(Capacity(_)))
  let response : Response = {
    ..response,
    options: [{ number: 4, value: b"v", }, option_uint(14, 0L).unwrap()],
  }
  cache.store("p", request, response, 0L).unwrap()
  assert_true(cache.lookup("p", request, 1L) is Err(Capacity(_)))
}

///|
test "root path representations are equivalent for resource updates" {
  let store = ResourceStore::new(4, 4096, [0], true, Limits::default()).unwrap()
  let message = Message::new(Confirmable, Code::request(Put), 1)
  message.options = [option_text(11, "")]
  message.payload = b"root"
  assert_eq(store.handle(message).code.value, 65)
  assert_eq(store.handle(message).code.value, 68)
  message.code = Code::request(Get)
  assert_eq(store.handle(message).payload, b"root")
  message.options = []
  assert_eq(store.handle(message).payload, b"root")
}

///|
test "unknown NON method receives NON 4.05" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  let message = Message::new(NonConfirmable, { value: 5, }, 100)
  message.token = b"t"
  endpoint
  .receive("p", encode(message, Limits::default()).unwrap(), 0L)
  .unwrap()
  match endpoint.drain()[0] {
    SendDatagram(_, bytes) => {
      let response = decode(bytes, Limits::default()).unwrap()
      assert_eq(response.msg_type, NonConfirmable)
      assert_eq(response.code.value, 133)
      assert_eq(response.token, b"t")
    }
    _ => abort("response")
  }
  assert_true(endpoint.server_records()[0].answered)
}
