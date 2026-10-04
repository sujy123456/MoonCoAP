///|
fn main raise {
  let limits = @coap.Limits::default()
  let store = @coap.ResourceStore::new(8, 4096, [0, 50], true, limits).unwrap()
  store.put("/telemetry", b"23.5", 0, 2L, false).unwrap() |> ignore
  store.put("/config", b"enabled", 0, 60L, true).unwrap() |> ignore
  let discovery = store.discovery(limits).unwrap()
  let message = @coap.Message::new(
    @coap.Confirmable,
    @coap.Code::request(@coap.Get),
    1,
  )
  message.options = [
    @coap.option_text(11, ".well-known"),
    @coap.option_text(11, "core"),
  ]
  let links = @coap.parse_links(discovery.handle(message).payload, limits).unwrap()
  assert_eq(links.length(), 2)
  println("Discovery: 2 reusable resources")
  let request : @coap.Request = {
    ..@coap.Request::new(@coap.Get),
    options: [@coap.option_text(11, "telemetry")],
  }
  message.options = request.options.copy()
  let cache = @coap.ResponseCache::new(8, 4096, limits).unwrap()
  cache.store("device", request, store.handle(message), 0L).unwrap()
  assert_true(cache.lookup("device", request, 1000L).unwrap() is @coap.Fresh(_))
  let validation = match cache.lookup("device", request, 2000L).unwrap() {
    @coap.Stale(_, request) => request
    _ => abort("stale")
  }
  message.options = validation.options.copy()
  let valid = store.handle(message)
  assert_eq(valid.code.value, 67)
  cache.validate("device", validation, valid, 2000L).unwrap()
  assert_true(cache.lookup("device", request, 2001L).unwrap() is @coap.Fresh(_))
  println("Cache: fresh -> stale -> ETag validated -> fresh")
}
