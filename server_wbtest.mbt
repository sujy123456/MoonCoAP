///|
fn incoming_post(mid : Int) -> Bytes {
  let message = Message::new(Confirmable, Code::request(Post), mid)
  message.token = b"job"
  message.options = [option_text(11, "jobs")]
  message.payload = b"create"
  encode(message, Limits::default()).unwrap()
}

///|
test "duplicate POST replays identical response and business delivered once" {
  let server = Endpoint::new(Config::default()).unwrap()
  let packet = incoming_post(100)
  ignore(server.receive("client", packet, 0L).unwrap())
  let id = match server.drain()[0] {
    RequestReceived(incoming) => incoming.id
    _ => abort("expected request")
  }
  ignore(server.respond(id, Response::content(b"done"), 1L, 0).unwrap())
  let original = server.drain()
  ignore(server.receive("client", packet, 2L).unwrap())
  assert_eq(server.drain(), original)
  assert_true(
    server.respond(id, Response::content(b"again"), 3L, 0) is Err(Conflict(_)),
  )
}

///|
test "deferred response retains Token, retransmits and accepts Empty ACK" {
  let server = Endpoint::new(Config::default()).unwrap()
  ignore(server.receive("client", incoming_post(100), 0L).unwrap())
  let id = match server.drain()[0] {
    RequestReceived(incoming) => incoming.id
    _ => abort("expected request")
  }
  ignore(server.acknowledge(id, 1L).unwrap())
  let acknowledgement = server.drain()
  assert_eq(acknowledgement.length(), 1)
  ignore(server.respond(id, Response::content(b"done"), 10L, 0).unwrap())
  let wire = match server.drain()[0] {
    SendDatagram(_, wire) => wire
    _ => abort("expected response")
  }
  let response = decode(wire, Limits::default()).unwrap()
  assert_eq(response.msg_type, Confirmable)
  assert_eq(response.token, b"job")
  ignore(server.poll(2010L).unwrap())
  assert_eq(server.drain(), [SendDatagram("client", wire)])
  let ack = encode(
    empty_control(Acknowledgement, response.mid),
    Limits::default(),
  ).unwrap()
  ignore(server.receive("client", ack, 2020L).unwrap())
  ignore(server.poll(6010L).unwrap())
  assert_true(server.drain().is_empty())
}

///|
test "capacity never evicts unexpired POST execution records" {
  let server = Endpoint::new({ ..Config::default(), max_dedup: 1, }).unwrap()
  ignore(server.receive("a", incoming_post(1), 0L).unwrap())
  let id = match server.drain()[0] {
    RequestReceived(incoming) => incoming.id
    _ => abort("expected request")
  }
  ignore(server.respond(id, Response::content(b"one"), 1L, 0).unwrap())
  let reply = server.drain()
  assert_true(server.receive("a", incoming_post(2), 2L) is Err(Capacity(_)))
  assert_true(server.drain().is_empty())
  ignore(server.receive("a", incoming_post(1), 3L).unwrap())
  assert_eq(server.drain(), reply)
}

///|
test "unknown critical CON gets Bad Option; NON is ignored" {
  let server = Endpoint::new(Config::default()).unwrap()
  let message = Message::new(Confirmable, Code::request(Get), 1)
  message.options = [{ number: 101, value: b"", }]
  ignore(
    server
    .receive("a", encode(message, Limits::default()).unwrap(), 0L)
    .unwrap(),
  )
  match server.drain()[0] {
    SendDatagram(_, wire) =>
      assert_eq(decode(wire, Limits::default()).unwrap().code.value, 130)
    _ => abort("expected error response")
  }
  message.msg_type = NonConfirmable
  message.mid = 2
  ignore(
    server
    .receive("a", encode(message, Limits::default()).unwrap(), 1L)
    .unwrap(),
  )
  assert_true(server.drain().is_empty())
}
