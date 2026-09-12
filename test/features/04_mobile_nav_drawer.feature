@fsm @navigation @mobile @ui
Feature: Responsive Mobile Navigation Hamburger Drawer
  As a mobile operator monitoring the C3I mesh on small screens
  I want to toggle the navigation drawer using the hamburger button
  So that navigation links expand and collapse predictably

  Background:
    Given I navigate to "http://127.0.0.1:4100/"
    And the page title should contain "C3I — Dashboard"

  Scenario: Hamburger Menu Toggle
    Given the mobile hamburger button ".nav-hamburger" exists
    When I click the element ".nav-hamburger"
    Then the element ".nav-groups" should have class "nav-open"
    And the element ".nav-top" should have class "nav-open"
    When I click the element ".nav-hamburger"
    Then the element ".nav-groups" should not have class "nav-open"
    And the element ".nav-top" should not have class "nav-open"
    And no unhandled JavaScript exceptions should have occurred
