@sciviz @categories-and-modalities #fractal-l2 #fractal-l7 #fractal-l8
Feature: SciViz 16 Taxonomic Categories and 15 Modality Use Cases
  As a SciViz Systems Engineer
  I want all 16 taxonomic categories and 15 formal test use cases verified
  So that the 9-modality verification suite provides complete mathematical coverage

  Background:
    Given I am on the page "http://127.0.0.1:4100/sciviz/extensions"

  Scenario Outline: SciViz Category Distribution and Interactive Filter Pill <category>
    Then the sciviz category pill for "<category>" should display count "<expected_min>"
    And the element count for ".sciviz-extensions-dashboard table tbody tr" should be at least 167

    Examples:
      | category | expected_min |
      | Uncertainty & Distribution | 18 |
      | Network & Graph Topology | 12 |
      | Flow, Alluvial & Sankey | 6 |
      | Hierarchical Partition | 8 |
      | Spatial & Vector Field | 15 |
      | Quality Control & Time-Series | 11 |
      | Bioinformatics & Genomics | 19 |
      | Typography & Text Repel | 9 |
      | Multi-Scale & Coordinates | 7 |
      | Composite & Multi-Panel | 10 |
      | 3D & Perspective Projection | 6 |
      | Statistical Diagnosis & Inference | 17 |
      | Pattern, Filter & Shaders | 5 |
      | Dimensionality Reduction | 7 |
      | Theming, Palettes & Aesthetics | 12 |
      | Introspection & Layer Editing | 5 |

  Scenario Outline: SciViz 15 Formal Feature Use Cases across 9 Modalities
    Then the sciviz formal use case "<use_case_id>" for "<extension_name>" should have modality "<modality>"
    And the sciviz formal use case "<use_case_id>" should have passed verification

    Examples:
      | use_case_id | extension_name | modality |
      | UC-EXT-01 | ggdist / ggridges | TDD Testing |
      | UC-EXT-02 | ggraph / geomnet | Component Testing |
      | UC-EXT-03 | ggalluvial / ggsankeyfier | Component Testing |
      | UC-EXT-04 | treemapify | Component Testing |
      | UC-EXT-05 | ComplexUpset / ggupset | UI Elements Testing |
      | UC-EXT-06 | ggquiver / ggfields | UI Elements Testing |
      | UC-EXT-07 | ggQC / xmrr | System Testing |
      | UC-EXT-08 | survminer / ggsurvfit | System Testing |
      | UC-EXT-09 | ggtree / ggdendro | UI Elements Testing |
      | UC-EXT-10 | geomtextpath / ggrepel | UI Elements Testing |
      | UC-EXT-11 | ggHoriPlot | Component Testing |
      | UC-EXT-12 | patchwork / cowplot | UI Elements Testing |
      | UC-EXT-13 | ggnewscale | Property Testing |
      | UC-EXT-14 | ggfx / ggblend | Fuzz Testing |
      | UC-EXT-15 | gginnards | Chaos Testing |
