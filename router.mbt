///|
pub(all) struct RouteMatch {
  path : Array[Bytes]
  verb : Method
} derive(Eq, Debug)

///|
pub extend RouteMatch with Eq::{equal, not_equal}

///|
pub extend RouteMatch with @debug.Debug::{to_repr}

///|
struct Route {
  path : Array[Bytes]
  verbs : Array[Method]
  handler : (IncomingRequest) -> Response
}

///|
pub struct Router {
  limits : Limits
  capacity : Int
  mut routes : Array[Route]
}

///|
pub fn Router::new(capacity : Int, limits : Limits) -> Result[Router, Failure] {
  match limits.validate() {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  if capacity < 1 || capacity > 4096 {
    return Err(Invalid("route capacity must be 1..4096"))
  }
  Ok({ limits, capacity, routes: [], })
}

///|
pub fn resource_path(
  path : String,
  limits : Limits,
) -> Result[Array[Bytes], Failure] {
  if !path.has_prefix("/") || path.contains("?") || path.contains("#") {
    return Err(
      Invalid("resource path must be absolute without query or fragment"),
    )
  }
  match CoapUri::parse("coap://localhost" + path, limits) {
    Err(e) => Err(e)
    Ok(uri) => Ok(uri.path)
  }
}

///|
pub fn canonical_path(parts : Array[Bytes]) -> String {
  if parts.is_empty() {
    return "/"
  }
  let mut result = ""
  for part in parts {
    result = result + "/" + percent_encode(part)
  }
  result
}

///|
pub fn Router::add(
  self : Router,
  path : String,
  verbs : Array[Method],
  handler : (IncomingRequest) -> Response,
) -> Result[Unit, Failure] {
  let parts = match resource_path(path, self.limits) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  if verbs.is_empty() {
    return Err(Invalid("route requires at least one method"))
  }
  let unique : Array[Method] = []
  for verb in verbs {
    if unique.contains(verb) {
      return Err(Invalid("duplicate route method"))
    }
    unique.push(verb)
  }
  for route in self.routes {
    if route.path == parts && route.verbs.any(fn(v) { unique.contains(v) }) {
      return Err(Conflict("route method is already registered"))
    }
  }
  if self.routes.length() >= self.capacity {
    return Err(Capacity("router is full"))
  }
  self.routes.push({ path: parts, verbs: unique, handler, })
  Ok(())
}

///|
pub fn Router::remove(self : Router, path : String) -> Result[Int, Failure] {
  let parts = match resource_path(path, self.limits) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let before = self.routes.length()
  self.routes = self.routes.filter(fn(route) { route.path != parts })
  Ok(before - self.routes.length())
}

///|
pub fn Router::routes(self : Router) -> Array[RouteMatch] {
  let result : Array[RouteMatch] = []
  for route in self.routes {
    for verb in route.verbs {
      result.push({ path: route.path.copy(), verb, })
    }
  }
  result
}

///|
pub fn Router::dispatch(self : Router, incoming : IncomingRequest) -> Response {
  let message = incoming.message
  if !message.code.is_request() {
    return Response::error(128)
  }
  match validate_options(message, []) {
    Err(_) => return Response::error(130)
    Ok(_) => ()
  }
  let verb = match message.code.verb() {
    None => return Response::error(133)
    Some(v) => v
  }
  let parts = message.option_values(11)
  let mut found_path = false
  for route in self.routes {
    if route.path == parts {
      found_path = true
      if route.verbs.contains(verb) {
        return (route.handler)({ ..incoming, message: message.copy(), })
      }
    }
  }
  Response::error(if found_path { 133 } else { 132 })
}

///|
pub fn Endpoint::serve(
  self : Endpoint,
  router : Router,
  incoming : IncomingRequest,
  now : Int64,
) -> Result[Unit, Failure] {
  self.respond(incoming.id, router.dispatch(incoming), now, 0)
}
