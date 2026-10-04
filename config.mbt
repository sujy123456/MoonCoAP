///|
pub(all) struct Config {
  limits : Limits
  ack_timeout_ms : Int64
  ack_random_factor_permille : Int
  max_retransmit : Int
  exchange_lifetime_ms : Int64
  non_lifetime_ms : Int64
  response_timeout_ms : Int64
  max_peers : Int
  max_exchanges : Int
  max_dedup : Int
  max_mid_leases : Int
  max_queue : Int
  max_actions : Int
  nstart : Int
  initial_mid : Int
  token_seed : Int64
} derive(Eq, Debug)

///|
pub extend Config with Eq::{equal, not_equal}

///|
pub extend Config with @debug.Debug::{to_repr}

///|
pub fn Config::default() -> Config {
  {
    limits: Limits::default(),
    ack_timeout_ms: 2000L,
    ack_random_factor_permille: 1500,
    max_retransmit: 4,
    exchange_lifetime_ms: 247000L,
    non_lifetime_ms: 145000L,
    response_timeout_ms: 247000L,
    max_peers: 64,
    max_exchanges: 128,
    max_dedup: 256,
    max_mid_leases: 4096,
    max_queue: 128,
    max_actions: 1024,
    nstart: 1,
    initial_mid: 0,
    token_seed: 1L,
  }
}

///|
pub fn Config::validate(self : Config) -> Result[Unit, Failure] {
  match self.limits.validate() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if self.ack_timeout_ms < 1L || self.ack_timeout_ms > 60000L {
    return Err(Invalid("ACK timeout must be 1..60000 milliseconds"))
  }
  if self.ack_random_factor_permille < 1000 ||
    self.ack_random_factor_permille > 2000 {
    return Err(Invalid("random factor must be 1000..2000 permille"))
  }
  if self.max_retransmit < 0 || self.max_retransmit > 8 {
    return Err(Invalid("max_retransmit must be 0..8"))
  }
  if self.exchange_lifetime_ms < 1L || self.exchange_lifetime_ms > 604800000L {
    return Err(
      Invalid("exchange lifetime must be positive and at most one week"),
    )
  }
  if self.non_lifetime_ms < 1L ||
    self.non_lifetime_ms > self.exchange_lifetime_ms {
    return Err(Invalid("NON lifetime must not exceed exchange lifetime"))
  }
  if self.response_timeout_ms < self.ack_timeout_ms ||
    self.response_timeout_ms > self.exchange_lifetime_ms {
    return Err(Invalid("response timeout outside exchange lifetime"))
  }
  if self.max_peers < 1 || self.max_peers > 4096 {
    return Err(Invalid("peer count must be 1..4096"))
  }
  if self.max_exchanges < 1 || self.max_exchanges > 4096 {
    return Err(Invalid("exchange count must be 1..4096"))
  }
  if self.max_dedup < 1 || self.max_dedup > 65536 {
    return Err(Invalid("deduplication count must be 1..65536"))
  }
  if self.max_mid_leases < self.max_exchanges || self.max_mid_leases > 65536 {
    return Err(Invalid("MID lease capacity outside supported range"))
  }
  if self.max_queue < 0 || self.max_queue > self.max_exchanges {
    return Err(Invalid("queue count must not exceed exchange count"))
  }
  if self.max_actions < 2 * self.max_exchanges + self.max_dedup + 4 ||
    self.max_actions > 131072 {
    return Err(Invalid("action capacity must cover a complete polling batch"))
  }
  if self.nstart < 1 || self.nstart > self.max_exchanges {
    return Err(Invalid("NSTART outside supported range"))
  }
  if self.initial_mid < 0 || self.initial_mid > 65535 || self.token_seed < 0L {
    return Err(Invalid("invalid allocator seed"))
  }
  let maximum_interval = self.ack_timeout_ms *
    self.ack_random_factor_permille.to_int64() /
    1000L
  let transmit_wait = maximum_interval *
    ((1L << (self.max_retransmit + 1)) - 1L)
  if self.exchange_lifetime_ms < transmit_wait {
    return Err(
      Invalid("exchange lifetime is shorter than maximum transmit wait"),
    )
  }
  Ok(())
}

///|
pub fn retry_interval(
  config : Config,
  random_sample : Int,
) -> Result[Int64, Failure] {
  match config.validate() {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  if random_sample < 0 || random_sample > 1000000 {
    return Err(Invalid("random sample must be 0..1000000"))
  }
  let maximum_extra = config.ack_timeout_ms *
    (config.ack_random_factor_permille - 1000).to_int64() /
    1000L
  Ok(
    config.ack_timeout_ms + maximum_extra * random_sample.to_int64() / 1000000L,
  )
}

///|
pub fn deadline_after(now : Int64, delay : Int64) -> Result[Int64, Failure] {
  if now < 0L || delay < 0L || now > 9223372036854775807L - delay {
    return Err(Clock("negative time or deadline overflow"))
  }
  Ok(now + delay)
}

///|
pub fn Config::max_transmit_span(self : Config) -> Int64 {
  self.ack_timeout_ms *
  ((1L << self.max_retransmit) - 1L) *
  self.ack_random_factor_permille.to_int64() /
  1000L
}
