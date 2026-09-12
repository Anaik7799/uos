@fsm @hmi @cockpit @ui
Feature: HMI Test Cycle Driver
  As an operator verifying human-machine interface responsiveness
  I want to trigger the automatic HMI state cycle
  So that cockpit modes cycle through dark, dim, normal, bright, and emergency states

  Background:
    Given I navigate to "http://127.0.0.1:4100/"
    And the page title should contain "C3I — Dashboard"

  Scenario: Trigger and Stop Test Cycle
    Given the test cycle trigger function "triggerTestCycle" is defined
    When I trigger the test cycle
    Then the test cycle should be active
    When I trigger the test cycle
    Then the body class should contain "cockpit-normal"
    And no unhandled JavaScript exceptions should have occurred
