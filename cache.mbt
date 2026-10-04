///|
pub(all) struct CacheKey {
  peer : String
  options : Array[CoapOption]
} derive(Eq, Debug)

///|
pub extend CacheKey with Eq::{equal, not_equal}

///|
pub extend CacheKey with @debug.Debug::{to_repr}

///|
pub fn cache_key(
  peer : String,
  request : Request,
  limits : Limits,
) -> Result[CacheKey, Failure] {
  match validate_peer(peer) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if request.verb != Get || !request.payload.is_empty() {
    return Err(Unsupported("cache only accepts payload-free GET"))
  }
  let message = Message::new(Confirmable, Code::request(Get), 0)
  message.options = request.options.copy()
  match validate_options(message, []) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match encode(message, limits) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if message.first_option(1) is Some(_) || message.first_option(5) is Some(_) {
    return Err(
      Unsupported("conditional mutations cannot use the representation cache"),
    )
  }
  let options : Array[CoapOption] = []
  for option in ordered_options(message.options) {
    if option.number == 4 || !option_is_cache_key(option.number) {
      continue
    }
    match standard_option(option.number) {
      Some(spec) =>
        if spec.kind == Unsigned {
          options.push(
            option_uint(option.number, option_to_uint(option).unwrap()).unwrap(),
          )
        } else if option.number == 3 {
          options.push(
            option_text(3, option_to_text(option).unwrap().to_lower()),
          )
        } else {
          options.push(option)
        }
      None => options.push(option)
    }
  }
  Ok({ peer, options, })
}

///|
pub(all) enum CacheLookup {
  Miss
  Fresh(Response)
  Stale(Response, Request)
} derive(Eq, Debug)

///|
pub extend CacheLookup with Eq::{equal, not_equal}

///|
pub extend CacheLookup with @debug.Debug::{to_repr}

///|
pub(all) struct CacheStats {
  hits : Int64
  misses : Int64
  stale : Int64
  insertions : Int64
  validations : Int64
  evictions : Int64
  entries : Int
  bytes : Int
} derive(Eq, Debug)

///|
pub extend CacheStats with Eq::{equal, not_equal}

///|
pub extend CacheStats with @debug.Debug::{to_repr}

///|
priv struct CacheEntry {
  key : CacheKey
  response : Response
  expires_at : Int64
  cost : Int
  mut touched : Int64
}

///|
pub struct ResponseCache {
  priv limits : Limits
  priv capacity : Int
  priv max_bytes : Int
  priv mut entries : Array[CacheEntry]
  priv mut last_now : Int64
  priv mut sequence : Int64
  priv mut hits : Int64
  priv mut misses : Int64
  priv mut stale : Int64
  priv mut insertions : Int64
  priv mut validations : Int64
  priv mut evictions : Int64
}

