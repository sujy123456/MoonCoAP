///|
pub(all) struct Representation {
  payload : Bytes
  content_format : Int
  etag : Bytes
  max_age : Int64
} derive(Eq, Debug)

///|
pub extend Representation with Eq::{equal, not_equal}

///|
pub extend Representation with @debug.Debug::{to_repr}

///|
pub fn Representation::validate(
  self : Representation,
  limits : Limits,
) -> Result[Unit, Failure] {
  if self.payload.length() > limits.max_payload {
    return Err(Capacity("representation exceeds payload limit"))
  }
  if self.content_format < 0 || self.content_format > 65535 {
    return Err(Invalid("content format out of range"))
  }
  if self.etag.length() < 1 || self.etag.length() > 8 {
    return Err(Invalid("ETag must contain 1..8 bytes"))
  }
  if self.max_age < 0L || self.max_age > 4294967295L {
    return Err(Invalid("Max-Age exceeds unsigned 32 bits"))
  }
  Ok(())
}

///|
pub fn Representation::response(
  self : Representation,
  valid : Bool,
) -> Response {
  let options = [
    { number: 4, value: self.etag, },
    option_uint(14, self.max_age).unwrap(),
  ]
  if !valid {
    options.push(option_uint(12, self.content_format.to_int64()).unwrap())
  }
  {
    code: { value: if valid { 67 } else { 69 }, },
    options,
    payload: if valid {
      b""
    } else {
      self.payload
    },
  }
}

///|
pub fn preconditions(message : Message, current : Representation?) -> Bool {
  if message.first_option(5) is Some(_) && current is Some(_) {
    return false
  }
  let matches = message.option_values(1)
  if matches.is_empty() {
    return true
  }
  match current {
    None => false
    Some(value) => matches.any(fn(tag) { tag.is_empty() || tag == value.etag })
  }
}

///|
pub fn select_representation(
  message : Message,
  current : Representation,
) -> Response {
  match message_uint(message, 17, current.content_format.to_int64()) {
    Err(_) => return Response::error(130)
    Ok(format) =>
      if format != current.content_format.to_int64() {
        return Response::error(134)
      }
  }
  if !preconditions(message, Some(current)) {
    return Response::error(140)
  }
  current.response(message.option_values(4).contains(current.etag))
}

///|
struct StoredResource {
  path : Array[Bytes]
  representation : Representation
  writable : Bool
}

///|
pub(all) struct ResourceInfo {
  path : String
  content_format : Int
  size : Int
  etag : Bytes
  writable : Bool
} derive(Eq, Debug)

///|
pub extend ResourceInfo with Eq::{equal, not_equal}

///|
pub extend ResourceInfo with @debug.Debug::{to_repr}

///|
pub struct ResourceStore {
  limits : Limits
  capacity : Int
  max_bytes : Int
  allowed_formats : Array[Int]
  allow_create : Bool
  mut version : Int64
  resources : Array[StoredResource]
}

