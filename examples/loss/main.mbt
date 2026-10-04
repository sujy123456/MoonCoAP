///|
fn main raise {
  let client = @coap.Endpoint::new(@coap.Config::default()).unwrap()
  let server = @coap.Endpoint::new(@coap.Config::default()).unwrap()
  let request : @coap.Request = {
    ..@coap.Request::new(@coap.Post),
    options: [@coap.option_text(11, "jobs")],
    payload: b"job-1",
  }
  client.request("server", request, 0L, 0).unwrap() |> ignore
  let packet = match client.drain()[0] {
    @coap.SendDatagram(_, bytes) => bytes
    _ => abort("request")
  }
  server.receive("client", packet, 0L).unwrap()
  let mut executions = 0
  for action in server.drain() {
    match action {
      @coap.RequestReceived(incoming) => {
        executions = executions + 1
        server
        .respond(incoming.id, @coap.Response::content(b"accepted"), 1L, 0)
        .unwrap()
      }
      _ => ()
    }
  }
  let first_response = server.drain()
  println("Drop first response")
  client.poll(2000L).unwrap()
  let retry = match client.drain()[0] {
    @coap.SendDatagram(_, bytes) => bytes
    _ => abort("retry")
  }
  assert_eq(retry, packet)
  server.receive("client", retry, 2000L).unwrap()
  let replay = server.drain()
  assert_eq(replay, first_response)
  assert_eq(executions, 1)
  for action in replay {
    match action {
      @coap.SendDatagram(_, bytes) =>
        client.receive("server", bytes, 2001L).unwrap()
      _ => abort("duplicate execution")
    }
  }
  assert_true(client.drain()[0] is @coap.ResponseReceived(_, _))
  println("POST retried; business executions=1; cached reply replayed")
}
