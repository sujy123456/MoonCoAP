///|
pub(all) enum ExchangePhase {
  Queued
  Sending
  WaitingResponse
  Finished
} derive(Eq, Debug)

///|
pub extend ExchangePhase with Eq::{equal, not_equal}

///|
pub extend ExchangePhase with @debug.Debug::{to_repr}

///|
pub(all) struct IncomingRequest {
  id : Int
  peer : String
  message : Message
  received_at : Int64
} derive(Eq, Debug)

///|
pub extend IncomingRequest with Eq::{equal, not_equal}

///|
pub extend IncomingRequest with @debug.Debug::{to_repr}

///|
pub(all) enum Action {
  SendDatagram(String, Bytes)
  RequestReceived(IncomingRequest)
  ResponseReceived(Int, Message)
  Failed(Int, Failure)
  Cancelled(Int)
} derive(Eq, Debug)

///|
pub extend Action with Eq::{equal, not_equal}

///|
pub extend Action with @debug.Debug::{to_repr}

///|
pub(all) struct ExchangeView {
  id : Int
  peer : String
  mid : Int
  token : Bytes
  phase : ExchangePhase
  created_at : Int64
  last_sent_at : Int64
  deadline : Int64
  transmit_deadline : Int64
  next_retry : Int64?
  interval : Int64
  retransmissions : Int
} derive(Eq, Debug)

///|
pub extend ExchangeView with Eq::{equal, not_equal}

///|
pub extend ExchangeView with @debug.Debug::{to_repr}

///|
struct ClientExchange {
  id : Int
  peer : String
  message : Message
  mut wire : Bytes
  mut phase : ExchangePhase
  created_at : Int64
  mut last_sent_at : Int64
  mut deadline : Int64
  mut transmit_deadline : Int64
  mut retransmit_stop : Int64
  mut next_retry : Int64?
  mut interval : Int64
  mut retransmissions : Int
}

///|
pub struct Endpoint {
  config : Config
  allocator : Allocator
  mut last_now : Int64
  mut next_id : Int
  mut clients : Array[ClientExchange]
  mut reply_receipts : Array[ReplyReceipt]
  mut servers : Array[ServerExchange]
  mut outbox : Array[Action]
}

///|
pub fn Endpoint::new(config : Config) -> Result[Endpoint, Failure] {
  let allocator = match Allocator::new(config) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  Ok({
    config,
    allocator,
    last_now: 0L,
    next_id: 1,
    clients: [],
    reply_receipts: [],
    servers: [],
    outbox: [],
  })
}

///|
fn Endpoint::observe_time(
  self : Endpoint,
  now : Int64,
) -> Result[Unit, Failure] {
  if now < self.last_now {
    return Err(Clock("endpoint clock moved backwards"))
  }
  match deadline_after(now, self.config.exchange_lifetime_ms) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.last_now = now
  match self.allocator.collect(now) {
    Err(error) => Err(error)
    Ok(_) => Ok(())
  }
}

///|
fn Endpoint::ensure_actions(
  self : Endpoint,
  needed : Int,
) -> Result[Unit, Failure] {
  if needed < 0 || self.outbox.length() > self.config.max_actions - needed {
    Err(Capacity("drain endpoint actions before submitting more events"))
  } else {
    Ok(())
  }
}

///|
pub fn Endpoint::drain(self : Endpoint) -> Array[Action] {
  let result = self.outbox
  self.outbox = []
  result
}

///|
pub fn Endpoint::exchange_count(self : Endpoint) -> Int {
  self.clients.length()
}

///|
pub fn Endpoint::queued_count(self : Endpoint) -> Int {
  self.clients.filter(fn(exchange) { exchange.phase == Queued }).length()
}

///|
pub fn Endpoint::active_for_peer(self : Endpoint, peer : String) -> Int {
  let clients = self.clients
    .filter(fn(exchange) { exchange.peer == peer && exchange.phase == Sending })
    .length()
  let mut servers = 0
  for exchange in self.servers {
    match exchange.transmission {
      Some(response) =>
        if exchange.incoming.peer == peer && response.phase == Sending {
          servers = servers + 1
        }
      None => ()
    }
  }
  clients + servers
}

///|
pub fn Endpoint::active_peers(self : Endpoint) -> Array[String] {
  let result : Array[String] = []
  for exchange in self.clients {
    if !result.contains(exchange.peer) {
      result.push(exchange.peer)
    }
  }
  for exchange in self.servers {
    if !result.contains(exchange.incoming.peer) {
      result.push(exchange.incoming.peer)
    }
  }
  result
}

///|
pub fn Endpoint::exchanges(self : Endpoint) -> Array[ExchangeView] {
  self.clients.map(fn(exchange) {
    {
      id: exchange.id,
      peer: exchange.peer,
      mid: exchange.message.mid,
      token: exchange.message.token,
      phase: exchange.phase,
      created_at: exchange.created_at,
      last_sent_at: exchange.last_sent_at,
      deadline: exchange.deadline,
      transmit_deadline: exchange.transmit_deadline,
      next_retry: exchange.next_retry,
      interval: exchange.interval,
      retransmissions: exchange.retransmissions,
    }
  })
}

