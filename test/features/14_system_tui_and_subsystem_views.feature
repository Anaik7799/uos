@subsystems @tui @telemetry @cockpit @resilience
Feature: Subsystem Views and Cybernetic Command Verification
  As an operations supervisor
  I want every subsystem view to render operational cards, health badges, and real-time state
  So that full observability into memory, breakers, and consensus is verified across all domains

  Scenario Outline: Verify Operational Cards on Subsystem View <name>
    Given I navigate to "http://127.0.0.1:4100<route>"
    Then the page text should contain "<text>"
    And the element count for ".card" should be at least 1
    And no unhandled JavaScript exceptions should have occurred

    Examples:
      | route         | text         | name |
      | /cockpit        | Cockpit      | Cockpit Command & Control |
      | /prajna         | Prajna       | Prajna Circuit Breakers |
      | /smriti         | Smriti       | Smriti SQLite WAL Store |
      | /zenoh          | Zenoh        | Zenoh Pub/Sub Mesh |
      | /mcp            | MCP          | Model Context Protocol Tools |
      | /podman         | Podman       | Supervised Podman Containers |
      | /substrate      | Substrate    | BEAM OTP 29 Substrate |
      | /metabolic      | Metabolic    | Metabolic Energy & Rate |
      | /kms            | KMS          | Key Management Service |
      | /immune         | Immune       | Immune Defense System |
      | /integrity      | Integrity    | 13D Coordinate Integrity |
      | /evolution      | Evolution    | Self-Adaptive Evolution |
      | /biomorphic     | Biomorphic   | Biomorphic Models |
      | /homeostasis    | Homeostasis  | Homeostasis Equilibrium |
      | /bicameral      | Bicameral    | Bicameral Consensus |
      | /singularity    | Singularity  | Attractor Singularity |
      | /bridge         | Bridge       | Multi-Agent Bridge |
      | /federation     | Federation   | Federated Cluster Sync |
      | /git            | Git          | Jujutsu Standalone View |
      | /health-grid    | Health       | System Health Matrix |
      | /holon          | Holon        | 158-Holon Census Map |
      | /verification   | Verification | Two-Key Verification Engine |

  Scenario Outline: Verify Health Status Badges on Subsystem View <name>
    Given I navigate to "http://127.0.0.1:4100<route>"
    Then the page should have HTML5 landmarks
    And the element count for ".badge, .status-healthy, .card-value" should be at least 1
    And no unhandled JavaScript exceptions should have occurred

    Examples:
      | route         | name |
      | /cockpit        | Cockpit Command & Control |
      | /prajna         | Prajna Circuit Breakers |
      | /smriti         | Smriti SQLite WAL Store |
      | /zenoh          | Zenoh Pub/Sub Mesh |
      | /mcp            | Model Context Protocol Tools |
      | /podman         | Supervised Podman Containers |
      | /substrate      | BEAM OTP 29 Substrate |
      | /metabolic      | Metabolic Energy & Rate |
      | /kms            | Key Management Service |
      | /immune         | Immune Defense System |
      | /integrity      | 13D Coordinate Integrity |
      | /evolution      | Self-Adaptive Evolution |
      | /biomorphic     | Biomorphic Models |
      | /homeostasis    | Homeostasis Equilibrium |
      | /bicameral      | Bicameral Consensus |
      | /singularity    | Attractor Singularity |
      | /bridge         | Multi-Agent Bridge |
      | /federation     | Federated Cluster Sync |
      | /git            | Jujutsu Standalone View |
      | /health-grid    | System Health Matrix |
      | /holon          | 158-Holon Census Map |
      | /verification   | Two-Key Verification Engine |
