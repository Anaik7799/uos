from std.sys import argv, exit
from std.python import Python

def main():
    var args = argv()
    if len(args) < 2:
        print("Usage: mojo markitdown.mojo <input_file> [output_file.md]")
        return

    var input_path = args[1]
    
    try:
        var md = Python.import_module("markitdown")
        var MarkItDown = md.MarkItDown
        var converter = MarkItDown()
        
        var result = converter.convert(input_path)
        var text = String(result.text_content)
        
        if len(args) >= 3:
            var out_path = args[2]
            var builtins = Python.import_module("builtins")
            var f = builtins.open(out_path, "w", encoding="utf-8")
            _ = f.write(result.text_content)
            _ = f.close()
            print("Successfully saved markdown to:", out_path)
        else:
            print(text)
    except e:
        print("Error during conversion:", e)
