with open("apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/sciviz_comprehensive_explorer.gleam") as f:
    text = f.read()

# Replace single quotes in codeEl.innerText
old_default_code = "codeEl.innerText = code || ('library(ggplot2)\\nlibrary(' + name + ')\\nggplot(data) + aes(x, y)');"
new_default_code = "codeEl.innerText = code || (`library(ggplot2)\\nlibrary(${name})\\nggplot(data) + aes(x, y)`);"
text = text.replace(old_default_code, new_default_code)

# Replace single-quoted presets with backticks
presets_replacements = [
    ("code = 'ggplot(diamonds) +\\n  aes(carat, price) +\\n  geom_point(alpha=.1) +\\n  geom_smooth() #<<\\nggram('Diamond Pricing')';",
     "code = `ggplot(diamonds) +\\n  aes(carat, price) +\\n  geom_point(alpha=.1) +\\n  geom_smooth() #<<\\nggram('Diamond Pricing')`;"),

    ("code = 'ggplot(tcga_pan_cancer) +\\n  aes(log2_fc, -log10(p_val)) +\\n  geom_point(aes(color = is_significant)) +\\n  geom_text_repel(aes(label = gene_symbol)) #<<\\nggtree_align()';",
     "code = `ggplot(tcga_pan_cancer) +\\n  aes(log2_fc, -log10(p_val)) +\\n  geom_point(aes(color = is_significant)) +\\n  geom_text_repel(aes(label = gene_symbol)) #<<\\nggtree_align()`;"),

    ("code = 'ggplot(uos_mesh_events) +\\n  aes(peer_id, latency_us) +\\n  geom_edge_bundle() +\\n  geom_node_point(size = 3) #<<\\nggnetwork_theme()';",
     "code = `ggplot(uos_mesh_events) +\\n  aes(peer_id, latency_us) +\\n  geom_edge_bundle() +\\n  geom_node_point(size = 3) #<<\\nggnetwork_theme()`;"),

    ("code = 'ggplot(credit_risk_eval) +\\n  aes(d = default_obs, m = pred_prob) +\\n  geom_roc(n.cuts = 0) +\\n  style_roc() #<<\\nannotate('text', x = .75, y = .25, label = 'AUC = 0.89')';",
     "code = `ggplot(credit_risk_eval) +\\n  aes(d = default_obs, m = pred_prob) +\\n  geom_roc(n.cuts = 0) +\\n  style_roc() #<<\\nannotate('text', x = .75, y = .25, label = 'AUC = 0.89')`;"),

    ("code = 'ggplot(eeg_128ch_matrix) +\\n  aes(epoch_time_ms, microvolts, group = channel_id) +\\n  geom_path(alpha = 0.6) +\\n  geom_highlight_band(12, 30, fill = '#a855f7') #<<\\nggtimeseries_spec()';",
     "code = `ggplot(eeg_128ch_matrix) +\\n  aes(epoch_time_ms, microvolts, group = channel_id) +\\n  geom_path(alpha = 0.6) +\\n  geom_highlight_band(12, 30, fill = '#a855f7') #<<\\nggtimeseries_spec()`;"),

    ("code = 'ggplot(scrna_10x_pbmc) +\\n  aes(umap_1, umap_2, color = cell_type) +\\n  geom_point(size = 0.8, alpha = 0.7) +\\n  geom_density_2d(color = '#38bdf8') #<<\\nscale_color_scran()';",
     "code = `ggplot(scrna_10x_pbmc) +\\n  aes(umap_1, umap_2, color = cell_type) +\\n  geom_point(size = 0.8, alpha = 0.7) +\\n  geom_density_2d(color = '#38bdf8') #<<\\nscale_color_scran()`;")
]

for old, new in presets_replacements:
    if old in text:
        text = text.replace(old, new)
        print("Replaced preset!")
    else:
        print("Preset not found:", old[:30])

with open("apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/sciviz_comprehensive_explorer.gleam", "w") as f:
    f.write(text)

print("Updated script with backticks!")
