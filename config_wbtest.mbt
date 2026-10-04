///|
test "retry jitter bounds and invalid configuration are deterministic" {
  let config = Config::default()
  assert_eq(config.validate(), Ok(()))
  assert_eq(retry_interval(config, 0), Ok(2000L))
  assert_eq(retry_interval(config, 1000000), Ok(3000L))
  assert_true(retry_interval(config, -1) is Err(_))
  assert_true(({ ..config, nstart: 0, } : Config).validate() is Err(_))
  assert_true(({ ..config, max_mid_leases: 1, } : Config).validate() is Err(_))
  assert_true(
    ({ ..config, exchange_lifetime_ms: 1000L, } : Config).validate() is Err(_),
  )
  assert_true(deadline_after(9223372036854775807L, 1L) is Err(Clock(_)))
}
