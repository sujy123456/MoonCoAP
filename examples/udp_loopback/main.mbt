///|
async fn main {
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
        let mut done = false
        while !done {
          for event in server.step(100) {
            match event {
              @udp.Delivered(@coap.RequestReceived(incoming)) => {
                server.acknowledge(incoming.id)
                @async.sleep(10)
                server.respond(
                  incoming.id,
                  @coap.Response::content(b"native UDP"),
                )
                done = true
              }
              _ => ()
            }
          }
        }
        while server.server_state()[0].response_phase != Some(@coap.Finished) {
          server.step(100) |> ignore
        }
      })
      let response = client.exchange(
        server.address(),
        @coap.Request::new(@coap.Get),
        3000,
      )
      assert_eq(response.payload, b"native UDP")
      assert_eq(response.msg_type, @coap.Confirmable)
      println("Native UDP: separate response received and acknowledged")
    })
  })
}
