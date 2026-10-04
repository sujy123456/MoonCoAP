///|
test "link format roundtrip preserves quoted delimiters unicode and flags" {
  let bytes = @utf8.encode(
    "</a>;rt=\"sensor light\";title=\"温度, \\\"室内\\\"\";obs, </b>;ct=\"0 50\"",
  )
  let links = parse_links(bytes, Limits::default()).unwrap()
  assert_eq(links.length(), 2)
  assert_eq(links[0].attribute("title"), Some("温度, \"室内\""))
  assert_eq(
    parse_links(
      serialize_links(links, Limits::default()).unwrap(),
      Limits::default(),
    ).unwrap(),
    links,
  )
}

///|
test "discovery parser rejects truncation duplicates and resource overflow" {
  for
    malformed in [
      b"</a", b"</a>,", b"</a>;rt=", b"</a>;title=\"x", b"</a>;ct=70000", b"</a>;sz=-1",
      b"</a>;rt=x;rt=y", b"</a> garbage",
    ] {
    assert_true(parse_links(malformed, Limits::default()) is Err(_))
  }
  assert_true(
    parse_links(b"</a>,</b>", { ..Limits::default(), max_links: 1, })
    is Err(Capacity(_)),
  )
}

///|
test "discovery exact token prefix and existence filters" {
  let discovery = Discovery::new(Limits::default()).unwrap()
  discovery
  .add({
    target: "/a",
    attributes: [
      { name: "rt", value: Some("sensor temperature"), },
      { name: "obs", value: None, },
    ],
  })
  .unwrap()
  discovery
  .add({ target: "/b", attributes: [{ name: "rt", value: Some("actuator"), }], })
  .unwrap()
  for
    (query, count) in [
      ("rt=sensor", 1),
      ("rt=temp*", 1),
      ("rt=*", 2),
      ("obs=*", 1),
      ("href=/a", 1),
      ("href=/missing*", 0),
    ] {
    let message = Message::new(Confirmable, Code::request(Get), 1)
    message.options = [
      option_text(11, ".well-known"),
      option_text(11, "core"),
      option_text(15, query),
    ]
    assert_eq(
      parse_links(discovery.handle(message).payload, Limits::default())
      .unwrap()
      .length(),
      count,
    )
  }
  assert_true(LinkFilter::parse("rt=s*or") is Err(_))
}
