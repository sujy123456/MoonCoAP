///|
pub(all) enum Failure {
  Syntax(Int, String)
  Invalid(String)
  Capacity(String)
  Unsupported(String)
  Clock(String)
  NotFound(String)
  Conflict(String)
  Transport(String)
  TimedOut
  ResetByPeer
} derive(Eq, Debug)

///|
pub(all) enum MessageType {
  Confirmable
  NonConfirmable
  Acknowledgement
  Reset
} derive(Eq, Debug)

///|
pub fn MessageType::wire(self : MessageType) -> Int {
  match self {
    Confirmable => 0
    NonConfirmable => 1
    Acknowledgement => 2
    Reset => 3
  }
}

///|
pub(all) enum Method {
  Get
  Post
  Put
  Delete
} derive(Eq, Debug)

///|
pub fn Method::wire(self : Method) -> Int {
  match self {
    Get => 1
    Post => 2
    Put => 3
    Delete => 4
  }
}

///|
pub fn Method::name(self : Method) -> String {
  match self {
    Get => "GET"
    Post => "POST"
    Put => "PUT"
    Delete => "DELETE"
  }
}

///|
pub(all) struct Code {
  value : Int
} derive(Eq, Debug)

///|
pub fn Code::request(verb : Method) -> Code {
  { value: verb.wire(), }
}

///|
pub fn Code::response(class : Int, detail : Int) -> Result[Code, Failure] {
  if (class != 2 && class != 4 && class != 5) || detail < 0 || detail > 31 {
    return Err(Invalid("response class must be 2, 4 or 5 and detail 0..31"))
  }
  Ok({ value: class * 32 + detail, })
}

///|
pub fn Code::class(self : Code) -> Int {
  self.value >> 5
}

///|
pub fn Code::detail(self : Code) -> Int {
  self.value & 31
}

///|
pub fn Code::is_request(self : Code) -> Bool {
  self.value > 0 && self.value < 32
}

///|
pub fn Code::is_response(self : Code) -> Bool {
  self.class() == 2 || self.class() == 4 || self.class() == 5
}

///|
pub fn Code::is_success(self : Code) -> Bool {
  self.class() == 2
}

///|
pub fn Code::verb(self : Code) -> Method? {
  match self.value {
    1 => Some(Get)
    2 => Some(Post)
    3 => Some(Put)
    4 => Some(Delete)
    _ => None
  }
}

///|
pub fn Code::description(self : Code) -> String {
  match self.value {
    0 => "Empty"
    1 => "GET"
    2 => "POST"
    3 => "PUT"
    4 => "DELETE"
    65 => "Created"
    66 => "Deleted"
    67 => "Valid"
    68 => "Changed"
    69 => "Content"
    128 => "Bad Request"
    129 => "Unauthorized"
    130 => "Bad Option"
    131 => "Forbidden"
    132 => "Not Found"
    133 => "Method Not Allowed"
    134 => "Not Acceptable"
    140 => "Precondition Failed"
    141 => "Request Entity Too Large"
    143 => "Unsupported Content-Format"
    160 => "Internal Server Error"
    161 => "Not Implemented"
    162 => "Bad Gateway"
    163 => "Service Unavailable"
    164 => "Gateway Timeout"
    165 => "Proxying Not Supported"
    _ => "Unassigned"
  }
}

///|
pub(all) struct CoapOption {
  number : Int
  value : Bytes
} derive(Eq, Debug)

///|
pub(all) struct Message {
  mut msg_type : MessageType
  mut code : Code
  mut mid : Int
  mut token : Bytes
  mut options : Array[CoapOption]
  mut payload : Bytes
} derive(Eq, Debug)

///|
pub fn Message::new(msg_type : MessageType, code : Code, mid : Int) -> Message {
  { msg_type, code, mid, token: b"", options: [], payload: b"", }
}

///|
pub fn Message::copy(self : Message) -> Message {
  {
    msg_type: self.msg_type,
    code: self.code,
    mid: self.mid,
    token: self.token,
    options: self.options.map(fn(o) { { number: o.number, value: o.value, } }),
    payload: self.payload,
  }
}

///|
pub fn Message::option_values(self : Message, number : Int) -> Array[Bytes] {
  self.options.filter_map(fn(o) {
    if o.number == number {
      Some(o.value)
    } else {
      None
    }
  })
}

