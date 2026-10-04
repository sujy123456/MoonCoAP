///|
priv struct MidLease {
  peer : String
  mid : Int
  expires_at : Int64
}

///|
pub struct Allocator {
  priv mut next_mid : Int
  priv mut token_counter : Int64
  priv lifetime_ms : Int64
  priv capacity : Int
  priv mut last_now : Int64
  priv mut leases : Array[MidLease]
}

///|
fn validate_peer(peer : String) -> Result[Unit, Failure] {
  if peer.is_empty() || peer.length() > 256 {
    return Err(Invalid("peer key must be 1..256 characters"))
  }
  for character in peer.iter() {
    if character.to_int() < 32 || character.to_int() == 127 {
      return Err(Invalid("peer key contains a control character"))
    }
  }
  Ok(())
}

///|
pub fn Allocator::new(config : Config) -> Result[Allocator, Failure] {
  match config.validate() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  Ok({
    next_mid: config.initial_mid,
    token_counter: config.token_seed,
    lifetime_ms: config.exchange_lifetime_ms,
    capacity: config.max_mid_leases,
    last_now: 0L,
    leases: [],
  })
}

///|
pub fn Allocator::collect(
  self : Allocator,
  now : Int64,
) -> Result[Int, Failure] {
  if now < self.last_now {
    return Err(Clock("allocator clock moved backwards"))
  }
  self.last_now = now
  let previous = self.leases.length()
  self.leases = self.leases.filter(fn(lease) { lease.expires_at > now })
  Ok(previous - self.leases.length())
}

///|
pub fn Allocator::is_reserved(
  self : Allocator,
  peer : String,
  mid : Int,
) -> Bool {
  self.leases.any(fn(lease) { lease.peer == peer && lease.mid == mid })
}

///|
pub fn Allocator::active_leases(self : Allocator) -> Int {
  self.leases.length()
}

///|
pub fn Allocator::remaining_capacity(self : Allocator) -> Int {
  self.capacity - self.leases.length()
}

///|
pub fn Allocator::next_expiry(self : Allocator) -> Int64? {
  let mut expiry : Int64? = None
  for lease in self.leases {
    expiry = earlier(expiry, lease.expires_at)
  }
  expiry
}

///|
pub fn Allocator::reserve(
  self : Allocator,
  peer : String,
  mid : Int,
  now : Int64,
) -> Result[Unit, Failure] {
  match validate_peer(peer) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if mid < 0 || mid > 65535 {
    return Err(Invalid("MID must fit unsigned 16 bits"))
  }
  let expiry = match deadline_after(now, self.lifetime_ms) {
    Err(error) => return Err(error)
    Ok(value) => value
  }
  match self.collect(now) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if self.is_reserved(peer, mid) {
    return Err(Conflict("MID is still reserved for this peer"))
  }
  if self.leases.length() >= self.capacity {
    return Err(Capacity("MID leases are full"))
  }
  self.leases.push({ peer, mid, expires_at: expiry, })
  Ok(())
}

///|
pub fn Allocator::allocate_mid(
  self : Allocator,
  peer : String,
  now : Int64,
) -> Result[Int, Failure] {
  match validate_peer(peer) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match self.collect(now) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if self.leases.length() >= self.capacity {
    return Err(Capacity("MID leases are full"))
  }
  let search_bound = self.leases.length() + 1
  for _attempt = 0; _attempt < search_bound; _attempt = _attempt + 1 {
    let candidate = self.next_mid
    self.next_mid = (self.next_mid + 1) & 65535
    if !self.is_reserved(peer, candidate) {
      match self.reserve(peer, candidate, now) {
        Err(error) => return Err(error)
        Ok(_) => return Ok(candidate)
      }
    }
  }
  Err(Capacity("no unused message identifier"))
}

///|
pub fn Allocator::allocate_token(self : Allocator) -> Result[Bytes, Failure] {
  if self.token_counter == 9223372036854775807L {
    return Err(Capacity("Token counter exhausted"))
  }
  let counter = self.token_counter
  self.token_counter = self.token_counter + 1L
  Ok(
    Bytes::makei(8, fn(i) {
      ((counter >> ((7 - i) * 8)) & 255L).to_int().to_byte()
    }),
  )
}
