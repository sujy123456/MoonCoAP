///|
fn earlier(current : Int64?, candidate : Int64) -> Int64? {
  match current {
    None => Some(candidate)
    Some(value) => Some(if candidate < value { candidate } else { value })
  }
}

///|
fn Endpoint::expire_clients(self : Endpoint, now : Int64) -> Unit {
  for exchange in self.clients {
    let transmit_expired = exchange.phase == Sending &&
      exchange.message.msg_type == Confirmable &&
      now >= exchange.transmit_deadline
    if now >= exchange.deadline || transmit_expired {
      exchange.phase = Finished
      self.outbox.push(Failed(exchange.id, TimedOut))
    }
  }
  self.clients = self.clients.filter(fn(exchange) { exchange.phase != Finished })
}

///|
pub fn Endpoint::poll(self : Endpoint, now : Int64) -> Result[Unit, Failure] {
  match self.observe_time(now) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  match
    self.ensure_actions(
      self.config.max_exchanges * 2 + self.config.max_dedup + 4,
    ) {
    Err(error) => return Err(error)
    Ok(_) => ()
  }
  self.expire_clients(now)
  for exchange in self.clients {
    if exchange.phase != Sending || exchange.message.msg_type != Confirmable {
      continue
    }
    match exchange.next_retry {
      None => ()
      Some(deadline) => {
        if now < deadline {
          continue
        }
        if exchange.retransmissions >= self.config.max_retransmit {
          exchange.phase = Finished
          self.outbox.push(Failed(exchange.id, TimedOut))
        } else {
          exchange.retransmissions = exchange.retransmissions + 1
          exchange.last_sent_at = now
          exchange.interval = exchange.interval * 2L
          exchange.next_retry = Some(now + exchange.interval)
          self.outbox.push(SendDatagram(exchange.peer, exchange.wire))
        }
      }
    }
  }
  self.clients = self.clients.filter(fn(exchange) { exchange.phase != Finished })
  self.reply_receipts = self.reply_receipts.filter(fn(receipt) {
    receipt.expires_at > now
  })
  self.poll_server_responses(now)
  self.expire_server_records(now)
  self.promote_clients(now)
  Ok(())
}

///|
pub fn Endpoint::next_deadline(self : Endpoint) -> Int64? {
  let mut result = self.allocator.next_expiry()
  for exchange in self.clients {
    result = earlier(result, exchange.deadline)
    if exchange.phase == Sending && exchange.message.msg_type == Confirmable {
      result = earlier(result, exchange.transmit_deadline)
    }
    match exchange.next_retry {
      None => ()
      Some(time) => result = earlier(result, time)
    }
  }
  for receipt in self.reply_receipts {
    result = earlier(result, receipt.expires_at)
  }
  for exchange in self.servers {
    if exchange.expires_at > self.last_now {
      result = earlier(result, exchange.expires_at)
    }
    match exchange.transmission {
      Some(response) =>
        if response.phase != Finished {
          result = earlier(result, response.deadline)
          match response.next_retry {
            Some(time) => result = earlier(result, time)
            None => ()
          }
        }
      None => ()
    }
  }
  result
}
