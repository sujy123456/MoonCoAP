///|
async fn main {
  let limits = @coap.Limits::default()
  let store = @coap.ResourceStore::new(16, 8192, [0, 50], true, limits).unwrap()
  store.put("/status", b"ready", 0, 2L, false).unwrap() |> ignore
  store.put("/config", b"initial", 0, 60L, true).unwrap() |> ignore
  let server = @udp.UdpEndpoint::bind(
    "127.0.0.1:56830",
    @udp.network_config(@coap.Config::default()),
  )
  defer server.close()
  println("READY 127.0.0.1:56830")
  let mut jobs = 0
  while server.now() < 60000L {
    for event in server.step(100) {
      match event {
        @udp.Delivered(@coap.RequestReceived(incoming)) => {
          let path = incoming.message.option_values(11)
          if path == [b".well-known", b"core"] {
            server.respond(
              incoming.id,
              store.discovery(limits).unwrap().handle(incoming.message),
            )
          } else if path == [b"separate"] {
            server.acknowledge(incoming.id)
            server.respond(incoming.id, @coap.Response::content(b"deferred"))
          } else if path == [b"jobs"] &&
            incoming.message.code.verb() == Some(@coap.Post) {
            jobs = jobs + 1
            server.respond(
              incoming.id,
              @coap.Response::content(@utf8.encode(jobs.to_string())),
            )
          } else {
            server.respond(incoming.id, store.handle(incoming.message))
          }
        }
        _ => ()
      }
    }
  }
}
