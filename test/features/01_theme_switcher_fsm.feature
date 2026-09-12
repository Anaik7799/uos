@fsm @theme @ui
Feature: Theme Switcher Finite State Machine
  As an operator using the C3I cybernetic dashboard
  I want to switch visual themes between Dark, Cyber Amber, Solaris White, and Deep Forest
  So that the interface adapts to environmental lighting conditions without reload

  Background:
    Given I navigate to "http://127.0.0.1:4100/"
    And the page title should contain "C3I — Dashboard"

  Scenario: Cyclic Theme Transition Dark -> Amber -> Solaris -> Forest -> Dark
    Given the theme should be default "dark"
    When I select theme "amber"
    Then the body class should contain "theme-amber"
    When I select theme "solaris"
    Then the body class should contain "theme-solaris"
    When I select theme "forest"
    Then the body class should contain "theme-forest"
    When I select theme "dark"
    Then the body should have no theme class
    And no unhandled JavaScript exceptions should have occurred

  Scenario: LocalStorage Theme Persistence
    Given I select theme "amber"
    And the body class should contain "theme-amber"
    When I evaluate script "localStorage.getItem('c3i-theme')"
    Then the script result should equal "amber"
    When I select theme "dark"
    And I evaluate script "localStorage.getItem('c3i-theme')"
    Then the script result should equal "dark"
    And no unhandled JavaScript exceptions should have occurred
