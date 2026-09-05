type feature = { id : string; label : string; source_domains : string list }

let all =
  [ { id="interactive_cli"; label="Interactive CLI and terminal UI"; source_domains=["hermes_cli";"ui-tui";"tui_gateway"] };
    { id="agent_loop"; label="Agent conversation and tool loop"; source_domains=["agent"] };
    { id="model_routing"; label="Model providers and routing"; source_domains=["agent";"providers"] };
    { id="tool_execution"; label="Tool execution and approvals"; source_domains=["agent";"tools"] };
    { id="mcp"; label="MCP integration"; source_domains=["agent";"optional-mcps"] };
    { id="memory"; label="Persistent memory and session search"; source_domains=["agent";"native"] };
    { id="context_files"; label="Project context files"; source_domains=["agent";"skills"] };
    { id="skills"; label="Skills and discovery"; source_domains=["agent";"skills";"optional-skills"] };
    { id="learning_loop"; label="Learning and self-improvement"; source_domains=["agent";"skills"] };
    { id="subagents"; label="Subagents and parallel delegation"; source_domains=["agent"] };
    { id="scheduled_automation"; label="Scheduled cron automation"; source_domains=["cron";"agent";"gateway"] };
    { id="messaging_gateway"; label="Messaging platforms and delivery gateway"; source_domains=["gateway";"agent"] };
    { id="voice_media"; label="Voice, transcription, and media generation"; source_domains=["agent";"tools"] };
    { id="browser_research"; label="Browser control and web research"; source_domains=["agent";"tools";"web"] };
    { id="execution_backends"; label="Local, container, SSH, and serverless execution"; source_domains=["tools";"docker";"scripts"] };
    { id="trajectory_data"; label="Trajectory generation and compression"; source_domains=["agent";"datagen-config-examples"] };
    { id="operations_cli"; label="Setup, config, doctor, migration, and usage"; source_domains=["hermes_cli";"apps";"agent"] };
    { id="application_surfaces"; label="Desktop and web application surfaces"; source_domains=["apps";"web";"ui-tui"] } ]
