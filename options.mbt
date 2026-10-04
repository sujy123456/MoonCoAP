///|
pub(all) enum OptionKind {
  Opaque
  Unsigned
  Text
  Flag
} derive(Eq, Debug)

///|
pub(all) struct OptionSpec {
  number : Int
  name : String
  kind : OptionKind
  min_length : Int
  max_length : Int
  repeatable : Bool
  request_only : Bool
  response_only : Bool
} derive(Eq, Debug)

///|
pub extend OptionKind with Eq::{equal, not_equal}

///|
pub extend OptionKind with @debug.Debug::{to_repr}

///|
pub extend OptionSpec with Eq::{equal, not_equal}

///|
pub extend OptionSpec with @debug.Debug::{to_repr}

///|
fn option_spec(
  number : Int,
  name : String,
  kind : OptionKind,
  min_length : Int,
  max_length : Int,
  repeatable : Bool,
  request_only : Bool,
  response_only : Bool,
) -> OptionSpec {
  {
    number,
    name,
    kind,
    min_length,
    max_length,
    repeatable,
    request_only,
    response_only,
  }
}

///|
pub fn standard_option(number : Int) -> OptionSpec? {
  match number {
    1 => Some(option_spec(1, "If-Match", Opaque, 0, 8, true, true, false))
    3 => Some(option_spec(3, "Uri-Host", Text, 1, 255, false, true, false))
    4 => Some(option_spec(4, "ETag", Opaque, 1, 8, true, false, false))
    5 => Some(option_spec(5, "If-None-Match", Flag, 0, 0, false, true, false))
    7 => Some(option_spec(7, "Uri-Port", Unsigned, 0, 2, false, true, false))
    8 => Some(option_spec(8, "Location-Path", Text, 0, 255, true, false, true))
    11 => Some(option_spec(11, "Uri-Path", Text, 0, 255, true, true, false))
    12 =>
      Some(
        option_spec(12, "Content-Format", Unsigned, 0, 2, false, false, false),
      )
    14 => Some(option_spec(14, "Max-Age", Unsigned, 0, 4, false, false, true))
    15 => Some(option_spec(15, "Uri-Query", Text, 0, 255, true, true, false))
    17 => Some(option_spec(17, "Accept", Unsigned, 0, 2, false, true, false))
    20 =>
      Some(option_spec(20, "Location-Query", Text, 0, 255, true, false, true))
    35 => Some(option_spec(35, "Proxy-Uri", Text, 1, 1034, false, true, false))
    39 =>
      Some(option_spec(39, "Proxy-Scheme", Text, 1, 255, false, true, false))
    60 => Some(option_spec(60, "Size1", Unsigned, 0, 4, false, true, false))
    _ => None
  }
}

///|
pub fn option_is_critical(number : Int) -> Bool {
  (number & 1) != 0
}

///|
pub fn option_is_unsafe(number : Int) -> Bool {
  (number & 2) != 0
}

///|
pub fn option_is_cache_key(number : Int) -> Bool {
  (number & 30) != 28
}

///|
pub fn option_uint(number : Int, value : Int64) -> Result[CoapOption, Failure] {
  if value < 0L || value > 4294967295L {
    return Err(Invalid("option integer must fit unsigned 32 bits"))
  }
  let mut remaining = value
  let reverse : Array[Byte] = []
  while remaining > 0L {
    reverse.push((remaining & 255L).to_int().to_byte())
    remaining = remaining >> 8
  }
  let bytes = Bytes::makei(reverse.length(), fn(i) {
    reverse[reverse.length() - 1 - i]
  })
  Ok({ number, value: bytes, })
}

///|
pub fn option_to_uint(option : CoapOption) -> Result[Int64, Failure] {
  if option.value.length() > 4 {
    return Err(Invalid("option integer is longer than four bytes"))
  }
  let mut value = 0L
  for byte in option.value {
    value = value * 256L + byte.to_int().to_int64()
  }
  Ok(value)
}

///|
pub fn option_text(number : Int, text : String) -> CoapOption {
  { number, value: @utf8.encode(text), }
}

///|
pub fn option_to_text(option : CoapOption) -> Result[String, Failure] {
  decode_utf8(option.value)
}

///|
pub fn validate_options(
  message : Message,
  supported_critical : Array[Int],
) -> Result[Unit, Failure] {
  let seen : Array[Int] = []
  for option in message.options {
    if option.number < 0 || option.number > 65535 {
      return Err(Invalid("option number out of range"))
    }
    match standard_option(option.number) {
      None =>
        if option_is_critical(option.number) &&
          !supported_critical.contains(option.number) {
          return Err(Unsupported("unknown critical option"))
        }
      Some(spec) => {
        if option.value.length() < spec.min_length ||
          option.value.length() > spec.max_length {
          return Err(Invalid("invalid length for " + spec.name))
        }
        if !spec.repeatable && seen.contains(option.number) {
          return Err(Invalid("duplicate " + spec.name))
        }
        if spec.request_only && !message.code.is_request() {
          return Err(Invalid(spec.name + " is request-only"))
        }
        if spec.response_only && !message.code.is_response() {
          return Err(Invalid(spec.name + " is response-only"))
        }
        match spec.kind {
          Text =>
            match option_to_text(option) {
              Err(error) => return Err(error)
              Ok(text) =>
                for character in text.iter() {
                  if character.to_int() < 32 || character.to_int() == 127 {
                    return Err(Invalid("control character in " + spec.name))
                  }
                }
            }
          Unsigned =>
            match option_to_uint(option) {
              Err(error) => return Err(error)
              Ok(_) => ()
            }
          Opaque | Flag => ()
        }
        seen.push(option.number)
      }
    }
  }
  if seen.contains(1) && seen.contains(5) {
    return Err(Invalid("If-Match and If-None-Match are mutually exclusive"))
  }
  if seen.contains(35) {
    if seen.contains(3) ||
      seen.contains(7) ||
      seen.contains(11) ||
      seen.contains(15) ||
      seen.contains(39) {
      return Err(Invalid("Proxy-Uri conflicts with URI options"))
    }
    return Err(Unsupported("proxying is outside this profile"))
  }
  if seen.contains(39) {
    return Err(Unsupported("proxying is outside this profile"))
  }
  Ok(())
}

///|
pub fn message_uint(
  message : Message,
  number : Int,
  default_value : Int64,
) -> Result[Int64, Failure] {
  match message.first_option(number) {
    None => Ok(default_value)
    Some(value) => option_to_uint({ number, value, })
  }
}

///|
pub fn request_path(message : Message) -> Result[String, Failure] {
  let parts = message.option_values(11)
  let mut path = ""
  for part in parts {
    match decode_utf8(part) {
      Ok(value) => path = path + "/" + value
      Err(error) => return Err(error)
    }
  }
  if path == "" {
    Ok("/")
  } else {
    Ok(path)
  }
}

///|
pub fn request_queries(message : Message) -> Result[Array[String], Failure] {
  let result : Array[String] = []
  for part in message.option_values(15) {
    match decode_utf8(part) {
      Ok(value) => result.push(value)
      Err(error) => return Err(error)
    }
  }
  Ok(result)
}
