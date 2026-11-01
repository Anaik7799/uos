// PRIVATE TEST BUILD ONLY. Appended to exact production owner bytes. Never a
// production export, trust constructor, environment flag or admission path.
pub fn fixture_start(
  c: ConfigurationData,
  admit: fn() -> Result(Nil, String),
  read_authority: fn() -> Result(Nil, String),
  quiescence: fn(String) -> Result(Nil, String),
  effect: fn(String) -> store.RawExchange,
) -> actor.StartResult(Subject(Message)) {
  start_internal(
    c,
    Adapter(
      admit,
      read_authority,
      fn(stage) {
        quiescence(case stage {
          Startup -> "startup"
          BeforePending -> "before_pending"
          PendingCreatedByThisOwner -> "pending_created_by_this_owner"
          Reconciliation -> "reconciliation"
        })
      },
      effect,
    ),
  )
}
