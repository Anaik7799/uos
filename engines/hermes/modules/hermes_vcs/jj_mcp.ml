(* Compatibility quarantine only. No MCP mutation tool is published before the
   closed Jujutsu request algebra and bridge activity are Current. *)

type unavailable = {
  code : string;
  lifecycle : string;
}

let tools = []

let dispatch _name _payload =
  Error
    { code = "jj.mcp-unavailable-until-bridge-activity";
      lifecycle = "Unavailable_observed" }
