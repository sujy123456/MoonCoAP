///|
fn message_type_from_wire(value : Int) -> MessageType {
  match value {
    0 => Confirmable
    1 => NonConfirmable
    2 => Acknowledgement
    _ => Reset
  }
}

///|
fn slice_bytes(bytes : Bytes, start : Int, end : Int) -> Bytes {
  Bytes::makei(end - start, fn(i) { bytes[start + i] })
}

///|
fn read_extended(
  nibble : Int,
  bytes : Bytes,
  cursor : Int,
) -> Result[(Int, Int), Failure] {
  if nibble < 13 {
    return Ok((nibble, cursor))
  }
  if nibble == 13 {
    if cursor >= bytes.length() {
      return Err(Syntax(cursor, "truncated one-byte option extension"))
    }
    return Ok((13 + bytes[cursor].to_int(), cursor + 1))
  }
  if nibble == 14 {
    if cursor > bytes.length() - 2 {
      return Err(Syntax(cursor, "truncated two-byte option extension"))
    }
    let value = bytes[cursor].to_int() * 256 + bytes[cursor + 1].to_int()
    return Ok((269 + value, cursor + 2))
  }
  Err(Syntax(cursor - 1, "reserved option nibble"))
}

///|
fn validate_envelope(message : Message) -> Result[Unit, Failure] {
  if message.mid < 0 || message.mid > 65535 {
    return Err(Invalid("message identifier must be 0..65535"))
  }
  if message.code.value < 0 || message.code.value > 255 {
    return Err(Invalid("code must fit one byte"))
  }
  if message.token.length() > 8 {
    return Err(Invalid("Token must be 0..8 bytes"))
  }
  if message.code.value == 0 {
    if message.token.length() != 0 ||
      !message.options.is_empty() ||
      !message.payload.is_empty() {
      return Err(Invalid("Empty message must consist of the four-byte header"))
    }
    if message.msg_type == NonConfirmable {
      return Err(Invalid("NON Empty messages are not supported"))
    }
  } else {
    if message.msg_type == Reset {
      return Err(Invalid("Reset must be Empty"))
    }
    if message.msg_type == Acknowledgement && !message.code.is_response() {
      return Err(Invalid("non-empty ACK must carry a response"))
    }
    if !message.code.is_request() && !message.code.is_response() {
      return Err(Unsupported("reserved code class"))
    }
  }
  Ok(())
}

///|
pub fn decode(bytes : Bytes, limits : Limits) -> Result[Message, Failure] {
  match limits.validate() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if bytes.length() > limits.max_datagram {
    return Err(Capacity("datagram exceeds configured limit"))
  }
  if bytes.length() < 4 {
    return Err(Syntax(bytes.length(), "truncated header"))
  }
  let first = bytes[0].to_int()
  if first >> 6 != 1 {
    return Err(Syntax(0, "unsupported CoAP version"))
  }
  let token_length = first & 15
  if token_length > 8 {
    return Err(Syntax(0, "reserved Token length"))
  }
  if bytes.length() - 4 < token_length {
    return Err(Syntax(4, "truncated Token"))
  }
  let message = Message::new(
    message_type_from_wire((first >> 4) & 3),
    { value: bytes[1].to_int(), },
    bytes[2].to_int() * 256 + bytes[3].to_int(),
  )
  message.token = slice_bytes(bytes, 4, 4 + token_length)
  let mut cursor = 4 + token_length
  let mut option_number = 0
  let mut option_bytes = 0
  while cursor < bytes.length() {
    let header = bytes[cursor].to_int()
    if header == 255 {
      cursor = cursor + 1
      if cursor == bytes.length() {
        return Err(Syntax(cursor - 1, "payload marker without payload"))
      }
      if bytes.length() - cursor > limits.max_payload {
        return Err(Capacity("payload exceeds configured limit"))
      }
      message.payload = slice_bytes(bytes, cursor, bytes.length())
      cursor = bytes.length()
      break
    }
    if message.options.length() >= limits.max_options {
      return Err(Capacity("too many options"))
    }
    cursor = cursor + 1
    let (delta, next) = match read_extended(header >> 4, bytes, cursor) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    cursor = next
    let (length, next) = match read_extended(header & 15, bytes, cursor) {
      Ok(value) => value
      Err(error) => return Err(error)
    }
    cursor = next
    if delta > 65535 - option_number {
      return Err(Syntax(cursor, "option number exceeds 65535"))
    }
    option_number = option_number + delta
    if length > bytes.length() - cursor {
      return Err(Syntax(cursor, "truncated option value"))
    }
    if length > limits.max_option_bytes - option_bytes {
      return Err(Capacity("option values exceed configured limit"))
    }
    option_bytes = option_bytes + length
    message.options.push({
      number: option_number,
      value: slice_bytes(bytes, cursor, cursor + length),
    })
    cursor = cursor + length
  }
  match validate_envelope(message) {
    Err(error) => Err(error)
    Ok(_) => Ok(message)
  }
}
