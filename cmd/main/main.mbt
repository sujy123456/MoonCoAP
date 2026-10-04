///|
fn main raise {
  let message = @coap.Message::new(
    @coap.Confirmable,
    @coap.Code::request(@coap.Get),
    123,
  )
  message.options = [@coap.option_text(11, "status")]
  let bytes = @coap.encode(message, @coap.Limits::default()).unwrap()
  let decoded = @coap.decode(bytes, @coap.Limits::default()).unwrap()
  assert_eq(decoded, message)
  println("MoonCoAP GET /status bytes=" + @coap.bytes_to_hex(bytes))
}
