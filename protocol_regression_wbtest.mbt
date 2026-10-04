///|
test "reserved response class cannot be constructed or decoded" {
  assert_true(Code::response(3, 1) is Err(_))
  assert_true(decode(b"\x40\x61\x00\x01", Limits::default()) is Err(_))
}

///|
test "invalid elective options are ignored but critical options fail" {
  let message = Message::new(Acknowledgement, { value: 141, }, 1)
  message.options = [
    option_uint(60, 1024L).unwrap(),
    { number: 12, value: b"\x00\x00\x00", },
    { number: 4, value: b"a", },
    { number: 4, value: b"b", },
  ]
  let options = received_options(message, []).unwrap()
  assert_eq(options.length(), 2)
  assert_eq(options[0].number, 60)
  assert_eq(options[1].value, b"a")
  message.options = [{ number: 11, value: b"..", }]
  assert_true(received_options(message, []) is Err(_))
}

///|
test "client accepts 4.13 Size1 response" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  let (id, request) = submitted_request(endpoint, "server")
  let response = Message::new(Acknowledgement, { value: 141, }, request.mid)
  response.token = request.token
  response.options = [option_uint(60, 512L).unwrap()]
  endpoint
  .receive("server", encode(response, Limits::default()).unwrap(), 1L)
  .unwrap()
  assert_true(
    endpoint.drain()[0] is ResponseReceived(received_id, received) &&
    received_id == id &&
    received.code.value == 141,
  )
}

///|
test "late poll stops transmission at MAX_TRANSMIT_SPAN but still waits for ACK" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  let (_, request) = submitted_request(endpoint, "server")
  endpoint.poll(50000L).unwrap()
  assert_true(endpoint.drain().is_empty())
  assert_eq(endpoint.exchanges()[0].next_retry, None)
  let ack = empty_control(Acknowledgement, request.mid)
  endpoint
  .receive("server", encode(ack, Limits::default()).unwrap(), 50001L)
  .unwrap()
  assert_eq(endpoint.exchanges()[0].phase, WaitingResponse)
}

///|
test "ACK exactly at server retry time does not cause an extra resend" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  endpoint.receive("client", incoming_post(100), 0L).unwrap()
  let id = match endpoint.drain()[0] {
    RequestReceived(request) => request.id
    _ => abort("request")
  }
  endpoint.acknowledge(id, 0L).unwrap()
  endpoint.drain() |> ignore
  endpoint.respond(id, Response::content(b"done"), 0L, 0).unwrap()
  let wire = match endpoint.drain()[0] {
    SendDatagram(_, bytes) => bytes
    _ => abort("response")
  }
  let mid = decode(wire, Limits::default()).unwrap().mid
  endpoint
  .receive(
    "client",
    encode(empty_control(Acknowledgement, mid), Limits::default()).unwrap(),
    2000L,
  )
  .unwrap()
  assert_true(endpoint.drain().is_empty())
  assert_eq(endpoint.server_records()[0].response_phase, Some(Finished))
}

///|
test "expired queued client is never started by cancellation" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  let first = endpoint.request("p", Request::new(Get), 0L, 0).unwrap()
  endpoint.request("p", Request::new(Get), 0L, 0).unwrap() |> ignore
  endpoint.drain() |> ignore
  endpoint.cancel(first, 247001L).unwrap()
  let actions = endpoint.drain()
  assert_true(!actions.any(fn(a) { a is SendDatagram(_, _) }))
  assert_eq(endpoint.exchange_count(), 0)
}

///|
test "automatic error reply remains atomic under outbox backpressure" {
  let endpoint = Endpoint::new({ ..Config::default(), max_actions: 516, }).unwrap()
  for i = 0; i < 129; i = i + 1 {
    endpoint.outbox.push(Cancelled(i))
  }
  let message = Message::new(Confirmable, Code::request(Get), 8)
  message.options = [{ number: 101, value: b"", }]
  endpoint
  .receive_request("p", encode(message, Limits::default()).unwrap(), 0L)
  .unwrap()
  let actions = endpoint.drain()
  assert_eq(actions.length(), 130)
  assert_true(actions[129] is SendDatagram(_, _))
  assert_true(endpoint.server_records()[0].answered)
}

///|
test "only malformed identifiable CON triggers Reset" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  assert_true(endpoint.receive("p", b"\x49\x01\x00\x64", 0L) is Err(_))
  let actions = endpoint.drain()
  assert_eq(actions.length(), 1)
  match actions[0] {
    SendDatagram(_, wire) =>
      assert_eq(
        decode(wire, Limits::default()).unwrap(),
        empty_control(Reset, 100),
      )
    _ => abort("reset")
  }
  for wire in [b"\x89\x01\x00\x64", b"\x69\x01\x00\x64", b"\x40\x01"] {
    assert_true(endpoint.receive("p", wire, 1L) is Err(_))
    assert_true(endpoint.drain().is_empty())
  }
}
