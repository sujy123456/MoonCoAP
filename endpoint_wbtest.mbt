///|
test "NSTART queues same peer, cancellation promotes next request" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  let first = endpoint.request("peer", Request::new(Get), 0L, 0).unwrap()
  let second = endpoint.request("peer", Request::new(Get), 0L, 0).unwrap()
  assert_eq(endpoint.active_for_peer("peer"), 1)
  assert_eq(endpoint.queued_count(), 1)
  assert_eq(endpoint.drain().length(), 1)
  assert_eq(endpoint.cancel(first, 1L), Ok(()))
  let actions = endpoint.drain()
  assert_eq(actions.length(), 2)
  assert_true(actions[0] is Cancelled(_))
  assert_true(actions[1] is SendDatagram(_, _))
  assert_eq(endpoint.exchanges()[0].id, second)
  assert_eq(endpoint.exchanges()[0].phase, Sending)
}

///|
test "NON requests also occupy an outstanding interaction" {
  let endpoint = Endpoint::new(Config::default()).unwrap()
  let non : Request = { ..Request::new(Get), confirmable: false, }
  ignore(endpoint.request("a", non, 0L, 0).unwrap())
  ignore(endpoint.request("a", Request::new(Get), 0L, 0).unwrap())
  ignore(endpoint.request("b", Request::new(Get), 0L, 0).unwrap())
  assert_eq(endpoint.queued_count(), 1)
  assert_eq(endpoint.active_peers().length(), 2)
  assert_eq(endpoint.drain().length(), 2)
  assert_true(endpoint.request("a", non, -1L, 0) is Err(Clock(_)))
}
