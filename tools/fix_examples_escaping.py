with open("apps/cepaf_gleam/src/cepaf_gleam/sciviz/extension_examples.gleam") as f:
    text = f.read()

import re

with open("apps/cepaf_gleam/src/cepaf_gleam/sciviz/extension_catalog.gleam") as f:
    cat_text = f.read()

pattern = re.compile(r"""ExtensionMetadata\(\s*
    name:\s*"([^"]+)",\s*
    url:\s*"([^"]+)",\s*
    author:\s*"([^"]+)",\s*
    description:\s*"([^"]*)",\s*
    tags:\s*\[(.*?)\]\s*,\s*
    category:\s*([A-Za-z0-9_]+)""", re.DOTALL | re.VERBOSE)

matches = pattern.findall(cat_text)

cat_geom_map = {
    "BioinformaticsGenomics": "geom_tree() + geom_tiplab(size = 3.5, color = '#38bdf8') + theme_tree2()",
    "UncertaintyDistribution": "stat_halfeye(aes(fill = factor(group)), alpha = 0.8) + stat_interval()",
    "NetworkGraphTopology": "geom_edge_link(color = '#475569', alpha = 0.6) + geom_node_point(aes(size = centrality, color = cluster))",
    "FlowAlluvialSankey": "geom_alluvium(aes(fill = cohort), alpha = 0.75) + geom_stratum(fill = '#0f172a', color = '#38bdf8')",
    "SpatialVectorField": "geom_sf(aes(fill = elevation)) + geom_quiver(aes(u = vx, v = vy), color = '#38bdf8')",
    "QualityControlTimeSeries": "stat_qc(aes(x = time_step, y = metric), method = 'XmR') + stat_qc_violations(color = '#f43f5e')",
    "HierarchicalPartition": "geom_treemap(aes(area = weight, fill = category)) + geom_treemap_text(aes(label = category), color = '#ffffff')",
    "TypographyTextRepel": "geom_text_repel(aes(label = symbol), box.padding = 0.5, point.padding = 0.3, max.overlaps = 20)",
    "MultiScaleCoordinate": "coord_tern() + geom_point(aes(a = comp_a, b = comp_b, c = comp_c), size = 2.5, color = '#38bdf8')",
    "CompositeMultiPanel": "p1 + p2 / (p3 + p4) + plot_layout(guides = 'collect') + plot_annotation(tag_levels = 'A')",
    "ThreeDimensionalProjection": "stat_3d(aes(theta = 45, phi = 30), color = '#38bdf8', alpha = 0.7)",
    "StatisticalDiagnosisInference": "geom_point(alpha = 0.6) + stat_smooth(method = 'loess') + stat_regline_equation(label.x = 2.5, color = '#34d399')",
    "PatternFilterShader": "geom_col_pattern(aes(fill = condition), pattern = 'stripe', pattern_fill = '#38bdf8', pattern_density = 0.35)",
    "DimensionalityReduction": "geom_point(aes(color = cluster), size = 2.5, alpha = 0.8) + stat_ellipse(level = 0.95, linetype = 'dashed')",
    "ThemingPaletteAesthetic": "scale_color_viridis_d(option = 'plasma') + theme_minimal(base_size = 12) + theme(panel.background = element_rect(fill = '#020617'))",
    "IntrospectionLayerEditing": "gghighlight(p_val < 0.01 & abs(log2fc) > 1.5, unhighlighted_colour = '#334155', use_direct_label = TRUE)"
}

code_cases = []
for name, url, author, desc, tags_str, cat in matches:
    geom_call = cat_geom_map.get(cat, "geom_point(size = 2, color = '#38bdf8')")
    
    if name == "ggram":
        geom_call = 'ggram(\\"Cars Analysis Pipeline\\", style = \\"notebook\\")'
    elif name == "ggupset":
        geom_call = "scale_x_upset(order_by = 'degree') + geom_combmatrix(fill = '#38bdf8')"
    elif name == "ggrepel":
        geom_call = "geom_text_repel(aes(label = gene_id), box.padding = 0.4, color = '#f8fafc')"
    elif name == "ggdist":
        geom_call = "stat_slabinterval(aes(x = treatment, y = response), fill = '#38bdf8', alpha = 0.7)"
    elif name == "survminer":
        geom_call = "ggsurvplot(fit, data = cohort_data, pval = TRUE, conf.int = TRUE, risk.table = TRUE)"
    elif name == "patchwork":
        geom_call = "(p_scatter | p_density) / p_table + plot_layout(heights = c(2, 1))"
    elif name == "cowplot":
        geom_call = "plot_grid(p1, p2, labels = c('A', 'B'), label_size = 12, ncol = 2)"
    elif name == "gganimate":
        geom_call = "transition_time(time_epoch) + ease_aes('linear') + shadow_wake(wake_length = 0.1)"
    elif name == "ggbreak":
        geom_call = "scale_y_break(c(100, 500), scales = 0.5) + theme_minimal()"
    elif name == "plotROC":
        geom_call = "geom_roc(aes(m = prediction_score, d = ground_truth), n.cuts = 0) + style_roc()"
    elif name == "ggbump":
        geom_call = "geom_bump(aes(x = year, y = rank, color = entity), size = 2, smooth = 8)"
    elif name == "treemapify":
        geom_call = "geom_treemap(aes(area = count, fill = category)) + geom_treemap_text(aes(label = category))"
    elif name == "ggfx":
        geom_call = "with_blur(geom_point(aes(color = group), size = 3), sigma = 2)"

    clean_code = (
        f'library(ggplot2)\\n'
        f'library({name})\\n'
        f'# Canonical empirical dataset\\n'
        f'df <- data.frame(\\n'
        f'  obs_id = seq_len(100),\\n'
        f'  dim_x = rnorm(100, mean = 20, sd = 3.5),\\n'
        f'  dim_y = rpois(100, lambda = 15),\\n'
        f'  condition = factor(rep(c(\\"Alpha\\", \\"Beta\\"), each = 50))\\n'
        f')\\n'
        f'# {name} Pipeline\\n'
        f'ggplot(df, aes(x = dim_x, y = dim_y)) +\\n'
        f'  {geom_call} +\\n'
        f'  labs(title = \\"{name} Scientific Figure\\", subtitle = \\"100% Machine-Checked Gleam/BEAM Spec\\") +\\n'
        f'  theme_minimal(base_size = 11)'
    )
    code_cases.append(f'    "{name}" -> "{clean_code}"')

start_ec = text.find("pub fn example_code(ext: ExtensionMetadata) -> String {")
assert start_ec != -1

new_example_code_fn = (
    "pub fn example_code(ext: ExtensionMetadata) -> String {\n"
    "  case ext.name {\n"
    + "\n".join(code_cases) + "\n"
    "    _ -> \"library(ggplot2)\\nlibrary(\" <> ext.name <> \")\\nggplot(data) + aes(x, y)\"\n"
    "  }\n"
    "}\n"
)

new_text = text[:start_ec] + new_example_code_fn

with open("apps/cepaf_gleam/src/cepaf_gleam/sciviz/extension_examples.gleam", "w") as f:
    f.write(new_text)

print("Fixed escaping in extension_examples.gleam!")
