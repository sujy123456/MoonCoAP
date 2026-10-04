///|
async test "native UDP GET uses actual loopback datagrams" {
  @async.with_timeout(5000, async fn() {
    let server = @udp.UdpEndpoint::bind(
      "127.0.0.1:0",
      @udp.network_config(@coap.Config::default()),
    )
    defer server.close()
    let client = @udp.UdpEndpoint::bind(
      "127.0.0.1:0",
      @udp.network_config(@coap.Config::default()),
    )
    defer client.close()
    @async.with_task_group(async fn(group) {
      group.spawn_bg(async fn() {
        let mut served = false
        while !served {
          for event in server.step(100) {
            match event {
              @udp.Delivered(@coap.RequestReceived(incoming)) => {
                server.respond(
                  incoming.id,
                  @coap.Response::content(b"loopback"),
                )
                served = true
              }
              _ => ()
            }
          }
        }
      })
      let response = client.exchange(
        server.address(),
        @coap.Request::new(@coap.Get),
        3000,
      )
      assert_eq(response.payload, b"loopback")
      assert_eq(response.code.value, 69)
    })
  })
}

///|
async test "UDP separate response is acknowledged and retransmissions stop" {
  @async.with_timeout(5000, async fn() {
    let server = @udp.UdpEndpoint::bind(
      "127.0.0.1:0",
      @udp.network_config(@coap.Config::default()),
    )
    defer server.close()
    let client = @udp.UdpEndpoint::bind(
      "127.0.0.1:0",
      @udp.network_config(@coap.Config::default()),
    )
    defer client.close()
    @async.with_task_group(async fn(group) {
      group.spawn_bg(async fn() {
        let mut id : Int? = None
        while id is None {
          for event in server.step(100) {
            match event {
              @udp.Delivered(@coap.RequestReceived(incoming)) =>
                id = Some(incoming.id)
              _ => ()
            }
          }
        }
        server.acknowledge(id.unwrap())
        @async.sleep(20)
        server.respond(id.unwrap(), @coap.Response::content(b"separate"))
        while server.server_state()[0].response_phase != Some(@coap.Finished) {
          server.step(100) |> ignore
        }
      })
      let response = client.exchange(
        server.address(),
        @coap.Request::new(@coap.Get),
        3000,
      )
      assert_eq(response.msg_type, @coap.Confirmable)
      assert_eq(response.payload, b"separate")
    })
  })
}

///|
async test "timed-out exchange does not poison a subsequent request" {
  @async.with_timeout(5000, async fn() {
    let silent = @udp.UdpEndpoint::bind(
      "127.0.0.1:0",
      @udp.network_config(@coap.Config::default()),
    )
    defer silent.close()
    let server = @udp.UdpEndpoint::bind(
      "127.0.0.1:0",
      @udp.network_config(@coap.Config::default()),
    )
    defer server.close()
    let client = @udp.UdpEndpoint::bind(
      "127.0.0.1:0",
      @udp.network_config(@coap.Config::default()),
    )
    defer client.close()
    let failed = try {
      client.exchange(silent.address(), @coap.Request::new(@coap.Get), 20)
      |> ignore
      false
    } catch {
      _ => true
    }
    assert_true(failed)
    assert_eq(client.outstanding(), 0)
    assert_true(client.drain().is_empty())
    @async.with_task_group(async fn(group) {
      group.spawn_bg(async fn() {
        let mut done = false
        while !done {
          for event in server.step(100) {
            match event {
              @udp.Delivered(@coap.RequestReceived(request)) => {
                server.respond(request.id, @coap.Response::content(b"retry-ok"))
                done = true
              }
              _ => ()
            }
          }
        }
      })
      assert_eq(
        client.exchange(server.address(), @coap.Request::new(@coap.Get), 1000).payload,
        b"retry-ok",
      )
    })
  })
}