///|
pub fn Message::first_option(self : Message, number : Int) -> Bytes? {
  for option in self.options {
    if option.number == number {
      return Some(option.value)
    }
  }
  None
}

///|
pub fn Message::replace_option(
  self : Message,
  number : Int,
  value : Bytes,
) -> Unit {
  self.options = self.options.filter(fn(o) { o.number != number })
  self.options.push({ number, value, })
}

///|
pub fn Message::remove_option(self : Message, number : Int) -> Unit {
  self.options = self.options.filter(fn(o) { o.number != number })
}

///|
pub(all) struct Limits {
  max_datagram : Int
  max_options : Int
  max_option_bytes : Int
  max_payload : Int
  max_uri_bytes : Int
  max_links : Int
  max_link_attributes : Int
} derive(Eq, Debug)

///|
pub fn Limits::default() -> Limits {
  {
    max_datagram: 1152,
    max_options: 32,
    max_option_bytes: 512,
    max_payload: 1024,
    max_uri_bytes: 1024,
    max_links: 64,
    max_link_attributes: 16,
  }
}

///|
pub fn Limits::validate(self : Limits) -> Result[Unit, Failure] {
  if self.max_datagram < 4 || self.max_datagram > 65535 {
    return Err(Invalid("max_datagram must be 4..65535"))
  }
  if self.max_options < 0 || self.max_options > 1024 {
    return Err(Invalid("max_options must be 0..1024"))
  }
  if self.max_option_bytes < 0 || self.max_option_bytes > 65535 {
    return Err(Invalid("invalid option byte limit"))
  }
  if self.max_payload < 0 || self.max_payload > 65535 {
    return Err(Invalid("invalid payload limit"))
  }
  if self.max_uri_bytes < 1 || self.max_uri_bytes > 65535 {
    return Err(Invalid("invalid URI byte limit"))
  }
  if self.max_links < 1 || self.max_links > 4096 {
    return Err(Invalid("invalid discovery link limit"))
  }
  if self.max_link_attributes < 1 || self.max_link_attributes > 128 {
    return Err(Invalid("invalid link attribute limit"))
  }
  Ok(())
}

///|
pub(all) struct Request {
  verb : Method
  options : Array[CoapOption]
  payload : Bytes
  confirmable : Bool
} derive(Eq, Debug)

///|
pub fn Request::new(verb : Method) -> Request {
  { verb, options: [], payload: b"", confirmable: true, }
}

///|
pub(all) struct Response {
  code : Code
  options : Array[CoapOption]
  payload : Bytes
} derive(Eq, Debug)

///|
pub fn Response::content(payload : Bytes) -> Response {
  { code: { value: 69, }, options: [], payload, }
}

///|
pub fn Response::error(code : Int) -> Response {
  { code: { value: code, }, options: [], payload: b"", }
}

///|
pub fn bytes_to_hex(bytes : Bytes) -> String {
  let digits = "0123456789abcdef"
  let result : Array[Char] = []
  for byte in bytes {
    let value = byte.to_int()
    result.push(digits.get_char(value >> 4).unwrap())
    result.push(digits.get_char(value & 15).unwrap())
  }
  String::from_array(result)
}

///|
pub fn hex_to_bytes(text : String) -> Result[Bytes, Failure] {
  if text.length() % 2 != 0 {
    return Err(Invalid("hex input has odd length"))
  }
  let output : Array[Byte] = []
  for i = 0; i < text.length(); i = i + 2 {
    let high = hex_digit(text[i].to_int())
    let low = hex_digit(text[i + 1].to_int())
    if high < 0 || low < 0 {
      return Err(Syntax(i, "invalid hexadecimal digit"))
    }
    output.push((high * 16 + low).to_byte())
  }
  Ok(Bytes::from_array(output))
}

///|
fn hex_digit(value : Int) -> Int {
  if value >= 48 && value <= 57 {
    value - 48
  } else if value >= 65 && value <= 70 {
    value - 55
  } else if value >= 97 && value <= 102 {
    value - 87
  } else {
    -1
  }
}

///|
pub fn decode_utf8(bytes : Bytes) -> Result[String, Failure] {
  Ok(@utf8.decode(bytes[:])) catch {
    _ => Err(Syntax(0, "invalid UTF-8"))
  }
}