///|
pub fn ResponseCache::new(
  capacity : Int,
  max_bytes : Int,
  limits : Limits,
) -> Result[ResponseCache, Failure] {
  match limits.validate() {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if capacity < 1 || capacity > 4096 || max_bytes < 1 || max_bytes > 16777216 {
    return Err(Invalid("invalid response cache capacity"))
  }
  Ok({
    limits,
    capacity,
    max_bytes,
    entries: [],
    last_now: 0L,
    sequence: 0L,
    hits: 0L,
    misses: 0L,
    stale: 0L,
    insertions: 0L,
    validations: 0L,
    evictions: 0L,
  })
}

///|
fn ResponseCache::observe(
  self : ResponseCache,
  now : Int64,
) -> Result[Unit, Failure] {
  if now < self.last_now {
    return Err(Clock("cache clock moved backwards"))
  }
  if self.sequence == 9223372036854775807L {
    return Err(Capacity("cache usage sequence exhausted"))
  }
  self.last_now = now
  self.sequence = self.sequence + 1L
  Ok(())
}

///|
pub fn ResponseCache::stats(self : ResponseCache) -> CacheStats {
  let mut bytes = 0
  for entry in self.entries {
    bytes = bytes + entry.cost
  }
  {
    hits: self.hits,
    misses: self.misses,
    stale: self.stale,
    insertions: self.insertions,
    validations: self.validations,
    evictions: self.evictions,
    entries: self.entries.length(),
    bytes,
  }
}

///|
fn ResponseCache::find(self : ResponseCache, key : CacheKey) -> Int? {
  for i = 0; i < self.entries.length(); i = i + 1 {
    if self.entries[i].key == key {
      return Some(i)
    }
  }
  None
}

///|
fn aged_response(response : Response, remaining : Int64) -> Response {
  let options = response.options.filter(fn(option) { option.number != 14 })
  options.push(
    option_uint(14, if remaining > 0L { remaining / 1000L } else { 0L }).unwrap(),
  )
  { code: response.code, options, payload: response.payload, }
}

///|
pub fn ResponseCache::lookup(
  self : ResponseCache,
  peer : String,
  request : Request,
  now : Int64,
) -> Result[CacheLookup, Failure] {
  let key = match cache_key(peer, request, self.limits) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  match self.observe(now) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let index = match self.find(key) {
    None => {
      self.misses = self.misses + 1L
      return Ok(Miss)
    }
    Some(i) => i
  }
  let entry = self.entries[index]
  entry.touched = self.sequence
  if entry.expires_at > now {
    self.hits = self.hits + 1L
    return Ok(Fresh(aged_response(entry.response, entry.expires_at - now)))
  }
  self.stale = self.stale + 1L
  let options = request.options.filter(fn(option) { option.number != 4 })
  for tag in entry.response.options.filter(fn(option) { option.number == 4 }) {
    options.push(tag)
  }
  let validation : Request = { ..request, options, }
  match cache_key(peer, validation, self.limits) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  Ok(Stale(aged_response(entry.response, 0L), validation))
}

///|
fn response_cost(key : CacheKey, response : Response) -> Int {
  let mut cost = @utf8.encode(key.peer).length() +
    response.payload.length() +
    64
  for option in key.options {
    cost = cost + option.value.length() + 8
  }
  for option in response.options {
    cost = cost + option.value.length() + 8
  }
  cost
}

///|
fn validate_cached_response(
  response : Response,
  limits : Limits,
) -> Result[Int64, Failure] {
  let message = Message::new(NonConfirmable, response.code, 0)
  message.options = response.options.copy()
  message.payload = response.payload
  match validate_options(message, []) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match encode(message, limits) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  message_uint(message, 14, 60L)
}

///|
fn ResponseCache::evict_oldest(self : ResponseCache) -> Unit {
  let mut index = 0
  for i = 1; i < self.entries.length(); i = i + 1 {
    if self.entries[i].touched < self.entries[index].touched {
      index = i
    }
  }
  self.entries.remove(index) |> ignore
  self.evictions = self.evictions + 1L
}

///|
pub fn ResponseCache::store(
  self : ResponseCache,
  peer : String,
  request : Request,
  response : Response,
  now : Int64,
) -> Result[Unit, Failure] {
  let key = match cache_key(peer, request, self.limits) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  if response.code.value != 69 {
    return Err(Unsupported("only 2.05 Content representations are cached"))
  }
  let max_age = match validate_cached_response(response, self.limits) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  match
    validate_cached_response(
      aged_response(response, max_age * 1000L),
      self.limits,
    ) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let expiry = match deadline_after(now, max_age * 1000L) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let cost = response_cost(key, response)
  if cost > self.max_bytes {
    return Err(Capacity("representation exceeds cache byte budget"))
  }
  match self.observe(now) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match self.find(key) {
    Some(i) => self.entries.remove(i) |> ignore
    None => ()
  }
  while self.entries.length() >= self.capacity ||
        self.stats().bytes > self.max_bytes - cost {
    self.evict_oldest()
  }
  self.entries.push({
    key,
    response: { ..response, options: response.options.copy(), },
    expires_at: expiry,
    cost,
    touched: self.sequence,
  })
  self.insertions = self.insertions + 1L
  Ok(())
}

///|
pub fn ResponseCache::validate(
  self : ResponseCache,
  peer : String,
  request : Request,
  response : Response,
  now : Int64,
) -> Result[Unit, Failure] {
  if response.code.value != 67 || !response.payload.is_empty() {
    return Err(Invalid("validation requires empty 2.03 Valid response"))
  }
  let key = match cache_key(peer, request, self.limits) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let age = match validate_cached_response(response, self.limits) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let expiry = match deadline_after(now, age * 1000L) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let index = match self.find(key) {
    None => return Err(NotFound("no representation to validate"))
    Some(i) => i
  }
  let entry = self.entries[index]
  let offered = request.options
    .filter(fn(option) { option.number == 4 })
    .map(fn(option) { option.value })
  let old_tags = entry.response.options
    .filter(fn(option) { option.number == 4 })
    .map(fn(option) { option.value })
  let tags = response.options
    .filter(fn(option) { option.number == 4 })
    .map(fn(option) { option.value })
  if tags.length() != 1 ||
    !old_tags.contains(tags[0]) ||
    !offered.contains(tags[0]) {
    return Err(Conflict("validation ETag was not offered or does not match"))
  }
  let options = entry.response.options.copy()
  let replaced : Array[Int] = []
  for replacement in response.options {
    if !replaced.contains(replacement.number) {
      for i = options.length() - 1; i >= 0; i = i - 1 {
        if options[i].number == replacement.number {
          options.remove(i) |> ignore
        }
      }
      replaced.push(replacement.number)
    }
    options.push(replacement)
  }
  let merged : Response = { ..entry.response, options, }
  match validate_cached_response(merged, self.limits) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  match
    validate_cached_response(aged_response(merged, age * 1000L), self.limits) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let cost = response_cost(key, merged)
  if self.stats().bytes - entry.cost + cost > self.max_bytes {
    return Err(Capacity("validated metadata exceeds cache budget"))
  }
  match self.observe(now) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  self.entries[index] = {
    key,
    response: merged,
    expires_at: expiry,
    cost,
    touched: self.sequence,
  }
  self.validations = self.validations + 1L
  Ok(())
}

///|
pub fn ResponseCache::invalidate(
  self : ResponseCache,
  peer : String,
  path : String,
) -> Result[Int, Failure] {
  let parts = match resource_path(path, self.limits) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let before = self.entries.length()
  self.entries = self.entries.filter(fn(entry) {
    entry.key.peer != peer ||
    entry.key.options
    .filter(fn(option) { option.number == 11 })
    .map(fn(option) { option.value }) !=
    parts
  })
  Ok(before - self.entries.length())
}

///|
pub fn ResponseCache::clear(self : ResponseCache) -> Int {
  let count = self.entries.length()
  self.entries = []
  count
}
