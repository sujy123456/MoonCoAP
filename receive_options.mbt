///|
pub fn received_options(
  message : Message,
  supported : Array[Int],
) -> Result[Array[CoapOption], Failure] {
  let accepted : Array[CoapOption] = []
  for option in message.options {
    let candidate = message.copy()
    candidate.options = accepted.copy()
    candidate.options.push(option)
    match validate_options(candidate, supported) {
      Ok(_) => accepted.push(option)
      Err(error) => if option_is_critical(option.number) { return Err(error) }
    }
  }
  Ok(accepted)
}

///|
fn Endpoint::decode_incoming(
  self : Endpoint,
  peer : String,
  packet : Bytes,
) -> Result[Message, Failure] {
  match decode(packet, self.config.limits) {
    Ok(message) => Ok(message)
    Err(error) => {
      if packet.length() >= 4 &&
        packet[0].to_int() >> 6 == 1 &&
        ((packet[0].to_int() >> 4) & 3) == 0 {
        self.send_control(
          peer,
          Reset,
          packet[2].to_int() * 256 + packet[3].to_int(),
        )
      }
      Err(error)
    }
  }
}
