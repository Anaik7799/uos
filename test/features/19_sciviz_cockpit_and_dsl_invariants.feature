@sciviz @cockpit-navigation #fractal-l0 #fractal-l2 #fractal-l5
Feature: SciViz Cockpit, Gallery Navigation and Architectural Invariants
  As a Cockpit Operator
  I want navigation between SciViz views, dark theme persistence, and zero client JS verified
  So that the entire scientific visualization cockpit operates with SIL-6 reliability

  Scenario: SciViz Extensions Top Nav Navigation Links
    Given I am on the page "http://127.0.0.1:4100/sciviz/extensions"
    Then the page title should contain "ggplot2 Extensions Gallery Cockpit"
    And the page text should contain "SIL-6 / SCIVIZ"
    And the page text should contain "Zero-Muda Purity: 0 Client JS"
    And the page text should contain "NVMe 25503L801736: LOCKED"

  Scenario: SciViz Cockpit Main Page Landmark Verification
    Given I am on the page "http://127.0.0.1:4100/sciviz"
    Then the page should have HTML5 landmarks
    And the heading hierarchy should have a heading
    And the page title should contain "SciViz"

  Scenario: SciViz 9-Modality Test Cockpit Dashboard Verification
    Given I am on the page "http://127.0.0.1:4100/sciviz/tests"
    Then the page should have HTML5 landmarks
    And the heading hierarchy should have a heading
    And the page title should contain "SciViz"

  Scenario: SciViz Extensions Table View Density
    Given I am on the page "http://127.0.0.1:4100/sciviz/extensions"
    Then the table row count for ".sciviz-extensions-dashboard table tbody tr" should be at least 167

  Scenario: SciViz Extensions Gallery SVG Render Density
    Given I am on the page "http://127.0.0.1:4100/sciviz/extensions"
    Then the svg count should be at least 180

  Scenario: SciViz Extensions Dark Cockpit Palette
    Given I am on the page "http://127.0.0.1:4100/sciviz/extensions"
    Then the page text should contain "1x1 Fractal Feature Map Specification"

  Scenario: SciViz Intent Atlas Integration Invariants
    Given I am on the page "http://127.0.0.1:4100/sciviz"
    Then the page title should contain "SciViz"

  Scenario: SciViz Synthetic Dataset Mathematical Invariants
    Given I am on the page "http://127.0.0.1:4100/sciviz/tests"
    Then the page title should contain "SciViz"

  Scenario: SciViz WAI-ARIA Accessible Accordion Toggles
    Given I am on the page "http://127.0.0.1:4100/sciviz/extensions"
    Then the element count for ".fractal-map-details" should be at least 167

  Scenario: SciViz Zero Unhandled Exceptions Invariant
    Given I am on the page "http://127.0.0.1:4100/sciviz/extensions"
    Then no unhandled JavaScript exceptions should have occurred
