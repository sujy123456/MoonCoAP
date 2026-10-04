///|
fn submitted_request(endpoint : Endpoint, peer : String) -> (Int, Message) {
  let id = endpoint.request(peer, Request::new(Get), 0L, 0).unwrap()
  let actions = endpoint.drain()
  match actions[0] {
    SendDatagram(_, wire) => (id, decode(wire, Limits::default()).unwrap())
    _ => abort("expected an outgoing request")
  }
}

///|
test "piggybacked response requires both MID and Token from same peer" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  let (id, request) = submitted_request(endpoint, "server")
  let response = Message::new(Acknowledgement, { value: 69, }, request.mid)
  response.token = b"wrong"
  ignore(
    endpoint
    .receive_response(
      "server",
      encode(response, Limits::default()).unwrap(),
      1L,
    )
    .unwrap(),
  )
  assert_eq(endpoint.exchange_count(), 1)
  response.token = request.token
  ignore(
    endpoint
    .receive_response("other", encode(response, Limits::default()).unwrap(), 1L)
    .unwrap(),
  )
  assert_eq(endpoint.exchange_count(), 1)
  response.payload = b"ok"
  ignore(
    endpoint
    .receive_response(
      "server",
      encode(response, Limits::default()).unwrap(),
      2L,
    )
    .unwrap(),
  )
  let actions = endpoint.drain()
  assert_true(actions[0] is ResponseReceived(request_id, _) && request_id == id)
  assert_eq(endpoint.exchange_count(), 0)
}

///|
test "Empty ACK releases NSTART but retains separate response waiter" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  let (_id, request) = submitted_request(endpoint, "server")
  ignore(endpoint.request("server", Request::new(Get), 0L, 0).unwrap())
  let ack = encode(
    empty_control(Acknowledgement, request.mid),
    Limits::default(),
  ).unwrap()
  ignore(endpoint.receive_response("server", ack, 10L).unwrap())
  assert_eq(endpoint.exchange_count(), 2)
  assert_eq(endpoint.exchanges()[0].phase, WaitingResponse)
  assert_eq(endpoint.queued_count(), 0)
  assert_eq(endpoint.drain().length(), 1)
  let response = Message::new(Confirmable, { value: 69, }, 777)
  response.token = request.token
  let wire = encode(response, Limits::default()).unwrap()
  ignore(endpoint.receive_response("server", wire, 20L).unwrap())
  assert_eq(endpoint.drain().length(), 2)
  ignore(endpoint.receive_response("server", wire, 30L).unwrap())
  let repeated = endpoint.drain()
  assert_eq(repeated.length(), 1)
  assert_true(repeated[0] is SendDatagram(_, _))
}

///|
test "unmatched CON response reset, unknown critical NON ignored" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  let response = Message::new(Confirmable, { value: 69, }, 9)
  response.token = b"orphan"
  ignore(
    endpoint
    .receive_response(
      "server",
      encode(response, Limits::default()).unwrap(),
      0L,
    )
    .unwrap(),
  )
  match endpoint.drain()[0] {
    SendDatagram(_, wire) =>
      assert_eq(decode(wire, Limits::default()).unwrap().msg_type, Reset)
    _ => abort("expected Reset")
  }
  let (_, request) = submitted_request(endpoint, "server")
  response.msg_type = NonConfirmable
  response.token = request.token
  response.options = [{ number: 101, value: b"", }]
  ignore(
    endpoint
    .receive_response(
      "server",
      encode(response, Limits::default()).unwrap(),
      1L,
    )
    .unwrap(),
  )
  assert_eq(endpoint.exchange_count(), 1)
  assert_true(endpoint.drain().is_empty())
}
