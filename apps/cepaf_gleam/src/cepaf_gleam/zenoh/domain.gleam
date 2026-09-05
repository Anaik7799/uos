pub type ZenohSession

pub type ZenohSubscription

pub type ZenohMessage {
  ZenohMessage(key: String, payload: BitArray, timestamp: Int)
}

pub type ConnectionStatus {
  Connected
  Disconnected
  Connecting
  Error(String)
}

pub type LifecycleState {
  Uninitialized
  Starting(start_time: Int)
  Running(connected_at: Int)
  Reconnecting(attempt: Int, last_error: String, start_time: Int)
  Stopped(reason: String, stopped_at: Int)
}

pub type LifecycleEvent {
  Initializing(config: Config)
  SessionConnected(session_id: String)
  SessionDisconnected(reason: String)
  HealthCheck(stats: ZenohHealth)
  ReconnectFailed(attempts: Int, error: String)
  Shutdown(graceful: Bool)
}

pub type ZenohHealth {
  ZenohHealth(
    status: ConnectionStatus,
    session_id: String,
    connected_at: Int,
    last_heartbeat: Int,
    reconnect_count: Int,
    messages_published: Int,
    messages_received: Int,
    error_count: Int,
  )
}

pub fn empty_health() -> ZenohHealth {
  ZenohHealth(
    status: Disconnected,
    session_id: "",
    connected_at: 0,
    last_heartbeat: 0,
    reconnect_count: 0,
    messages_published: 0,
    messages_received: 0,
    error_count: 0,
  )
}

pub type Config {
  Config(router_endpoint: String, mode: String, connect_timeout_ms: Int)
}

pub fn default_config() -> Config {
  Config(
    router_endpoint: "tcp/localhost:7447",
    mode: "client",
    connect_timeout_ms: 5000,
  )
}
