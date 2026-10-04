///|
test "URI percent encoding preserves segment boundaries and UTF8" {
  let uri = CoapUri::parse(
    "coap://EXAMPLE.com:7777/a%2Fb/%E8%AE%BE%E5%A4%87?x=1&y=a%26b",
    Limits::default(),
  ).unwrap()
  assert_eq(uri.host, "example.com")
  assert_eq(uri.port, 7777)
  assert_eq(uri.path, [b"a/b", @utf8.encode("设备")])
  assert_eq(uri.query, [b"x=1", b"y=a&b"])
  assert_eq(CoapUri::parse(uri.to_string(), Limits::default()), Ok(uri))
  assert_eq(percent_decode("a+b"), Ok(b"a+b"))
  assert_eq(percent_encode(b"a/b"), "a%2Fb")
}

///|
test "IPv6 authorities, empty segments and invalid URIs" {
  let uri = CoapUri::parse("coap://[::1]:5684/a//b/", Limits::default()).unwrap()
  assert_eq(uri.path, [b"a", b"", b"b", b""])
  assert_eq(CoapUri::parse(uri.to_string(), Limits::default()), Ok(uri))
  for
    value in [
      "http://host/a", "coaps://host/a", "coap:///a", "coap://user@host/a", "coap://host:65536/a",
      "coap://host:/a", "coap://host:0/a", "coap://host/a#fragment", "coap://[::1/a",
      "coap://host/%xx", "coap://host/%FF", "coap://host/a b",
    ] {
    assert_true(CoapUri::parse(value, Limits::default()) is Err(_))
  }
}
