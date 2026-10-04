///|
fn main raise {
  let client = @coap.Endpoint::new(@coap.Config::default()).unwrap()
  let server = @coap.Endpoint::new(@coap.Config::default()).unwrap()
  let router = @coap.Router::new(4, @coap.Limits::default()).unwrap()
  router
  .add("/status", [@coap.Get], fn(_) { @coap.Response::content(b"ready") })
  .unwrap()
  let (_, request) = @coap.Request::from_uri(
    @coap.Get,
    "coap://device/status",
    @coap.Limits::default(),
  ).unwrap()
  let id = client.request("server", request, 0L, 0).unwrap()
  for action in client.drain() {
    match action {
      @coap.SendDatagram(_, bytes) =>
        server.receive("client", bytes, 0L).unwrap()
      _ => ()
    }
  }
  for action in server.drain() {
    match action {
      @coap.RequestReceived(incoming) =>
        server.serve(router, incoming, 1L).unwrap()
      _ => ()
    }
  }
  for action in server.drain() {
    match action {
      @coap.SendDatagram(_, bytes) =>
        client.receive("server", bytes, 2L).unwrap()
      _ => ()
    }
  }
  for action in client.drain() {
    match action {
      @coap.ResponseReceived(received, message) => {
        assert_eq(received, id)
        assert_eq(message.payload, b"ready")
        println("GET /status -> 2.05 ready")
      }
      _ => abort("unexpected action")
    }
  }
  assert_eq(client.exchange_count(), 0)
}
