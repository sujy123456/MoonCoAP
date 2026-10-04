///|
fn extended_nibble(value : Int) -> Int {
  if value < 13 {
    value
  } else if value < 269 {
    13
  } else {
    14
  }
}

///|
fn append_extension(output : Array[Byte], value : Int) -> Unit {
  if value >= 269 {
    let extension = value - 269
    output.push((extension >> 8).to_byte())
    output.push((extension & 255).to_byte())
  } else if value >= 13 {
    output.push((value - 13).to_byte())
  }
}

///|
fn ordered_options(options : Array[CoapOption]) -> Array[CoapOption] {
  let result = options.copy()
  for i = 1; i < result.length(); i = i + 1 {
    let current = result[i]
    let mut position = i
    while position > 0 && result[position - 1].number > current.number {
      result[position] = result[position - 1]
      position = position - 1
    }
    result[position] = current
  }
  result
}

///|
pub fn encode(message : Message, limits : Limits) -> Result[Bytes, Failure] {
  match limits.validate() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match validate_envelope(message) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if message.options.length() > limits.max_options {
    return Err(Capacity("too many options"))
  }
  if message.payload.length() > limits.max_payload {
    return Err(Capacity("payload exceeds configured limit"))
  }
  let output : Array[Byte] = [
    (64 + message.msg_type.wire() * 16 + message.token.length()).to_byte(),
    message.code.value.to_byte(),
    (message.mid >> 8).to_byte(),
    (message.mid & 255).to_byte(),
  ]
  for byte in message.token {
    output.push(byte)
  }
  let mut previous_number = 0
  let mut option_bytes = 0
  for option in ordered_options(message.options) {
    if option.number < 0 || option.number > 65535 {
      return Err(Invalid("option number must be 0..65535"))
    }
    if option.value.length() > limits.max_option_bytes - option_bytes {
      return Err(Capacity("option values exceed configured limit"))
    }
    option_bytes = option_bytes + option.value.length()
    let delta = option.number - previous_number
    let length = option.value.length()
    output.push(
      (extended_nibble(delta) * 16 + extended_nibble(length)).to_byte(),
    )
    append_extension(output, delta)
    append_extension(output, length)
    if output.length() > limits.max_datagram - length {
      return Err(Capacity("encoded options exceed datagram limit"))
    }
    for byte in option.value {
      output.push(byte)
    }
    previous_number = option.number
  }
  if !message.payload.is_empty() {
    if output.length() >= limits.max_datagram - message.payload.length() {
      return Err(Capacity("encoded payload exceeds datagram limit"))
    }
    output.push(b'\xff')
    for byte in message.payload {
      output.push(byte)
    }
  }
  if output.length() > limits.max_datagram {
    return Err(Capacity("encoded header or Token exceeds datagram limit"))
  }
  Ok(Bytes::from_array(output))
}

///|
pub fn encoded_size(message : Message, limits : Limits) -> Result[Int, Failure] {
  match encode(message, limits) {
    Ok(bytes) => Ok(bytes.length())
    Err(error) => Err(error)
  }
}
