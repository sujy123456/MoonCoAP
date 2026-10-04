///|
async fn main {
  let client = @udp.UdpEndpoint::bind(
    "127.0.0.1:0",
    @udp.network_config(@coap.Config::default()),
  )
  defer client.close()
  let request : @coap.Request = {
    ..@coap.Request::new(@coap.Get),
    options: [@coap.option_text(11, "status")],
  }
  let response = client.exchange("127.0.0.1:56831", request, 5000)
  assert_eq(response.payload, b"python-ready")
  assert_eq(response.code.value, 69)
  println("MoonBit client -> aiocoap server: 2.05 python-ready")
}
