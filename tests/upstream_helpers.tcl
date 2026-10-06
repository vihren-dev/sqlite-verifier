# Run with the source-pinned testfixture to check the helper semantics we reproduce.
sqlite3 db :memory:
foreach {helper sql expected} {
  exists {SELECT 42} 1
  exists {SELECT 42 WHERE 0} 0
  onecolumn {SELECT 42,99 UNION ALL SELECT 7,8} 42
  onecolumn {SELECT NULL} {}
  onecolumn {SELECT 42 WHERE 0} {}
} {
  set actual [db $helper $sql]
  if {$actual ne $expected} {error "$helper: expected <$expected>, got <$actual>"}
}
puts HELPER_SEMANTICS_OK
exit
