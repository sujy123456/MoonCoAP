///|
priv struct ServerTransmission {
  message : Message
  mut wire : Bytes
  mut phase : ExchangePhase
  mut last_sent_at : Int64
  mut deadline : Int64
  mut next_retry : Int64?
  mut interval : Int64
  mut retransmissions : Int
}

///|
struct ServerExchange {
  incoming : IncomingRequest
  original_packet : Bytes
  expires_at : Int64
  mut initial_reply : Bytes?
  mut answered : Bool
  mut transmission : ServerTransmission?
}

///|
pub(all) struct ServerView {
  id : Int
  peer : String
  request_mid : Int
  token : Bytes
  expires_at : Int64
  acknowledged : Bool
  answered : Bool
  response_mid : Int?
  response_phase : ExchangePhase?
  response_deadline : Int64?
  last_sent_at : Int64?
  retransmissions : Int
} derive(Eq, Debug)

///|
pub extend ServerView with Eq::{equal, not_equal}

///|
pub extend ServerView with @debug.Debug::{to_repr}

///|
pub fn Endpoint::server_records(self : Endpoint) -> Array[ServerView] {
  self.servers.map(fn(exchange) {
    let (mid, phase, deadline, sent, attempts) = match exchange.transmission {
      None => (None, None, None, None, 0)
      Some(response) =>
        (
          Some(response.message.mid),
          Some(response.phase),
          Some(response.deadline),
          Some(response.last_sent_at),
          response.retransmissions,
        )
    }
    {
      id: exchange.incoming.id,
      peer: exchange.incoming.peer,
      request_mid: exchange.incoming.message.mid,
      token: exchange.incoming.message.token,
      expires_at: exchange.expires_at,
      acknowledged: exchange.initial_reply is Some(_),
      answered: exchange.answered,
      response_mid: mid,
      response_phase: phase,
      response_deadline: deadline,
      last_sent_at: sent,
      retransmissions: attempts,
    }
  })
}

///|
fn Endpoint::server_by_id(self : Endpoint, id : Int) -> ServerExchange? {
  for exchange in self.servers {
    if exchange.incoming.id == id {
      return Some(exchange)
    }
  }
  None
}

///|
pub fn Endpoint::acknowledge(
  self : Endpoint,
  id : Int,
  now : Int64,
) -> Result[Unit, Failure] {
  match self.observe_time(now) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match self.ensure_actions(1) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let exchange = match self.server_by_id(id) {
    None => return Err(NotFound("unknown server request"))
    Some(value) => value
  }
  if exchange.expires_at <= now {
    return Err(TimedOut)
  }
  if exchange.answered {
    return Err(Conflict("request already answered"))
  }
  if exchange.incoming.message.msg_type != Confirmable {
    return Err(Invalid("only CON requests can receive Empty ACK"))
  }
  match exchange.initial_reply {
    Some(_) => return Ok(())
    None => ()
  }
  let acknowledgement = encode(
    empty_control(Acknowledgement, exchange.incoming.message.mid),
    self.config.limits,
  ).unwrap()
  exchange.initial_reply = Some(acknowledgement)
  self.outbox.push(SendDatagram(exchange.incoming.peer, acknowledgement))
  Ok(())
}

///|
pub fn Endpoint::receive_request(
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
  match self.ensure_actions(self.config.max_dedup + 3) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let message = match decode(packet, self.config.limits) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if !message.code.is_request() {
    return Err(Invalid("receive_request expects a request"))
  }
  self.expire_server_records(now)
  for exchange in self.servers {
    if exchange.incoming.peer == peer &&
      exchange.incoming.message.mid == message.mid &&
      exchange.expires_at > now {
      if exchange.original_packet != packet {
        return Err(Conflict("request MID reused before exchange expiry"))
      }
      if message.msg_type == Confirmable {
        match exchange.initial_reply {
          Some(reply) => self.outbox.push(SendDatagram(peer, reply))
          None => {
            let reply = encode(
              empty_control(Acknowledgement, message.mid),
              self.config.limits,
            ).unwrap()
            exchange.initial_reply = Some(reply)
            self.outbox.push(SendDatagram(peer, reply))
          }
        }
      }
      return Ok(())
    }
  }
  let option_error = match validate_options(message, []) {
    Ok(_) => None
    Err(error) => Some(error)
  }
  if option_error is Some(_) && message.msg_type == NonConfirmable {
    return Ok(())
  }
  if self.servers.length() >= self.config.max_dedup {
    return Err(Capacity("request cache full; live records cannot be evicted"))
  }
  let peers = self.active_peers()
  if !peers.contains(peer) && peers.length() >= self.config.max_peers {
    return Err(Capacity("active peer count is full"))
  }
  if self.next_id == 2147483647 {
    return Err(Capacity("request identifier space exhausted"))
  }
  let id = self.next_id
  self.next_id = self.next_id + 1
  let incoming : IncomingRequest = {
    id,
    peer,
    message: message.copy(),
    received_at: now,
  }
  self.servers.push({
    incoming,
    original_packet: packet,
    expires_at: now +
    (if message.msg_type == Confirmable {
      self.config.exchange_lifetime_ms
    } else {
      self.config.non_lifetime_ms
    }),
    initial_reply: None,
    answered: false,
    transmission: None,
  })
  match option_error {
    Some(_) => {
      let code = if message.first_option(35) is Some(_) ||
        message.first_option(39) is Some(_) {
        165
      } else {
        130
      }
      return self.respond(id, Response::error(code), now, 0)
    }
    None => ()
  }
  if message.code.verb() is None {
    return self.respond(id, Response::error(133), now, 0)
  }
  self.outbox.push(
    RequestReceived({
      id: incoming.id,
      peer: incoming.peer,
      message: incoming.message.copy(),
      received_at: incoming.received_at,
    }),
  )
  Ok(())
}

