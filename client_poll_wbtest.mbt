///|
test "retransmission backs off, stops at maximum wait and never bursts" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  let (id, _) = submitted_request(endpoint, "server")
  assert_eq(endpoint.next_deadline(), Some(2000L))
  ignore(endpoint.poll(1999L).unwrap())
  assert_true(endpoint.drain().is_empty())
  ignore(endpoint.poll(10000L).unwrap())
  assert_eq(endpoint.drain().length(), 1)
  assert_eq(endpoint.exchanges()[0].retransmissions, 1)
  assert_eq(endpoint.exchanges()[0].next_retry, Some(14000L))
  ignore(endpoint.poll(14000L).unwrap())
  assert_eq(endpoint.drain().length(), 1)
  ignore(endpoint.poll(62000L).unwrap())
  let actions = endpoint.drain()
  assert_true(actions[0] is Failed(request_id, TimedOut) && request_id == id)
  assert_eq(endpoint.exchange_count(), 0)
}

///|
test "Empty ACK disables retransmission while separate timeout remains" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  let (id, request) = submitted_request(endpoint, "server")
  let ack = encode(
    empty_control(Acknowledgement, request.mid),
    Limits::default(),
  ).unwrap()
  ignore(endpoint.receive_response("server", ack, 1L).unwrap())
  ignore(endpoint.poll(62000L).unwrap())
  assert_true(endpoint.drain().is_empty())
  assert_eq(endpoint.exchange_count(), 1)
  ignore(endpoint.poll(247000L).unwrap())
  assert_true(
    endpoint.drain()[0] is Failed(request_id, TimedOut) && request_id == id,
  )
}

///|
test "late responses cannot revive a request when driver has not polled" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  let (_, request) = submitted_request(endpoint, "server")
  let response = Message::new(Acknowledgement, { value: 69, }, request.mid)
  response.token = request.token
  ignore(
    endpoint
    .receive_response(
      "server",
      encode(response, Limits::default()).unwrap(),
      247000L,
    )
    .unwrap(),
  )
  assert_true(endpoint.drain()[0] is Failed(_, TimedOut))
  assert_eq(endpoint.exchange_count(), 0)
}
