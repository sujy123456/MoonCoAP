///|
test "MID wraparound skips active leases and peers have separate scopes" {
  let allocator = Allocator::new({ ..Config::default(), initial_mid: 65535, }).unwrap()
  assert_eq(allocator.reserve("a", 0, 0L), Ok(()))
  assert_eq(allocator.allocate_mid("a", 0L), Ok(65535))
  assert_eq(allocator.allocate_mid("a", 0L), Ok(1))
  assert_eq(allocator.reserve("b", 0, 0L), Ok(()))
  assert_true(allocator.reserve("a", 0, 1L) is Err(Conflict(_)))
  assert_eq(allocator.collect(247000L), Ok(4))
  assert_eq(allocator.active_leases(), 0)
  assert_true(allocator.collect(0L) is Err(Clock(_)))
}

///|
test "finite lease storage applies backpressure rather than early reuse" {
  let allocator = Allocator::new({
    ..Config::default(),
    max_exchanges: 1,
    max_queue: 0,
    max_mid_leases: 1,
  }).unwrap()
  assert_eq(allocator.allocate_mid("a", 0L), Ok(0))
  assert_true(allocator.allocate_mid("a", 1L) is Err(Capacity(_)))
  assert_eq(allocator.remaining_capacity(), 0)
  assert_true(allocator.allocate_mid("a", 247000L) is Ok(_))
  let first = allocator.allocate_token().unwrap()
  let second = allocator.allocate_token().unwrap()
  assert_true(first != second)
  assert_eq(first.length(), 8)
}
