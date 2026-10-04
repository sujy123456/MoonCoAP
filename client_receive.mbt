///|
struct ReplyReceipt {
  peer : String
  mid : Int
  token : Bytes
  acknowledgement : Bytes
  expires_at : Int64
}

///|
fn Endpoint::client_by_token(
  self : Endpoint,
  peer : String,
  token : Bytes,
) -> Int? {
  for index = 0; index < self.clients.length(); index = index + 1 {
    let exchange = self.clients[index]
    if exchange.peer == peer &&
      exchange.message.token == token &&
      (exchange.phase == Sending || exchange.phase == WaitingResponse) {
      return Some(index)
    }
  }
  None
}

///|
fn Endpoint::client_by_mid(self : Endpoint, peer : String, mid : Int) -> Int? {
  for index = 0; index < self.clients.length(); index = index + 1 {
    let exchange = self.clients[index]
    if exchange.peer == peer &&
      exchange.message.mid == mid &&
      exchange.message.msg_type == Confirmable &&
      (exchange.phase == Sending || exchange.phase == WaitingResponse) {
      return Some(index)
    }
  }
  None
}

///|
fn Endpoint::finish_response(
  self : Endpoint,
  index : Int,
  message : Message,
  now : Int64,
) -> Unit {
  let exchange = self.clients.remove(index)
  self.outbox.push(ResponseReceived(exchange.id, message.copy()))
  self.promote_outbound(now)
}

///|
fn Endpoint::reject_response(
  self : Endpoint,
  index : Int,
  error : Failure,
  now : Int64,
) -> Unit {
  let exchange = self.clients.remove(index)
  self.outbox.push(Failed(exchange.id, error))
  self.promote_outbound(now)
}

///|
pub fn empty_control(msg_type : MessageType, mid : Int) -> Message {
  Message::new(msg_type, { value: 0, }, mid)
}

///|
fn Endpoint::send_control(
  self : Endpoint,
  peer : String,
  msg_type : MessageType,
  mid : Int,
) -> Unit {
  let packet = encode(empty_control(msg_type, mid), self.config.limits).unwrap()
  self.outbox.push(SendDatagram(peer, packet))
}

///|
pub fn Endpoint::response_receipt_count(self : Endpoint) -> Int {
  self.reply_receipts.length()
}

///|
pub fn Endpoint::receive_response(
  self : Endpoint,
  peer : String,
  packet : Bytes,
  now : Int64,
) -> Result[Unit, Failure] {
  match self.observe_time(now) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match validate_peer(peer) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match
    self.ensure_actions(self.config.max_exchanges + self.config.max_dedup + 4) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let message = match self.decode_incoming(peer, packet) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  self.expire_clients(now)
  self.promote_outbound(now)
  self.reply_receipts = self.reply_receipts.filter(fn(receipt) {
    receipt.expires_at > now
  })
  if message.msg_type == Reset {
    match self.client_by_mid(peer, message.mid) {
      None => ()
      Some(index) => self.reject_response(index, ResetByPeer, now)
    }
    return Ok(())
  }
  if message.msg_type == Acknowledgement {
    let index = match self.client_by_mid(peer, message.mid) {
      None => return Ok(())
      Some(value) => value
    }
    let exchange = self.clients[index]
    if message.code.value == 0 {
      exchange.phase = WaitingResponse
      exchange.next_retry = None
      self.promote_outbound(now)
      return Ok(())
    }
    if message.token != exchange.message.token {
      return Ok(())
    }
    match received_options(message, []) {
      Err(error) => self.reject_response(index, error, now)
      Ok(options) => {
        message.options = options
        self.finish_response(index, message, now)
      }
    }
    return Ok(())
  }
  if message.code.value == 0 && message.msg_type == Confirmable {
    self.send_control(peer, Reset, message.mid)
    return Ok(())
  }
  if !message.code.is_response() {
    return Err(
      Invalid("receive_response expects a response or control message"),
    )
  }
  if message.msg_type == Confirmable {
    for receipt in self.reply_receipts {
      if receipt.peer == peer && receipt.mid == message.mid {
        if receipt.token != message.token {
          return Err(Conflict("response MID reused with a different Token"))
        }
        self.outbox.push(SendDatagram(peer, receipt.acknowledgement))
        return Ok(())
      }
    }
  }
  let index = match self.client_by_token(peer, message.token) {
    None => {
      if message.msg_type == Confirmable {
        self.send_control(peer, Reset, message.mid)
      }
      return Ok(())
    }
    Some(value) => value
  }
  match received_options(message, []) {
    Err(error) => {
      if message.msg_type == Confirmable {
        self.send_control(peer, Reset, message.mid)
        self.reject_response(index, error, now)
      }
      return Ok(())
    }
    Ok(options) => message.options = options
  }
  if message.msg_type == Confirmable {
    if self.reply_receipts.length() >= self.config.max_dedup {
      return Err(Capacity("response receipt cache is full"))
    }
    let acknowledgement = encode(
      empty_control(Acknowledgement, message.mid),
      self.config.limits,
    ).unwrap()
    self.reply_receipts.push({
      peer,
      mid: message.mid,
      token: message.token,
      acknowledgement,
      expires_at: now + self.config.exchange_lifetime_ms,
    })
    self.outbox.push(SendDatagram(peer, acknowledgement))
  }
  self.finish_response(index, message, now)
  Ok(())
}
