///|
pub(all) struct LinkAttribute {
  name : String
  value : String?
} derive(Eq, Debug)

///|
pub extend LinkAttribute with Eq::{equal, not_equal}

///|
pub extend LinkAttribute with @debug.Debug::{to_repr}

///|
pub(all) struct CoreLink {
  target : String
  attributes : Array[LinkAttribute]
} derive(Eq, Debug)

///|
pub extend CoreLink with Eq::{equal, not_equal}

///|
pub extend CoreLink with @debug.Debug::{to_repr}

///|
pub fn CoreLink::attribute(self : CoreLink, name : String) -> String? {
  for attribute in self.attributes {
    if attribute.name == name {
      return attribute.value
    }
  }
  None
}

///|
fn link_token(value : Int) -> Bool {
  (value >= 48 && value <= 57) ||
  (value >= 65 && value <= 90) ||
  (value >= 97 && value <= 122) ||
  value == 33 ||
  value == 35 ||
  value == 36 ||
  value == 37 ||
  value == 38 ||
  value == 39 ||
  value == 42 ||
  value == 43 ||
  value == 45 ||
  value == 46 ||
  value == 94 ||
  value == 95 ||
  value == 96 ||
  value == 124 ||
  value == 126
}

///|
fn unsigned_decimal(text : String, maximum : Int64) -> Result[Int64, Failure] {
  if text.is_empty() {
    return Err(Invalid("empty decimal attribute"))
  }
  let mut value = 0L
  for character in text.iter() {
    let digit = character.to_int() - 48
    if digit < 0 || digit > 9 || value > (maximum - digit.to_int64()) / 10L {
      return Err(Invalid("invalid or overflowing decimal attribute"))
    }
    value = value * 10L + digit.to_int64()
  }
  Ok(value)
}

///|
pub fn CoreLink::validate(
  self : CoreLink,
  limits : Limits,
) -> Result[Unit, Failure] {
  if self.target.is_empty() ||
    @utf8.encode(self.target).length() > limits.max_uri_bytes {
    return Err(Invalid("invalid link target length"))
  }
  for character in self.target.iter() {
    let value = character.to_int()
    if value <= 32 ||
      value >= 127 ||
      value == 60 ||
      value == 62 ||
      value == 34 ||
      value == 92 {
      return Err(Invalid("link target must be an escaped ASCII URI reference"))
    }
  }
  match percent_decode(self.target) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if self.attributes.length() > limits.max_link_attributes {
    return Err(Capacity("too many link attributes"))
  }
  let singleton : Array[String] = []
  for attribute in self.attributes {
    if attribute.name.is_empty() ||
      !attribute.name.iter().all(fn(c) { link_token(c.to_int()) }) {
      return Err(Invalid("invalid link attribute name"))
    }
    if ["rt", "if", "sz", "ct", "title", "anchor", "rel"].contains(
        attribute.name,
      ) {
      if singleton.contains(attribute.name) {
        return Err(Invalid("duplicate singleton link attribute"))
      }
      singleton.push(attribute.name)
    }
    match attribute.value {
      None =>
        if attribute.name == "rt" ||
          attribute.name == "if" ||
          attribute.name == "sz" ||
          attribute.name == "ct" {
          return Err(Invalid("standard link attribute requires a value"))
        }
      Some(value) => {
        if @utf8.encode(value).length() > limits.max_uri_bytes {
          return Err(Capacity("link attribute value too long"))
        }
        if value.iter().any(fn(c) { c.to_int() < 32 || c.to_int() == 127 }) {
          return Err(Invalid("control byte in link value"))
        }
        if attribute.name == "sz" {
          match unsigned_decimal(value, 4294967295L) {
            Err(e) => return Err(e)
            Ok(_) => ()
          }
        }
        if attribute.name == "ct" {
          for format in value.split(" ") {
            match unsigned_decimal(format.to_owned(), 65535L) {
              Err(e) => return Err(e)
              Ok(_) => ()
            }
          }
        }
        if (attribute.name == "rt" || attribute.name == "if") &&
          value.is_empty() {
          return Err(Invalid("empty relation attribute"))
        }
      }
    }
  }
  Ok(())
}

///|
priv struct LinkParser {
  bytes : Bytes
  mut cursor : Int
  limits : Limits
}

///|
fn LinkParser::skip_space(self : LinkParser) -> Unit {
  while self.cursor < self.bytes.length() &&
        (self.bytes[self.cursor] == b' ' || self.bytes[self.cursor] == b'\t') {
    self.cursor = self.cursor + 1
  }
}

///|
fn LinkParser::token(self : LinkParser) -> Result[String, Failure] {
  let start = self.cursor
  while self.cursor < self.bytes.length() &&
        link_token(self.bytes[self.cursor].to_int()) {
    self.cursor = self.cursor + 1
  }
  if self.cursor == start {
    return Err(Syntax(start, "expected link token"))
  }
  decode_utf8(slice_bytes(self.bytes, start, self.cursor))
}

