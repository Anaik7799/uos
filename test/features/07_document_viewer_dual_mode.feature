@docs @markdown @citations @ui
Feature: Document Viewer and Literature Verification
  As an operator reading architectural specifications
  I want canonical markdown documents to be served with verification badges and citations
  So that academic foundation and hardware storage interlocks are verifiable

  Background:
    Given I navigate to "http://127.0.0.1:4100/docs/design/20260912-1115-uos-state-of-the-art-web-zk-wiki-km-synthesis-specification.md"
    And the page title should contain "C3I — Doc: 20260912-1115-uos-state-of-the-art-web-zk-wiki-km-synthesis-specification.md"

  Scenario: Academic Literature Citations and Storage Badge
    Then the preformatted text length should exceed 10000
    And the preformatted text should contain "Brin"
    And the preformatted text should contain "Kleinberg"
    And the element ".badge-storage" should contain "NVMe"
    And no unhandled JavaScript exceptions should have occurred
