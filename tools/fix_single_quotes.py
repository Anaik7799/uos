with open("apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/sciviz_comprehensive_explorer.gleam") as f:
    text = f.read()

text = text.replace("\\'", "'")

with open("apps/cepaf_gleam/src/cepaf_gleam/ui/lustre/sciviz_comprehensive_explorer.gleam", "w") as f:
    f.write(text)
print("Replaced \\' with ' in explorer!")
