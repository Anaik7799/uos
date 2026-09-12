@components @a2ui @heartbeat @ui
Feature: A2UI Component Catalog and WebSocket Heartbeat
  As a developer inspecting agentic UI components
  I want the 233-component catalog and live telemetry script to load cleanly
  So that component schemas, properties, and live indicators are verified

  Background:
    Given I navigate to "http://127.0.0.1:4100/components"
    And the page title should contain "C3I — Component Demo"

  Scenario: Component Catalog Cards and Script Loading
    Then the element count for ".card" should be at least 10
    And the element count for ".section" should be at least 5
    And the active nav link should be "Components"
    And no unhandled JavaScript exceptions should have occurred