///|
fn LinkParser::quoted(self : LinkParser) -> Result[String, Failure] {
  let output : Array[Byte] = []
  self.cursor = self.cursor + 1
  while self.cursor < self.bytes.length() {
    let byte = self.bytes[self.cursor]
    self.cursor = self.cursor + 1
    if byte == b'"' {
      return decode_utf8(Bytes::from_array(output))
    }
    if byte == b'\\' {
      if self.cursor == self.bytes.length() {
        return Err(Syntax(self.cursor, "truncated quoted escape"))
      }
      let escaped = self.bytes[self.cursor]
      if escaped.to_int() < 32 || escaped.to_int() == 127 {
        return Err(Syntax(self.cursor, "control byte in quoted escape"))
      }
      output.push(escaped)
      self.cursor = self.cursor + 1
    } else {
      if byte.to_int() < 32 || byte.to_int() == 127 {
        return Err(Syntax(self.cursor - 1, "control byte in quoted string"))
      }
      output.push(byte)
    }
    if output.length() > self.limits.max_uri_bytes {
      return Err(Capacity("quoted link value is too long"))
    }
  }
  Err(Syntax(self.cursor, "unterminated quoted string"))
}

///|
fn LinkParser::link(self : LinkParser) -> Result[CoreLink, Failure] {
  self.skip_space()
  if self.cursor >= self.bytes.length() || self.bytes[self.cursor] != b'<' {
    return Err(Syntax(self.cursor, "expected opening angle bracket"))
  }
  self.cursor = self.cursor + 1
  let start = self.cursor
  while self.cursor < self.bytes.length() && self.bytes[self.cursor] != b'>' {
    self.cursor = self.cursor + 1
  }
  if self.cursor == self.bytes.length() {
    return Err(Syntax(self.cursor, "unclosed link target"))
  }
  let target = match decode_utf8(slice_bytes(self.bytes, start, self.cursor)) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  self.cursor = self.cursor + 1
  let attributes : Array[LinkAttribute] = []
  self.skip_space()
  while self.cursor < self.bytes.length() && self.bytes[self.cursor] == b';' {
    if attributes.length() >= self.limits.max_link_attributes {
      return Err(Capacity("too many link attributes"))
    }
    self.cursor = self.cursor + 1
    self.skip_space()
    let name = match self.token() {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    self.skip_space()
    let mut value : String? = None
    if self.cursor < self.bytes.length() && self.bytes[self.cursor] == b'=' {
      self.cursor = self.cursor + 1
      self.skip_space()
      let parsed = if self.cursor < self.bytes.length() &&
        self.bytes[self.cursor] == b'"' {
        self.quoted()
      } else {
        self.token()
      }
      value = Some(
        match parsed {
          Err(e) => return Err(e)
          Ok(v) => v
        },
      )
    }
    attributes.push({ name, value, })
    self.skip_space()
  }
  let link : CoreLink = { target, attributes, }
  match link.validate(self.limits) {
    Err(e) => Err(e)
    Ok(_) => Ok(link)
  }
}

///|
pub fn parse_links(
  payload : Bytes,
  limits : Limits,
) -> Result[Array[CoreLink], Failure] {
  match limits.validate() {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if payload.length() > limits.max_payload {
    return Err(Capacity("discovery payload exceeds limit"))
  }
  let parser : LinkParser = { bytes: payload, cursor: 0, limits, }
  let links : Array[CoreLink] = []
  parser.skip_space()
  while parser.cursor < payload.length() {
    if links.length() >= limits.max_links {
      return Err(Capacity("too many discovery links"))
    }
    match parser.link() {
      Err(e) => return Err(e)
      Ok(link) => links.push(link)
    }
    if parser.cursor == payload.length() {
      break
    }
    if payload[parser.cursor] != b',' {
      return Err(Syntax(parser.cursor, "expected comma between links"))
    }
    parser.cursor = parser.cursor + 1
    parser.skip_space()
    if parser.cursor == payload.length() {
      return Err(Syntax(parser.cursor, "trailing link separator"))
    }
  }
  Ok(links)
}

///|
fn quote_link_value(text : String) -> String {
  let characters : Array[Char] = ['"']
  for character in text.iter() {
    if character == '"' || character == '\\' {
      characters.push('\\')
    }
    characters.push(character)
  }
  characters.push('"')
  String::from_array(characters)
}

///|
pub fn serialize_links(
  links : Array[CoreLink],
  limits : Limits,
) -> Result[Bytes, Failure] {
  match limits.validate() {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if links.length() > limits.max_links {
    return Err(Capacity("too many links"))
  }
  let mut text = ""
  for i = 0; i < links.length(); i = i + 1 {
    let link = links[i]
    match link.validate(limits) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
    if i > 0 {
      text = text + ","
    }
    text = text + "<" + link.target + ">"
    for attribute in link.attributes {
      text = text + ";" + attribute.name
      match attribute.value {
        None => ()
        Some(value) => text = text + "=" + quote_link_value(value)
      }
    }
    if @utf8.encode(text).length() > limits.max_payload {
      return Err(Capacity("discovery serialization exceeds payload limit"))
    }
  }
  Ok(@utf8.encode(text))
}

///|
pub(all) struct LinkFilter {
  name : String
  value : String
  prefix : Bool
} derive(Eq, Debug)

///|
pub extend LinkFilter with Eq::{equal, not_equal}

///|
pub extend LinkFilter with @debug.Debug::{to_repr}

///|
pub fn LinkFilter::parse(query : String) -> Result[LinkFilter, Failure] {
  let (name, value) = match query.split_once("=") {
    None => return Err(Invalid("discovery filter requires name=value"))
    Some((name, value)) => (name.to_owned(), value.to_owned())
  }
  if name.is_empty() || !name.iter().all(fn(c) { link_token(c.to_int()) }) {
    return Err(Invalid("invalid discovery filter name"))
  }
  let prefix = value.has_suffix("*")
  let value = if prefix { value[:value.length() - 1].to_owned() } else { value }
  if value.contains("*") {
    return Err(Invalid("only a final wildcard is supported"))
  }
  if value.iter().any(fn(c) { c.to_int() < 32 || c.to_int() == 127 }) {
    return Err(Invalid("invalid filter value"))
  }
  Ok({ name, value, prefix, })
}

///|
fn LinkFilter::matches_value(self : LinkFilter, value : String) -> Bool {
  if self.prefix {
    value.has_prefix(self.value)
  } else {
    value == self.value
  }
}

///|
pub fn LinkFilter::matches(self : LinkFilter, link : CoreLink) -> Bool {
  if self.name == "href" {
    return self.matches_value(link.target)
  }
  for attribute in link.attributes {
    if attribute.name != self.name {
      continue
    }
    match attribute.value {
      None => if self.prefix && self.value.is_empty() { return true }
      Some(value) =>
        if ["rt", "if", "rel", "ct"].contains(self.name) {
          for token in value.split(" ") {
            if self.matches_value(token.to_owned()) {
              return true
            }
          }
        } else if self.matches_value(value) {
          return true
        }
    }
  }
  false
}

///|
pub struct Discovery {
  priv limits : Limits
  priv mut links : Array[CoreLink]
}

///|
pub fn Discovery::new(limits : Limits) -> Result[Discovery, Failure] {
  match limits.validate() {
    Err(e) => Err(e)
    Ok(_) => Ok({ limits, links: [], })
  }
}

///|
pub fn Discovery::add(
  self : Discovery,
  link : CoreLink,
) -> Result[Unit, Failure] {
  match link.validate(self.limits) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if !link.target.has_prefix("/") ||
    link.target.has_prefix("//") ||
    link.attribute("anchor") is Some(_) {
    return Err(
      Unsupported(
        "local discovery catalog requires origin paths without anchors",
      ),
    )
  }
  let candidate = self.links.filter(fn(existing) {
    existing.target != link.target
  })
  candidate.push({ target: link.target, attributes: link.attributes.copy(), })
  match serialize_links(candidate, self.limits) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  self.links = candidate
  Ok(())
}

///|
pub fn Discovery::remove(self : Discovery, target : String) -> Bool {
  let before = self.links.length()
  self.links = self.links.filter(fn(link) { link.target != target })
  before != self.links.length()
}

///|
pub fn Discovery::links(self : Discovery) -> Array[CoreLink] {
  self.links.map(fn(link) {
    { target: link.target, attributes: link.attributes.copy(), }
  })
}

///|
pub fn Discovery::handle(self : Discovery, message : Message) -> Response {
  if message.option_values(11) != [b".well-known", b"core"] {
    return Response::error(132)
  }
  if message.code.verb() != Some(Get) {
    return Response::error(133)
  }
  match message_uint(message, 17, 40L) {
    Err(_) => return Response::error(130)
    Ok(v) => if v != 40L { return Response::error(134) }
  }
  let queries = match request_queries(message) {
    Err(_) => return Response::error(128)
    Ok(v) => v
  }
  if queries.length() > 1 {
    return Response::error(128)
  }
  let filter = if queries.is_empty() {
    None
  } else {
    match LinkFilter::parse(queries[0]) {
      Err(_) => return Response::error(128)
      Ok(v) => Some(v)
    }
  }
  let selected = match filter {
    None => self.links
    Some(filter) => self.links.filter(fn(link) { filter.matches(link) })
  }
  match serialize_links(selected, self.limits) {
    Err(_) => Response::error(163)
    Ok(payload) =>
      {
        code: { value: 69, },
        options: [option_uint(12, 40L).unwrap()],
        payload,
      }
  }
}

///|
pub fn ResourceStore::discovery(
  self : ResourceStore,
  limits : Limits,
) -> Result[Discovery, Failure] {
  let discovery = match Discovery::new(limits) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  for info in self.inventory() {
    let link : CoreLink = {
      target: info.path,
      attributes: [
        { name: "ct", value: Some(info.content_format.to_string()), },
        { name: "sz", value: Some(info.size.to_string()), },
      ],
    }
    match discovery.add(link) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  Ok(discovery)
}
