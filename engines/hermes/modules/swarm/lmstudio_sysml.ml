type sysml_part = { name: string; typ: string }
type sysml_connection = { source: string; target: string }
type sysml_system = { name: string; parts: sysml_part list; connections: sysml_connection list }

let lmstudio_system = {
  name = "LMStudio_System";
  parts = [
    { name = "lmstudio_engine"; typ = "engine" };
    { name = "zenoh_mesh"; typ = "mesh" }
  ];
  connections = [
    { source = "lmstudio_engine"; target = "zenoh_mesh" }
  ];
}
