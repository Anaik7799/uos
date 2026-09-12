@links @analysis @centrality @ui
Feature: Multi-Sink Endpoint Collator and Spectral Centrality
  As an operator reviewing system surface area
  I want all system links, wiki pages, ZK decision records, and API endpoints collated on one page
  So that PageRank authorities and Kleinberg HITS hubs are transparently observable

  Background:
    Given I navigate to "http://127.0.0.1:4100/links"
    And the page title should contain "Universal Link Tracker & Verifier"

  Scenario: Spectral Centrality and Endpoint Verification
    Then the page text should contain "Spectral Graph Centrality"
    And the page text should contain "PageRank Authorities"
    And the page text should contain "Kleinberg HITS Top Hubs"
    And the table row count for "tbody tr" should be at least 44
    And no unhandled JavaScript exceptions should have occurred
