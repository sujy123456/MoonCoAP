///|
pub(all) struct CoapUri {
  host : String
  port : Int
  path : Array[Bytes]
  query : Array[Bytes]
} derive(Eq, Debug)

///|
pub extend CoapUri with Eq::{equal, not_equal}

///|
pub extend CoapUri with @debug.Debug::{to_repr}

///|
pub fn percent_decode(text : String) -> Result[Bytes, Failure] {
  let input = @utf8.encode(text)
  let output : Array[Byte] = []
  let mut cursor = 0
  while cursor < input.length() {
    if input[cursor] == b'%' {
      if cursor > input.length() - 3 {
        return Err(Syntax(cursor, "truncated percent escape"))
      }
      let high = hex_digit(input[cursor + 1].to_int())
      let low = hex_digit(input[cursor + 2].to_int())
      if high < 0 || low < 0 {
        return Err(Syntax(cursor, "invalid percent escape"))
      }
      output.push((high * 16 + low).to_byte())
      cursor = cursor + 3
    } else {
      let value = input[cursor].to_int()
      if value < 32 || value == 127 || value == 32 {
        return Err(Syntax(cursor, "unescaped whitespace or control character"))
      }
      output.push(input[cursor])
      cursor = cursor + 1
    }
  }
  Ok(Bytes::from_array(output))
}

///|
pub fn percent_encode(bytes : Bytes) -> String {
  let digits = "0123456789ABCDEF"
  let result : Array[Char] = []
  for byte in bytes {
    let value = byte.to_int()
    if (value >= 65 && value <= 90) ||
      (value >= 97 && value <= 122) ||
      (value >= 48 && value <= 57) ||
      value == 45 ||
      value == 46 ||
      value == 95 ||
      value == 126 {
      result.push(value.unsafe_to_char())
    } else {
      result.push('%')
      result.push(digits.get_char(value >> 4).unwrap())
      result.push(digits.get_char(value & 15).unwrap())
    }
  }
  String::from_array(result)
}

///|
fn parse_port(text : String) -> Result[Int, Failure] {
  if text.is_empty() {
    return Err(Invalid("empty URI port"))
  }
  let mut value = 0
  for character in text.iter() {
    let digit = character.to_int() - 48
    if digit < 0 || digit > 9 {
      return Err(Invalid("URI port must be decimal"))
    }
    if value > (65535 - digit) / 10 {
      return Err(Invalid("URI port exceeds 65535"))
    }
    value = value * 10 + digit
  }
  if value == 0 {
    return Err(Invalid("URI port must be nonzero"))
  }
  Ok(value)
}

///|
fn split_uri_segments(
  text : String,
  separator : String,
) -> Result[Array[Bytes], Failure] {
  let result : Array[Bytes] = []
  for segment in text.split(separator) {
    let value = match percent_decode(segment.to_owned()) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    if value.length() > 255 {
      return Err(Capacity("URI segment exceeds option length"))
    }
    match decode_utf8(value) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
    result.push(value)
  }
  Ok(result)
}

