@sciviz @extensions @gallery @browser @sil6
Feature: SciViz ggplot2 Extensions Gallery & 9-Modality Test Verification
  As an operator in the UOS C3I ecosystem
  I want to verify that all 167 ggplot2 extensions and 9-modality tests render pure SVG displays
  So that scientific visualization adheres to SIL-6 Zero-Muda standards with zero client-side JavaScript

  Background:
    Given I navigate to "http://127.0.0.1:4100/sciviz"
    And the page title should contain "SciViz"

  Scenario: Verify SciViz 9-Modality Test Cockpit WebUI Display
    Given I navigate to "http://127.0.0.1:4100/sciviz/tests"
    Then the page title should contain "SciViz"
    And the page text should contain "9-Modality"
    And the heading hierarchy should have an h1
    And the page should have HTML5 landmarks
    And the svg count should be at least 15
    And no unhandled JavaScript exceptions should have occurred

  Scenario: Verify SciViz ggplot2 Extensions Gallery WebUI Display
    Given I navigate to "http://127.0.0.1:4100/sciviz/extensions"
    Then the page title should contain "Extensions"
    And the page text should contain "167"
    And the heading hierarchy should have an h1
    And the page should have HTML5 landmarks
    And the svg count should be at least 180
    And no unhandled JavaScript exceptions should have occurred

  Scenario: Verify SciViz Graphical Elements & Synthetic Data Envelopes
    Given I navigate to "http://127.0.0.1:4100/sciviz/extensions"
    Then the page text should contain "Uncertainty"
    And the page text should contain "Topology"
    And the page text should contain "Survival"
    And the page text should contain "Median"
    And the page text should contain "Code Example"
    And the svg count should be at least 180
    And the element count for "svg path" should be at least 10
    And the element count for "svg text" should be at least 20
    And no unhandled JavaScript exceptions should have occurred

  Scenario: Verify 1x1 Fractal Feature Map Specification & Features Offered Across All 167 Extensions
    Given I navigate to "http://127.0.0.1:4100/sciviz/extensions"
    Then the page text should contain "Features Offered"
    And the page text should contain "1x1 Fractal Feature Map Specification"
    And the page text should contain "Technical Aspects"
    And the page text should contain "Functional Aspects"
    And the page text should contain "UI/UX Aspects"
    And the element count for ".fractal-map-details" should be at least 167
    And no unhandled JavaScript exceptions should have occurred

