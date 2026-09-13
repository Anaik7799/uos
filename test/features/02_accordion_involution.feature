@fsm @accordion @checklist @ui
Feature: Interactive Disclosure and Accordion Involution
  As an SRE operator auditing system conformance
  I want the verification checklist accordion to toggle open and closed cleanly
  So that collapsible audit domains satisfy the mathematical involution property f(f(s)) = s

  Background:
    Given I navigate to "http://127.0.0.1:4100/checklist"
    And the page title should contain "Comprehensive Verification Checklist"

  Scenario: Verification Checklist Accordion Involution
    Given the details "details" exists on the page
    And I record the initial details open state for "details"
    When I click the summary for "details"
    Then the details "details" open state should be toggled
    When I click the summary for "details"
    Then the details "details" open state should be restored to initial
    And no unhandled JavaScript exceptions should have occurred

  Scenario Outline: Universal Accordion Involution Across System Pages
    Given I navigate to "<url>"
    And the page title should contain "<title_fragment>"
    And the details "details" exists on the page
    And I record the initial details open state for "details"
    When I click the summary for "details"
    Then the details "details" open state should be toggled
    When I click the summary for "details"
    Then the details "details" open state should be restored to initial
    And no unhandled JavaScript exceptions should have occurred

    Examples:
      | url                                    | title_fragment                       |
      | http://127.0.0.1:4100/links            | Universal Link Tracker & Verifier    |
      | http://127.0.0.1:4100/sciviz/extensions| Extensions                           |
      | http://127.0.0.1:4100/checklist        | Comprehensive Verification Checklist |