///|
pub fn CoapUri::parse(
  text : String,
  limits : Limits,
) -> Result[CoapUri, Failure] {
  match limits.validate() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if @utf8.encode(text).length() > limits.max_uri_bytes {
    return Err(Capacity("URI exceeds configured limit"))
  }
  if !text.has_prefix("coap://") {
    return Err(Unsupported("only coap:// URIs are supported"))
  }
  if text.contains("#") {
    return Err(Invalid("CoAP request URI must not contain a fragment"))
  }
  let mut authority_end = text.length()
  for i = 7; i < text.length(); i = i + 1 {
    if text[i].to_int() == 47 || text[i].to_int() == 63 {
      authority_end = i
      break
    }
  }
  let authority = text[7:authority_end].to_owned()
  if authority.is_empty() || authority.contains("@") {
    return Err(Invalid("empty host or unsupported userinfo"))
  }
  let mut host = ""
  let mut port = 5683
  if authority.has_prefix("[") {
    let closing = match authority.find("]") {
      Some(index) => index
      None => return Err(Invalid("unclosed IPv6 address"))
    }
    host = authority[1:closing].to_owned()
    if !host.contains(":") || host.contains("%") {
      return Err(Invalid("invalid or scoped IPv6 literal"))
    }
    host = match canonical_ipv6(host) {
      Err(e) => return Err(e)
      Ok(v) => v
    }
    let suffix = authority[closing + 1:].to_owned()
    if !suffix.is_empty() {
      if !suffix.has_prefix(":") {
        return Err(Invalid("unexpected bytes after IPv6 address"))
      }
      port = match parse_port(suffix[1:].to_owned()) {
        Ok(value) => value
        Err(error) => return Err(error)
      }
    }
  } else {
    match authority.split_once(":") {
      None => host = authority
      Some((name, port_text)) => {
        host = name.to_owned()
        port = match parse_port(port_text.to_owned()) {
          Ok(value) => value
          Err(error) => return Err(error)
        }
      }
    }
  }
  if host.is_empty() || @utf8.encode(host).length() > 255 {
    return Err(Invalid("invalid host length"))
  }
  for character in host.iter() {
    let value = character.to_int()
    if value <= 32 ||
      value >= 127 ||
      value == 47 ||
      value == 63 ||
      value == 91 ||
      value == 93 ||
      value == 37 {
      return Err(Invalid("host must be an ASCII name or IP literal"))
    }
  }
  let remainder = text[authority_end:].to_owned()
  let (path_text, query_text) = match remainder.split_once("?") {
    None => (remainder, None)
    Some((path, query)) => (path.to_owned(), Some(query.to_owned()))
  }
  let path = if path_text.is_empty() || path_text == "/" {
    []
  } else {
    if !path_text.has_prefix("/") {
      return Err(Invalid("absolute URI path must start with slash"))
    }
    match split_uri_segments(path_text[1:].to_owned(), "/") {
      Ok(value) => value
      Err(error) => return Err(error)
    }
  }
  let normalized : Array[Bytes] = []
  for i = 0; i < path.length(); i = i + 1 {
    let part = path[i]
    if part == b".." {
      if !normalized.is_empty() {
        normalized.remove(normalized.length() - 1) |> ignore
      }
      if i == path.length() - 1 && !normalized.is_empty() {
        normalized.push(b"")
      }
    } else if part == b"." {
      if i == path.length() - 1 && !normalized.is_empty() {
        normalized.push(b"")
      }
    } else {
      normalized.push(part)
    }
  }
  let path = normalized
  let query = match query_text {
    None => []
    Some(query) =>
      match split_uri_segments(query, "&") {
        Ok(value) => value
        Err(error) => return Err(error)
      }
  }
  if path.length() + query.length() + 2 > limits.max_options {
    return Err(Capacity("URI produces too many options"))
  }
  Ok({ host: host.to_lower(), port, path, query, })
}

///|
pub fn CoapUri::to_options(self : CoapUri) -> Array[CoapOption] {
  let options : Array[CoapOption] = [option_text(3, self.host)]
  if self.port != 5683 {
    options.push(option_uint(7, self.port.to_int64()).unwrap())
  }
  for value in self.path {
    options.push({ number: 11, value, })
  }
  for value in self.query {
    options.push({ number: 15, value, })
  }
  options
}

///|
pub fn CoapUri::to_string(self : CoapUri) -> String {
  let authority = if self.host.contains(":") {
    "[" + self.host + "]"
  } else {
    self.host
  }
  let mut text = "coap://" + authority
  if self.port != 5683 {
    text = text + ":" + self.port.to_string()
  }
  text = text + "/"
  for i = 0; i < self.path.length(); i = i + 1 {
    if i > 0 {
      text = text + "/"
    }
    text = text + percent_encode(self.path[i])
  }
  for i = 0; i < self.query.length(); i = i + 1 {
    text = text + (if i == 0 { "?" } else { "&" })
    text = text + percent_encode(self.query[i])
  }
  text
}

///|
pub fn Request::from_uri(
  verb : Method,
  text : String,
  limits : Limits,
) -> Result[(CoapUri, Request), Failure] {
  match CoapUri::parse(text, limits) {
    Err(error) => Err(error)
    Ok(uri) =>
      Ok(
        (
          uri,
          { verb, options: uri.to_options(), payload: b"", confirmable: true, },
        ),
      )
  }
}
