///|
test "IPv6 literals validate and canonicalize equivalent forms" {
  for
    (input, output) in [
      ("0:0:0:0:0:0:0:0", "::"),
      ("0:0:0:0:0:0:0:1", "::1"),
      ("2001:0DB8:0:0:1:0:0:1", "2001:db8::1:0:0:1"),
      ("::ffff:192.0.2.1", "::ffff:c000:201"),
    ] {
    assert_eq(canonical_ipv6(input).unwrap(), output)
    assert_eq(parse_ipv6(input).unwrap(), parse_ipv6(output).unwrap())
  }
  for
    input in [
      ":::", "1::2::3", "1:2:3", "1:2:3:4:5:6:7:8:9", "1:2:3:4:5:6:7:8::", "::gggg",
      "::ffff:999.0.0.1", "fe80::1%eth0",
    ] {
    assert_true(parse_ipv6(input) is Err(_))
  }
}

///|
test "URI dot segments resolve before options and encoded slash stays a segment" {
  let uri = CoapUri::parse(
    "coap://[2001:0db8:0:0:0:0:0:1]/a/../b/./c%2Fd",
    Limits::default(),
  ).unwrap()
  assert_eq(uri.host, "2001:db8::1")
  assert_eq(uri.path, [b"b", b"c/d"])
  assert_true(CoapUri::parse("coap://[:::]/", Limits::default()) is Err(_))
}