///|
fn Endpoint::start_client(
  self : Endpoint,
  exchange : ClientExchange,
  now : Int64,
) -> Result[Unit, Failure] {
  let mid = match self.allocator.allocate_mid(exchange.peer, now) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  exchange.message.mid = mid
  let wire = match encode(exchange.message, self.config.limits) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  exchange.wire = wire
  exchange.phase = Sending
  exchange.last_sent_at = now
  exchange.deadline = now + self.config.response_timeout_ms
  exchange.transmit_deadline = now +
    exchange.interval * ((1L << (self.config.max_retransmit + 1)) - 1L)
  exchange.retransmit_stop = now + self.config.max_transmit_span()
  exchange.next_retry = if exchange.message.msg_type == Confirmable {
    Some(now + exchange.interval)
  } else {
    None
  }
  self.outbox.push(SendDatagram(exchange.peer, exchange.wire))
  Ok(())
}

///|
fn Endpoint::promote_outbound(self : Endpoint, now : Int64) -> Unit {
  self.expire_clients(now)
  self.expire_server_transmissions(now)
  for _round = 0
      _round < self.config.max_exchanges + self.config.max_dedup
      _round = _round + 1 {
    let mut client_index : Int? = None
    let mut server_index : Int? = None
    let mut smallest_id = 2147483647
    for index = 0; index < self.clients.length(); index = index + 1 {
      let exchange = self.clients[index]
      if exchange.phase == Queued &&
        exchange.id < smallest_id &&
        self.active_for_peer(exchange.peer) < self.config.nstart {
        smallest_id = exchange.id
        client_index = Some(index)
        server_index = None
      }
    }
    for index = 0; index < self.servers.length(); index = index + 1 {
      let exchange = self.servers[index]
      match exchange.transmission {
        Some(response) =>
          if response.phase == Queued &&
            exchange.incoming.id < smallest_id &&
            self.active_for_peer(exchange.incoming.peer) < self.config.nstart {
            smallest_id = exchange.incoming.id
            server_index = Some(index)
            client_index = None
          }
        None => ()
      }
    }
    match (client_index, server_index) {
      (Some(index), _) => {
        let exchange = self.clients[index]
        match self.start_client(exchange, now) {
          Ok(_) => ()
          Err(error) => {
            exchange.phase = Finished
            self.outbox.push(Failed(exchange.id, error))
          }
        }
      }
      (_, Some(index)) => {
        let exchange = self.servers[index]
        match self.start_server_response(exchange, now) {
          Ok(_) => ()
          Err(error) => {
            match exchange.transmission {
              Some(response) => response.phase = Finished
              None => ()
            }
            self.outbox.push(Failed(exchange.incoming.id, error))
          }
        }
      }
      _ => break
    }
  }
  self.clients = self.clients.filter(fn(exchange) { exchange.phase != Finished })
}

///|
fn Endpoint::expire_server_records(self : Endpoint, now : Int64) -> Unit {
  for exchange in self.servers {
    if !exchange.answered && exchange.expires_at <= now {
      exchange.answered = true
      self.outbox.push(Failed(exchange.incoming.id, TimedOut))
    }
  }
  self.servers = self.servers.filter(fn(exchange) {
    if exchange.expires_at > now {
      true
    } else {
      match exchange.transmission {
        Some(response) => response.phase != Finished
        None => false
      }
    }
  })
}

///|
pub fn Endpoint::request(
  self : Endpoint,
  peer : String,
  request : Request,
  now : Int64,
  random_sample : Int,
) -> Result[Int, Failure] {
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
  self.expire_clients(now)
  self.expire_server_records(now)
  self.promote_outbound(now)
  if self.clients.length() >= self.config.max_exchanges {
    return Err(Capacity("client exchanges are full"))
  }
  let peers = self.active_peers()
  if !peers.contains(peer) && peers.length() >= self.config.max_peers {
    return Err(Capacity("active peer count is full"))
  }
  let queued = self.active_for_peer(peer) >= self.config.nstart
  if queued && self.queued_count() >= self.config.max_queue {
    return Err(Capacity("client waiting queue is full"))
  }
  if self.next_id == 2147483647 {
    return Err(Capacity("request identifier space exhausted"))
  }
  let interval = match retry_interval(self.config, random_sample) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  let message = Message::new(
    if request.confirmable {
      Confirmable
    } else {
      NonConfirmable
    },
    Code::request(request.verb),
    0,
  )
  message.options = request.options.copy()
  message.payload = request.payload
  message.token = match self.allocator.allocate_token() {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match validate_options(message, []) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match encode(message, self.config.limits) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  let id = self.next_id
  let exchange : ClientExchange = {
    id,
    peer,
    message,
    wire: b"",
    phase: Queued,
    created_at: now,
    last_sent_at: now,
    deadline: now + self.config.response_timeout_ms,
    transmit_deadline: now + self.config.exchange_lifetime_ms,
    retransmit_stop: now,
    next_retry: None,
    interval,
    retransmissions: 0,
  }
  if !queued {
    match self.start_client(exchange, now) {
      Err(error) => return Err(error)
      Ok(_) => ()
    }
  }
  self.next_id = self.next_id + 1
  self.clients.push(exchange)
  Ok(id)
}

///|
pub fn Endpoint::cancel(
  self : Endpoint,
  id : Int,
  now : Int64,
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
  if !self.clients.any(fn(exchange) { exchange.id == id }) {
    return Err(NotFound("unknown client request"))
  }
  self.clients = self.clients.filter(fn(exchange) { exchange.id != id })
  self.outbox.push(Cancelled(id))
  self.promote_outbound(now)
  Ok(())
}
