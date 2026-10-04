///|
pub fn parse_ipv4(text : String) -> Result[Array[Int], Failure] {
  let parts = text.split(".").collect()
  if parts.length() != 4 {
    return Err(Invalid("IPv4 address needs four octets"))
  }
  let result : Array[Int] = []
  for part in parts {
    let segment = part.to_owned()
    if segment.length() > 1 && segment.has_prefix("0") {
      return Err(Invalid("IPv4 octets cannot have leading zeroes"))
    }
    match unsigned_decimal(segment, 255L) {
      Err(e) => return Err(e)
      Ok(value) => result.push(value.to_int())
    }
  }
  Ok(result)
}

///|
fn ipv6_half(text : String, allow_ipv4 : Bool) -> Result[Array[Int], Failure] {
  if text.is_empty() {
    return Ok([])
  }
  let parts = text.split(":").collect()
  let result : Array[Int] = []
  for i = 0; i < parts.length(); i = i + 1 {
    let part = parts[i].to_owned()
    if part.contains(".") {
      if !allow_ipv4 || i != parts.length() - 1 {
        return Err(Invalid("embedded IPv4 must be the final IPv6 component"))
      }
      let octets = match parse_ipv4(part) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      result.push(octets[0] * 256 + octets[1])
      result.push(octets[2] * 256 + octets[3])
      continue
    }
    if part.is_empty() || part.length() > 4 {
      return Err(Invalid("invalid IPv6 component length"))
    }
    let mut value = 0
    for character in part.iter() {
      let digit = hex_digit(character.to_int())
      if digit < 0 {
        return Err(Invalid("invalid IPv6 hexadecimal component"))
      }
      value = value * 16 + digit
    }
    result.push(value)
  }
  Ok(result)
}

///|
pub fn parse_ipv6(text : String) -> Result[Array[Int], Failure] {
  if text.is_empty() ||
    text.contains("%") ||
    text.contains("[") ||
    text.contains("]") {
    return Err(Invalid("invalid or scoped IPv6 literal"))
  }
  match text.split_once("::") {
    None => {
      let words = match ipv6_half(text, true) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      if words.length() != 8 {
        return Err(Invalid("uncompressed IPv6 address requires eight words"))
      }
      Ok(words)
    }
    Some((left_text, right_text)) => {
      if right_text.contains("::") {
        return Err(Invalid("multiple IPv6 compression markers"))
      }
      let left = match ipv6_half(left_text.to_owned(), false) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      let right = match ipv6_half(right_text.to_owned(), true) {
        Err(e) => return Err(e)
        Ok(v) => v
      }
      if left.length() + right.length() >= 8 {
        return Err(Invalid("IPv6 compression must replace at least one word"))
      }
      let result = left.copy()
      for _i = left.length() + right.length(); _i < 8; _i = _i + 1 {
        result.push(0)
      }
      for word in right {
        result.push(word)
      }
      Ok(result)
    }
  }
}

///|
pub fn canonical_ipv6(text : String) -> Result[String, Failure] {
  let words = match parse_ipv6(text) {
    Err(e) => return Err(e)
    Ok(v) => v
  }
  let mut longest_start = -1
  let mut longest_length = 1
  let mut i = 0
  while i < words.length() {
    if words[i] != 0 {
      i = i + 1
      continue
    }
    let start = i
    while i < words.length() && words[i] == 0 {
      i = i + 1
    }
    if i - start > longest_length {
      longest_start = start
      longest_length = i - start
    }
  }
  let digits = "0123456789abcdef"
  let mut result = ""
  let mut cursor = 0
  while cursor < 8 {
    if cursor == longest_start {
      result = result + "::"
      cursor = cursor + longest_length
      continue
    }
    if !result.is_empty() && !result.has_suffix(":") {
      result = result + ":"
    }
    let mut value = words[cursor]
    let characters : Array[Char] = []
    while value > 0 {
      characters.push(digits.get_char(value & 15).unwrap())
      value = value >> 4
    }
    if characters.is_empty() {
      result = result + "0"
    } else {
      for j = characters.length() - 1; j >= 0; j = j - 1 {
        result = result + characters[j].to_string()
      }
    }
    cursor = cursor + 1
  }
  Ok(result)
}
