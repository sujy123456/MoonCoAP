///|
pub suberror ProtocolError {
  ProtocolError(@coap.Failure)
} derive(Debug)

///|
pub extend ProtocolError with @debug.Debug::{to_repr}

///|
pub(all) enum UdpEvent {
  Delivered(@coap.Action)
  Discarded(String, @coap.Failure)
} derive(Eq, Debug)

///|
pub extend UdpEvent with Eq::{equal, not_equal}

///|
pub extend UdpEvent with @debug.Debug::{to_repr}

///|
fn[T] checked(result : Result[T, @coap.Failure]) -> T raise ProtocolError {
  match result {
    Ok(value) => value
    Err(error) => raise ProtocolError(error)
  }
}

///|
pub struct UdpEndpoint {
  priv socket : @socket.UdpServer
  priv core : @coap.Endpoint
  priv limits : @coap.Limits
  priv random : @random.Rand
  priv buffer : FixedArray[Byte]
  priv max_events : Int
  priv origin : Int64
  priv mut clock : Int64
  priv mut closed : Bool
  priv mut pending : Array[UdpEvent]
}

///|
pub async fn UdpEndpoint::bind(
  address : String,
  config : @coap.Config,
) -> UdpEndpoint {
  let addr = @socket.Addr::parse(address)
  if addr.is_multicast() {
    raise ProtocolError(@coap.Unsupported("multicast is outside this profile"))
  }
  let core = checked(@coap.Endpoint::new(config))
  let socket = @socket.UdpServer(addr)
  {
    socket,
    core,
    limits: config.limits,
    random: @random.Rand::new(),
    buffer: FixedArray::make(65536, b'\x00'),
    max_events: config.max_actions * 2,
    origin: @async.now(),
    clock: 0L,
    closed: false,
    pending: [],
  }
}

///|
pub fn network_config(config : @coap.Config) -> @coap.Config {
  let random = @random.Rand::new()
  {
    ..config,
    initial_mid: random.int(limit=65536),
    token_seed: random.int64(limit=4611686018427387903L) + 1L,
  }
}

///|
pub fn UdpEndpoint::address(self : UdpEndpoint) -> String {
  self.socket.addr.to_string()
}

///|
pub fn UdpEndpoint::close(self : UdpEndpoint) -> Unit {
  if !self.closed {
    self.closed = true
    self.socket.close()
  }
}

///|
fn UdpEndpoint::ensure_open(self : UdpEndpoint) -> Unit raise ProtocolError {
  if self.closed {
    raise ProtocolError(@coap.Transport("UDP endpoint is closed"))
  }
}

///|
pub fn UdpEndpoint::now(self : UdpEndpoint) -> Int64 {
  let elapsed = @async.now() - self.origin
  if elapsed > self.clock {
    self.clock = elapsed
  }
  self.clock
}

///|
pub fn UdpEndpoint::state(self : UdpEndpoint) -> Array[@coap.ExchangeView] {
  self.core.exchanges()
}

///|
pub fn UdpEndpoint::server_state(self : UdpEndpoint) -> Array[@coap.ServerView] {
  self.core.server_records()
}

///|
pub fn UdpEndpoint::next_deadline(self : UdpEndpoint) -> Int64? {
  self.core.next_deadline()
}

///|
pub fn UdpEndpoint::outstanding(self : UdpEndpoint) -> Int {
  self.core.exchange_count()
}

///|
pub fn UdpEndpoint::drain(self : UdpEndpoint) -> Array[UdpEvent] {
  let result = self.pending
  self.pending = []
  result
}

///|
pub async fn UdpEndpoint::flush(self : UdpEndpoint) -> Unit {
  self.ensure_open()
  if self.pending.length() + self.core.pending_actions() > self.max_events {
    raise ProtocolError(@coap.Capacity("drain UDP events before flushing"))
  }
  let actions = self.core.drain()
  for action in actions {
    match action {
      @coap.SendDatagram(peer, bytes) =>
        self.socket.sendto(bytes, @socket.Addr::parse(peer)) catch {
          error =>
            self.pending.push(
              Discarded(peer, @coap.Transport(error.to_string())),
            )
        }
      _ => self.pending.push(Delivered(action))
    }
  }
}

///|
pub async fn UdpEndpoint::request(
  self : UdpEndpoint,
  address : String,
  request : @coap.Request,
) -> Int {
  self.ensure_open()
  self.ensure_room()
  let addr = @socket.Addr::parse(address)
  if addr.is_multicast() {
    raise ProtocolError(@coap.Unsupported("unicast address required"))
  }
  let id = checked(
    self.core.request(
      addr.to_string(),
      request,
      self.now(),
      self.random.int(limit=1000001),
    ),
  )
  self.flush()
  id
}

///|
pub async fn UdpEndpoint::respond(
  self : UdpEndpoint,
  id : Int,
  response : @coap.Response,
) -> Unit {
  self.ensure_open()
  self.ensure_room()
  checked(
    self.core.respond(id, response, self.now(), self.random.int(limit=1000001)),
  )
  self.flush()
}

///|
pub async fn UdpEndpoint::acknowledge(self : UdpEndpoint, id : Int) -> Unit {
  self.ensure_open()
  self.ensure_room()
  checked(self.core.acknowledge(id, self.now()))
  self.flush()
}

