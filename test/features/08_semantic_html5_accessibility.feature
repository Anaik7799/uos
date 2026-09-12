@semantics @a11y @landmarks @ui
Feature: Universal HTML5 Semantic Landmarks and WAI-ARIA 1.2
  As an accessibility and standards auditor
  I want every web page to provide proper HTML5 landmarks and heading structures
  So that assistive technology and automated agents can navigate predictably

  Scenario Outline: Semantic Landmarks on Core Pages
    Given I navigate to "<url>"
    Then the page should have HTML5 landmarks
    And the heading hierarchy should have an h1
    And the element count for "nav" should be at least 1
    And the element count for "main" should be at least 1
    And no unhandled JavaScript exceptions should have occurred

    Examples:
      | url                           |
      | http://127.0.0.1:4100/        |
      | http://127.0.0.1:4100/planning|
      | http://127.0.0.1:4100/cortex  |
      | http://127.0.0.1:4100/cockpit |
      | http://127.0.0.1:4100/links   |
