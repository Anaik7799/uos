@sciviz @visual-parity #fractal-l2 #fractal-l3
Feature: SciViz All 167 Registered Extensions Card and Visual Parity
  As a SciViz Cockpit Operator
  I want every registered ggplot2 extension to render an interactive visual card
  So that users can inspect authors, categories, and live SVG previews

  Background:
    Given I am on the page "http://127.0.0.1:4100/sciviz/extensions"

  Scenario Outline: SciViz Extension <name> Visual Card and Category Parity
    Then I should see the sciviz card for "<name>" with author "<author>" and category "<category>"
    And the sciviz card for "<name>" should render a live SVG preview

    Examples:
      | name | author | category |
      | ggram | EvaMaeRey | Composite & Multi-Panel |
      | ggQQunif | rcorty | Uncertainty & Distribution |
      | ggupset | const-ae | Hierarchical Partition |
      | xmrr | Alex Zanidean | Quality Control & Time-Series |
      | gg3D | Daniel Acker | 3D & Perspective Projection |
      | ggQC | Kenith Grey | Quality Control & Time-Series |
      | ggdist | mjskay | Uncertainty & Distribution |
      | ggedit | yonicd | Introspection & Layer Editing |
      | ggpage | emilhvitfeldt | Typography & Text Repel |
      | ggpca | Yaoxiang Li | Dimensionality Reduction |
      | ggbreak | YuLab-SMU | Multi-Scale & Coordinates |
      | ggimg | statsmaths | Theming, Palettes & Aesthetics |
      | gganatogram | jespermaag | Bioinformatics & Genomics |
      | ggforce | thomasp85 | Theming, Palettes & Aesthetics |
      | ggalt | hrbrmstr | Statistical Diagnosis & Inference |
      | ggiraph | davidgohel | Introspection & Layer Editing |
      | ggmuller | robjohnnoble | Flow, Alluvial & Sankey |
      | ggstance | lionel- | Theming, Palettes & Aesthetics |
      | ggrepel | slowkow | Typography & Text Repel |
      | ggraph | thomasp85 | Bioinformatics & Genomics |
      | gginnards | aphalo | Introspection & Layer Editing |
      | ggpp | aphalo | Uncertainty & Distribution |
      | ggpmisc | aphalo | Uncertainty & Distribution |
      | geomnet | sctyner | Network & Graph Topology |
      | ggExtra | daattali | Uncertainty & Distribution |
      | ggfortify | terrytangyuan | Theming, Palettes & Aesthetics |
      | autoplotly | terrytangyuan | Introspection & Layer Editing |
      | gganimate | thomasp85 | Theming, Palettes & Aesthetics |
      | ggfx | thomasp85 | Pattern, Filter & Shaders |
      | plotROC | sachsmc | Statistical Diagnosis & Inference |
      | ggbump | davidsjoberg | Flow, Alluvial & Sankey |
      | ggthemes | jrnold | Theming, Palettes & Aesthetics |
      | ggspectra | aphalo | Uncertainty & Distribution |
      | ggstatsplot | IndrajeetPatil | Statistical Diagnosis & Inference |
      | ggnetwork | briatte | Network & Graph Topology |
      | ggtech | ricardo-bion | Theming, Palettes & Aesthetics |
      | ggradar | ricardo-bion | Spatial & Vector Field |
      | ggx | brandmaier | Theming, Palettes & Aesthetics |
      | ggTimeSeries | Ather-Energy | Quality Control & Time-Series |
      | ggtree | GuangchuangYu | Bioinformatics & Genomics |
      | ggseas | ellisp | Quality Control & Time-Series |
      | ggsci | road2stat | Theming, Palettes & Aesthetics |
      | ggmosaic | haleyjeppson | Hierarchical Partition |
      | survminer | kassambara | Bioinformatics & Genomics |
      | ggeasy | jonocarroll | Introspection & Layer Editing |
      | ggside | jtlandis | Composite & Multi-Panel |
      | ggcorrplot | kassambara | Dimensionality Reduction |
      | ggpubr | kassambara | Theming, Palettes & Aesthetics |
      | ggthemr | cttobin | Theming, Palettes & Aesthetics |
      | GGally | ggobi | Dimensionality Reduction |
      | ggseqlogo | omarwagih | Bioinformatics & Genomics |
      | ggChernoff | Selbosh | Theming, Palettes & Aesthetics |
      | ggridges | clauswilke | Uncertainty & Distribution |
      | lemon | stenfanedwards | Multi-Scale & Coordinates |
      | cowplot | clauswilke | Composite & Multi-Panel |
      | qqplotr | almeidaxan | Uncertainty & Distribution |
      | ggalluvial | corybrunson | Flow, Alluvial & Sankey |
      | patchwork | thomasp85 | Composite & Multi-Panel |
      | ggquiver | mitchelloharawild | Spatial & Vector Field |
      | ggsignif | const-ae and IndrajeetPatil | Statistical Diagnosis & Inference |
      | ggdag | malcolmbarrett | Network & Graph Topology |
      | ggformula | rpruim | Theming, Palettes & Aesthetics |
      | ggbeeswarm | Erik Clarke and Scott Sherrill-Mix | Uncertainty & Distribution |
      | ggperiodic | eliocamp | Multi-Scale & Coordinates |
      | ggpol | erocoar | Hierarchical Partition |
      | ggpirate | mikabr | Uncertainty & Distribution |
      | esquisse | dreamrs | Introspection & Layer Editing |
      | ggerror | iamyannc | Theming, Palettes & Aesthetics |
      | ggdark | nsgrantham | Theming, Palettes & Aesthetics |
      | sugrrants | earowang | Quality Control & Time-Series |
      | tvthemes | Ryo-N7 | Theming, Palettes & Aesthetics |
      | ggfittext | wilkox | Typography & Text Repel |
      | ggparty | martin-borkovec | Bioinformatics & Genomics |
      | gggenes | wilkox | Bioinformatics & Genomics |
      | gggenomes | thackl | Bioinformatics & Genomics |
      | treemapify | wilkox | Hierarchical Partition |
      | lindia | yeukyul | Statistical Diagnosis & Inference |
      | gghalves | erocoar | Uncertainty & Distribution |
      | ggrastr | vpetukhov | Pattern, Filter & Shaders |
      | ggpointdensity | LKremer | Uncertainty & Distribution |
      | ggsom | oldlipe | Dimensionality Reduction |
      | ggnewscale | eliocamp | Multi-Scale & Coordinates |
      | ggh4x | teunbrand | Multi-Scale & Coordinates |
      | ggarrow | teunbrand | Spatial & Vector Field |
      | legendry | teunbrand | Multi-Scale & Coordinates |
      | ggcharts | thomas-neitmann | Theming, Palettes & Aesthetics |
      | humapr | benskov | Bioinformatics & Genomics |
      | ggshadow | marcmenem | Pattern, Filter & Shaders |
      | ggseg | Athanasiamo | Bioinformatics & Genomics |
      | mdthemes | thomas-neitmann | Typography & Text Repel |
      | ggwordcloud | lepennec | Typography & Text Repel |
      | ggasym | jhrcook | Multi-Scale & Coordinates |
      | gglorenz | jjchern | Theming, Palettes & Aesthetics |
      | hrbrthemes | hrbrmstr | Typography & Text Repel |
      | ggpattern | coolbutuseless | Pattern, Filter & Shaders |
      | ggtext | Claus Wilke | Typography & Text Repel |
      | calendR | R-CoderDotCom | Quality Control & Time-Series |
      | ggip | davidchall | Theming, Palettes & Aesthetics |
      | gglm | graysonwhite | Statistical Diagnosis & Inference |
      | econocharts | R-CoderDotCom | Theming, Palettes & Aesthetics |
      | ComplexUpset | krassowski | Hierarchical Partition |
      | ggchromatic | teunbrand | Theming, Palettes & Aesthetics |
      | ggheatmap | XiaoLuo-boy | Theming, Palettes & Aesthetics |
      | see | easystats | Uncertainty & Distribution |
      | directlabels | tdhock | Typography & Text Repel |
      | ggHoriPlot | rivasiker | Quality Control & Time-Series |
      | ggtrace | sheridar | Introspection & Layer Editing |
      | ggESDA | kiangkiangkiang | Theming, Palettes & Aesthetics |
      | geomtextpath | AllanCameron | Typography & Text Repel |
      | ggdensity | jamesotto852 | Uncertainty & Distribution |
      | ggtranscript | dzhang32 | Bioinformatics & Genomics |
      | piecepackr | trevorld | Theming, Palettes & Aesthetics |
      | oblicubes | trevorld | 3D & Perspective Projection |
      | ggDoubleHeat | PursuitOfDataScience | Theming, Palettes & Aesthetics |
      | nflplotR | mrcaseb | Theming, Palettes & Aesthetics |
      | ggbraid | nsgrantham | Flow, Alluvial & Sankey |
      | ggblanket | davidhodge931 | Theming, Palettes & Aesthetics |
      | ggpie | showteeth | Hierarchical Partition |
      | ggstar | xiangpin | Introspection & Layer Editing |
      | ggarchery | mdhall272 | Spatial & Vector Field |
      | tidyterra | dieghernan | Spatial & Vector Field |
      | ggseqplot | maraab23 | Theming, Palettes & Aesthetics |
      | ggsurvfit | ddsjoberg | Bioinformatics & Genomics |
      | ggsector | yanpd01 | Spatial & Vector Field |
      | ggterror | mivalek | Theming, Palettes & Aesthetics |
      | ggragged | mikmart | Composite & Multi-Panel |
      | ggmapinset | arcresu | Spatial & Vector Field |
      | ggmagnify | hughjonesd | Multi-Scale & Coordinates |
      | ggblend | mjskay | Pattern, Filter & Shaders |
      | ggflowchart | nrennie | Network & Graph Topology |
      | ggrain | njudd | Uncertainty & Distribution |
      | ggoutlierscatterplot | lukastay | Statistical Diagnosis & Inference |
      | ggautothemes | lukastay | Theming, Palettes & Aesthetics |
      | AMR | msberends | Bioinformatics & Genomics |
      | ichimoku | shikokuchuo | Quality Control & Time-Series |
      | eheat | Yunuuuu | Theming, Palettes & Aesthetics |
      | ggstats | larmarange | Statistical Diagnosis & Inference |
      | ggfoundry | cgoo4 | Theming, Palettes & Aesthetics |
      | ggalign | Yunuuuu | Multi-Scale & Coordinates |
      | ggreveal | weverthonmachado | Introspection & Layer Editing |
      | geofacet | hafen | Spatial & Vector Field |
      | tidyplots | jbengler | Theming, Palettes & Aesthetics |
      | rphylopic | willgearty | Bioinformatics & Genomics |
      | deeptime | willgearty | Quality Control & Time-Series |
      | ggpcp | heike | Dimensionality Reduction |
      | ggvolcano | Yaoxiang Li | Bioinformatics & Genomics |
      | ggfootball | aymennasri | Statistical Diagnosis & Inference |
      | ggfields | pepijn-devries | Spatial & Vector Field |
      | ggsankeyfier | pepijn-devries | Network & Graph Topology |
      | ggpath | mrcaseb | Theming, Palettes & Aesthetics |
      | gglinedensity | hrryt | Uncertainty & Distribution |
      | ggsurveillance | ndevln | Quality Control & Time-Series |
      | gguapo | eliansoutu | Theming, Palettes & Aesthetics |
      | ggDNAvis | ejade42 | Bioinformatics & Genomics |
      | ggdibbler | harriet-mason | Uncertainty & Distribution |
      | ggprop.test | EvaMaeRey | Statistical Diagnosis & Inference |
      | ggsky | uskovgs | Spatial & Vector Field |
      | ggpop | jurjoroa | Hierarchical Partition |
      | ggpointless | flrd | Statistical Diagnosis & Inference |
      | ggincerta | maggiexma | Uncertainty & Distribution |
      | ggRandomForests | ehrlinger | Bioinformatics & Genomics |
      | ggcube | matthewkling | 3D & Perspective Projection |
      | ggtaichi | PursuitOfDataScience | Theming, Palettes & Aesthetics |
      | ggchord2 | nrennie | Network & Graph Topology |
      | ggtintshade | wkumler | Pattern, Filter & Shaders |
      | glydraw | fubin1999 | Typography & Text Repel |
      | ggmultiglyph | aravind-j | Theming, Palettes & Aesthetics |