///|
pub async fn UdpEndpoint::cancel(self : UdpEndpoint, id : Int) -> Unit {
  self.ensure_open()
  self.ensure_room()
  checked(self.core.cancel(id, self.now()))
  self.flush()
}

///|
fn UdpEndpoint::wait_limit(self : UdpEndpoint, maximum : Int) -> Int {
  let now = self.now()
  let limit = match self.core.next_deadline() {
    None => maximum
    Some(deadline) => {
      let remaining = deadline - now
      if remaining <= 0L {
        0
      } else if remaining < maximum.to_int64() {
        remaining.to_int()
      } else {
        maximum
      }
    }
  }
  if limit < 1 {
    1
  } else {
    limit
  }
}

///|
pub async fn UdpEndpoint::step(
  self : UdpEndpoint,
  maximum_wait_ms : Int,
) -> Array[UdpEvent] {
  self.ensure_open()
  if maximum_wait_ms < 1 || maximum_wait_ms > 60000 {
    raise ProtocolError(@coap.Invalid("step wait must be 1..60000ms"))
  }
  if !self.pending.is_empty() {
    return self.drain()
  }
  self.flush()
  if !self.pending.is_empty() {
    return self.drain()
  }
  let result = @async.with_timeout_opt(self.wait_limit(maximum_wait_ms), async fn() {
    self.socket.recvfrom(self.buffer)
  })
  match result {
    None => ()
    Some((length, peer)) => {
      let name = peer.to_string()
      if peer.is_multicast() {
        self.pending.push(
          Discarded(name, @coap.Unsupported("multicast sender")),
        )
      } else if length > self.limits.max_datagram {
        self.pending.push(
          Discarded(
            name,
            @coap.Capacity("received datagram exceeds configured maximum"),
          ),
        )
      } else {
        let packet = Bytes::makei(length, fn(i) { self.buffer[i] })
        match self.core.receive(name, packet, self.now()) {
          Ok(_) => ()
          Err(error) => self.pending.push(Discarded(name, error))
        }
      }
    }
  }
  self.flush()
  checked(self.core.poll(self.now()))
  self.flush()
  self.drain()
}

///|
pub async fn UdpEndpoint::exchange(
  self : UdpEndpoint,
  address : String,
  request : @coap.Request,
  timeout_ms : Int,
) -> @coap.Message {
  if timeout_ms < 1 || timeout_ms > 3600000 {
    raise ProtocolError(@coap.Invalid("exchange timeout must be 1..3600000ms"))
  }
  if self.outstanding() != 0 {
    raise ProtocolError(
      @coap.Conflict("convenience exchange requires an idle endpoint"),
    )
  }
  let id = self.request(address, request)
  let deadline = self.now() + timeout_ms.to_int64()
  let retained : Array[UdpEvent] = []
  while self.now() < deadline {
    let remaining = (deadline - self.now()).to_int()
    let events = self.step(if remaining < 1000 { remaining } else { 1000 })
    let mut reply : @coap.Message? = None
    let mut failure : @coap.Failure? = None
    let mut unrelated = false
    for event in events {
      match event {
        Delivered(@coap.ResponseReceived(received_id, response)) =>
          if received_id == id {
            reply = Some(response)
          } else {
            unrelated = true
            retained.push(event)
          }
        Delivered(@coap.Failed(failed_id, error)) =>
          if failed_id == id {
            failure = Some(error)
          } else {
            unrelated = true
            retained.push(event)
          }
        Discarded(_, _) => retained.push(event)
        _ => {
          unrelated = true
          retained.push(event)
        }
      }
    }
    if retained.length() > self.max_events - self.core.action_capacity() {
      self.abort_exchange(id)
      self.pending = retained
      raise ProtocolError(
        @coap.Capacity("too many diagnostics during exchange"),
      )
    }
    match reply {
      Some(response) => {
        self.pending = retained
        return response
      }
      None => ()
    }
    match failure {
      Some(error) => {
        self.pending = retained
        raise ProtocolError(error)
      }
      None => ()
    }
    if unrelated {
      self.pending = retained
      self.abort_exchange(id)
      raise ProtocolError(
        @coap.Conflict(
          "unrelated events received; use request/step for duplex endpoints",
        ),
      )
    }
  }
  self.pending = retained
  self.abort_exchange(id)
  raise ProtocolError(@coap.TimedOut)
}

///|
fn UdpEndpoint::ensure_room(self : UdpEndpoint) -> Unit raise ProtocolError {
  if self.pending.length() > self.max_events - self.core.action_capacity() {
    raise ProtocolError(
      @coap.Capacity("drain UDP events before submitting more work"),
    )
  }
}

///|
async fn UdpEndpoint::abort_exchange(self : UdpEndpoint, id : Int) -> Unit {
  if self.core.exchanges().any(fn(exchange) { exchange.id == id }) {
    self.cancel(id)
  }
  self.pending = self.pending.filter(fn(event) {
    match event {
      Delivered(@coap.Cancelled(value))
      | Delivered(@coap.Failed(value, _))
      | Delivered(@coap.ResponseReceived(value, _)) => value != id
      _ => true
    }
  })
}