///|
pub fn ResourceStore::new(
  capacity : Int,
  max_bytes : Int,
  formats : Array[Int],
  allow_create : Bool,
  limits : Limits,
) -> Result[ResourceStore, Failure] {
  match limits.validate() {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if capacity < 1 || capacity > 4096 || max_bytes < 1 || max_bytes > 16777216 {
    return Err(Invalid("invalid resource store capacity"))
  }
  if formats.is_empty() || formats.any(fn(v) { v < 0 || v > 65535 }) {
    return Err(Invalid("invalid allowed content formats"))
  }
  Ok({
    limits,
    capacity,
    max_bytes,
    allowed_formats: formats.copy(),
    allow_create,
    version: 0L,
    resources: [],
  })
}

///|
pub fn ResourceStore::byte_size(self : ResourceStore) -> Int {
  let mut result = 0
  for resource in self.resources {
    result = result + resource.representation.payload.length()
  }
  result
}

///|
pub fn ResourceStore::inventory(self : ResourceStore) -> Array[ResourceInfo] {
  self.resources.map(fn(resource) {
    {
      path: canonical_path(resource.path),
      content_format: resource.representation.content_format,
      size: resource.representation.payload.length(),
      etag: resource.representation.etag,
      writable: resource.writable,
    }
  })
}

///|
fn ResourceStore::index(self : ResourceStore, path : Array[Bytes]) -> Int? {
  for i = 0; i < self.resources.length(); i = i + 1 {
    if self.resources[i].path == path {
      return Some(i)
    }
  }
  None
}

///|
fn ResourceStore::next_etag(self : ResourceStore) -> Result[Bytes, Failure] {
  if self.version == 9223372036854775807L {
    return Err(Capacity("resource revision space exhausted"))
  }
  self.version = self.version + 1L
  Ok(
    Bytes::makei(8, fn(i) {
      ((self.version >> ((7 - i) * 8)) & 255L).to_int().to_byte()
    }),
  )
}

///|
pub fn ResourceStore::get(
  self : ResourceStore,
  path : String,
) -> Result[Representation, Failure] {
  let parts = match resource_path(path, self.limits) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  match self.index(parts) {
    None => Err(NotFound("resource does not exist"))
    Some(i) => Ok(self.resources[i].representation)
  }
}

///|
pub fn ResourceStore::put(
  self : ResourceStore,
  path : String,
  payload : Bytes,
  format : Int,
  max_age : Int64,
  writable : Bool,
) -> Result[Representation, Failure] {
  let parts = match resource_path(path, self.limits) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let index = self.index(parts)
  let old_size = match index {
    None => 0
    Some(i) => self.resources[i].representation.payload.length()
  }
  if index is None && self.resources.length() >= self.capacity {
    return Err(Capacity("resource store is full"))
  }
  if !self.allowed_formats.contains(format) {
    return Err(Unsupported("unsupported content format"))
  }
  let candidate : Representation = {
    payload,
    content_format: format,
    etag: b"x",
    max_age,
  }
  match candidate.validate(self.limits) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if self.byte_size() - old_size + payload.length() > self.max_bytes {
    return Err(Capacity("resource byte budget exhausted"))
  }
  let tag = match self.next_etag() {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let value = { ..candidate, etag: tag, }
  match index {
    None =>
      self.resources.push({ path: parts, representation: value, writable, })
    Some(i) =>
      self.resources[i] = { path: parts, representation: value, writable, }
  }
  Ok(value)
}

///|
pub fn ResourceStore::remove(
  self : ResourceStore,
  path : String,
) -> Result[Bool, Failure] {
  let parts = match resource_path(path, self.limits) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  match self.index(parts) {
    None => Ok(false)
    Some(i) => {
      self.resources.remove(i) |> ignore
      Ok(true)
    }
  }
}

///|
pub fn ResourceStore::handle(
  self : ResourceStore,
  message : Message,
) -> Response {
  match validate_options(message, []) {
    Err(_) => return Response::error(130)
    Ok(_) => ()
  }
  let verb = match message.code.verb() {
    None => return Response::error(133)
    Some(v) => v
  }
  let parts = message.option_values(11)
  let index = self.index(parts)
  let current = match index {
    None => None
    Some(i) => Some(self.resources[i].representation)
  }
  if verb == Get {
    return match current {
      None => Response::error(132)
      Some(value) => select_representation(message, value)
    }
  }
  if verb == Post {
    return Response::error(133)
  }
  if index is None && (verb != Put || !self.allow_create) {
    return Response::error(132)
  }
  match index {
    Some(i) => if !self.resources[i].writable { return Response::error(133) }
    None => ()
  }
  if !preconditions(message, current) {
    return Response::error(140)
  }
  if verb == Delete {
    match index {
      Some(i) => self.resources.remove(i) |> ignore
      None => ()
    }
    return Response::error(66)
  }
  let format = match message_uint(message, 12, 0L) {
    Err(_) => return Response::error(130)
    Ok(v) => v.to_int()
  }
  if !self.allowed_formats.contains(format) {
    return Response::error(143)
  }
  if message.payload.length() > self.limits.max_payload {
    return {
      code: { value: 141, },
      options: [option_uint(60, self.limits.max_payload.to_int64()).unwrap()],
      payload: b"",
    }
  }
  let age = match current {
    None => 60L
    Some(value) => value.max_age
  }
  let representation = match
    self.put(canonical_path(parts), message.payload, format, age, true) {
    Err(_) => return Response::error(163)
    Ok(value) => value
  }
  {
    code: { value: if current is None { 65 } else { 68 }, },
    options: [{ number: 4, value: representation.etag, }],
    payload: b"",
  }
}
