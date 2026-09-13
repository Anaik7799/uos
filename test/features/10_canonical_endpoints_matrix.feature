@matrix @endpoints @coverage @regression
Feature: Canonical System Endpoints Matrix Verification
  As a system reliability engineer
  I want to verify that all 55 canonical system routes and endpoints are active and accessible
  So that complete surface area navigation and zero-muda availability invariants are verified

  Scenario Outline: Verify Semantic Landmarks and DOM on UI Page <path>
    Given I navigate to "http://127.0.0.1:4100<path>"
    Then the page should have HTML5 landmarks
    And the heading hierarchy should have a heading
    And no unhandled JavaScript exceptions should have occurred

    Examples:
      | path | name |
      | /                              | Dashboard |
      | /dashboard                     | Dashboard Alternate |
      | /planning                      | Planning Cockpit |
      | /planning-dashboard            | Planning Dashboard |
      | /cortex                        | Cortex Cognitive Map |
      | /cockpit                       | Cockpit Overview |
      | /components                    | Component Catalog |
      | /links                         | Universal Link Tracker |
      | /link-tracker                  | Link Tracker Alternate |
      | /checklist                     | Verification Checklist |
      | /sciviz                        | SciViz Cockpit |
      | /sciviz/extensions             | Extensions Gallery |
      | /sciviz/tests                  | Comprehensive Test Modalities |
      | /wiki                          | Hermes Wiki |
      | /zk                            | Zettelkasten MOC |
      | /testing                       | Testing Suite |
      | /podman                        | Podman Containers |
      | /substrate                     | Substrate Status |
      | /metabolic                     | Metabolic Status |
      | /kms                           | KMS Catalog |
      | /knowledge                     | Knowledge Store |
      | /telemetry                     | Telemetry Bus |
      | /immune                        | Immune Defense |
      | /integrity                     | System Integrity |
      | /evolution                     | Evolutionary Engine |
      | /biomorphic                    | Biomorphic Models |
      | /homeostasis                   | Homeostasis Loop |
      | /bicameral                     | Bicameral Consensus |
      | /singularity                   | Singularity Event |
      | /database                      | Database Ledger |
      | /config                        | Configuration Map |
      | /bridge                        | Bridge Protocol |
      | /federation                    | Federation Node |
      | /git                           | Git Jujutsu View |
      | /health-grid                   | Health Grid |
      | /holon                         | Holon Hierarchy |
      | /prajna                        | Prajna Breakers |
      | /verification                  | Verification Engine |

  Scenario Outline: Verify JSON Payload on API Endpoint <path>
    Given I navigate to "http://127.0.0.1:4100<path>"
    Then the page text should contain "{"
    And no unhandled JavaScript exceptions should have occurred

    Examples:
      | path | name |
      | /api/health                    | API Health Check |
      | /api/v1/dashboard              | API Dashboard JSON |
      | /api/v1/links/status           | API Links Status |
      | /api/v1/pages                  | API Pages Directory |
      | /api/v1/reload                 | API Reload State |
      | /api/v1/zenoh                  | API Zenoh Status |
      | /api/v1/verification           | API Verification Metrics |
      | /api/cockpit/nodes             | API Cockpit Nodes |
      | /api/substrate/status          | API Substrate Status |
      | /api/metabolic/status          | API Metabolic Status |
      | /api/podman/containers         | API Podman Containers |
      | /api/mcp/status                | API MCP Tools |
      | /api/kms/catalog               | API KMS Catalog |
      | /api/telemetry/status          | API Telemetry Health |
      | /api/v1/integrity              | API Integrity Log |
      | /api/v1/evolution              | API Evolution State |
      | /api/v1/biomorphic             | API Biomorphic Synthesis |