///|
fn Endpoint::start_server_response(
  self : Endpoint,
  exchange : ServerExchange,
  now : Int64,
) -> Result[Unit, Failure] {
  let response = match exchange.transmission {
    None => return Err(Invalid("server response is absent"))
    Some(value) => value
  }
  response.message.mid = match
    self.allocator.allocate_mid(exchange.incoming.peer, now) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  response.wire = match encode(response.message, self.config.limits) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  response.phase = Sending
  response.last_sent_at = now
  let maximum_wait = response.interval *
    ((1L << (self.config.max_retransmit + 1)) - 1L)
  if now + maximum_wait < response.deadline {
    response.deadline = now + maximum_wait
  }
  response.next_retry = Some(now + response.interval)
  self.outbox.push(SendDatagram(exchange.incoming.peer, response.wire))
  Ok(())
}

///|
pub fn Endpoint::respond(
  self : Endpoint,
  id : Int,
  response : Response,
  now : Int64,
  random_sample : Int,
) -> Result[Unit, Failure] {
  match self.observe_time(now) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match
    self.ensure_actions(self.config.max_exchanges + self.config.max_dedup + 4) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let exchange = match self.server_by_id(id) {
    None => return Err(NotFound("unknown server request"))
    Some(value) => value
  }
  if exchange.expires_at <= now {
    return Err(TimedOut)
  }
  if exchange.answered {
    return Err(Conflict("request already answered"))
  }
  if !response.code.is_response() {
    return Err(Invalid("server response must have a response code"))
  }
  let request = exchange.incoming.message
  let piggyback = request.msg_type == Confirmable &&
    exchange.initial_reply is None
  let msg_type = if piggyback {
    Acknowledgement
  } else if request.msg_type == NonConfirmable {
    NonConfirmable
  } else {
    Confirmable
  }
  let outgoing = Message::new(msg_type, response.code, request.mid)
  outgoing.token = request.token
  outgoing.options = response.options.copy()
  outgoing.payload = response.payload
  match validate_options(outgoing, []) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let validated_wire = match encode(outgoing, self.config.limits) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if piggyback {
    exchange.initial_reply = Some(validated_wire)
    exchange.answered = true
    self.outbox.push(SendDatagram(exchange.incoming.peer, validated_wire))
    return Ok(())
  }
  if msg_type == NonConfirmable {
    outgoing.mid = match
      self.allocator.allocate_mid(exchange.incoming.peer, now) {
      Err(error) => return Err(error)
      Ok(value) => value
    }
    let wire = encode(outgoing, self.config.limits).unwrap()
    exchange.initial_reply = Some(wire)
    exchange.answered = true
    self.outbox.push(SendDatagram(exchange.incoming.peer, wire))
    return Ok(())
  }
  let interval = match retry_interval(self.config, random_sample) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  exchange.transmission = Some({
    message: outgoing,
    wire: b"",
    phase: Queued,
    last_sent_at: now,
    deadline: now + self.config.exchange_lifetime_ms,
    next_retry: None,
    interval,
    retransmissions: 0,
  })
  exchange.answered = true
  self.promote_clients(now)
  Ok(())
}

///|
fn Endpoint::poll_server_responses(self : Endpoint, now : Int64) -> Unit {
  for exchange in self.servers {
    match exchange.transmission {
      None => ()
      Some(response) => {
        if response.phase == Finished {
          continue
        }
        if now >= response.deadline {
          response.phase = Finished
          response.next_retry = None
          self.outbox.push(Failed(exchange.incoming.id, TimedOut))
          continue
        }
        if response.phase == Queued {
          continue
        }
        match response.next_retry {
          None => ()
          Some(deadline) =>
            if now >= deadline {
              if response.retransmissions >= self.config.max_retransmit {
                response.phase = Finished
                response.next_retry = None
                self.outbox.push(Failed(exchange.incoming.id, TimedOut))
              } else {
                response.retransmissions = response.retransmissions + 1
                response.last_sent_at = now
                response.interval = response.interval * 2L
                response.next_retry = Some(now + response.interval)
                self.outbox.push(
                  SendDatagram(exchange.incoming.peer, response.wire),
                )
              }
            }
        }
      }
    }
  }
}

///|
fn Endpoint::receive_server_control(
  self : Endpoint,
  peer : String,
  message : Message,
  now : Int64,
) -> Bool {
  if message.code.value != 0 {
    return false
  }
  for exchange in self.servers {
    match exchange.transmission {
      Some(response) =>
        if exchange.incoming.peer == peer &&
          response.message.mid == message.mid &&
          response.phase == Sending {
          response.phase = Finished
          response.next_retry = None
          if message.msg_type == Reset {
            self.outbox.push(Failed(exchange.incoming.id, ResetByPeer))
          }
          self.promote_clients(now)
          return true
        }
      None => ()
    }
  }
  false
}

///|
pub fn Endpoint::receive(
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
  let message = match decode(packet, self.config.limits) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  if message.code.is_request() {
    return self.receive_request(peer, packet, now)
  }
  if message.msg_type == Acknowledgement || message.msg_type == Reset {
    self.poll_server_responses(now)
    self.expire_server_records(now)
    if self.receive_server_control(peer, message, now) {
      return Ok(())
    }
  }
  self.receive_response(peer, packet, now)
}
