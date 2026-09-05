(* L2 capability slices, one level beneath the L1 public feature families.

   Every slice is anchored to paths inside the frozen Hermes snapshot. The
   anchors are discovery facts only: they record where the reference behaviour
   lives, never that an OCaml candidate reproduces it. Parity still requires
   L4-L6 differential evidence. *)

type capability = {
  id : string;
  family_id : string;
  label : string;
  source_anchors : string list;
  doc_anchors : string list;
}

let all =
  [
    (* interactive_cli *)
    { id = "repl_session"; family_id = "interactive_cli";
      label = "Interactive REPL session and console engine";
      source_anchors = [ "hermes_cli/console_engine.py"; "hermes_cli/main.py" ];
      doc_anchors = [ "website/docs/user-guide/cli.md" ] };
    { id = "slash_commands"; family_id = "interactive_cli";
      label = "Slash commands and completion";
      source_anchors = [ "hermes_cli/commands.py"; "hermes_cli/completion.py" ];
      doc_anchors = [ "website/docs/reference/slash-commands.md" ] };
    { id = "terminal_ui"; family_id = "interactive_cli";
      label = "Terminal user interface surface";
      source_anchors = [ "ui-tui/src"; "hermes_cli/curses_ui.py" ];
      doc_anchors = [ "website/docs/user-guide/tui.md" ] };
    { id = "approval_prompts"; family_id = "interactive_cli";
      label = "Interactive approval prompts and modes";
      source_anchors = [ "hermes_cli/approval_mode.py"; "hermes_cli/approvals_suggest.py" ];
      doc_anchors = [ "website/docs/user-guide/security.md" ] };
    { id = "shell_passthrough"; family_id = "interactive_cli";
      label = "Shell passthrough and clipboard bridge";
      source_anchors = [ "hermes_cli/bang_shell.py"; "hermes_cli/clipboard.py" ];
      doc_anchors = [ "website/docs/user-guide/cli.md" ] };

    (* agent_loop *)
    { id = "conversation_loop"; family_id = "agent_loop";
      label = "Conversation turn loop";
      source_anchors = [ "agent/conversation_loop.py" ];
      doc_anchors = [ "website/docs/developer-guide/agent-loop.md" ] };
    { id = "prompt_assembly"; family_id = "agent_loop";
      label = "System prompt and request assembly";
      source_anchors = [ "agent/prompt_builder.py"; "agent/system_prompt.py" ];
      doc_anchors = [ "website/docs/developer-guide/prompt-assembly.md" ] };
    { id = "context_engine"; family_id = "agent_loop";
      label = "Context engine and references";
      source_anchors = [ "agent/context_engine.py"; "agent/context_references.py" ];
      doc_anchors = [ "website/docs/user-guide/features/context-references.md" ] };
    { id = "context_compression"; family_id = "agent_loop";
      label = "Conversation compression and prompt caching";
      source_anchors =
        [ "agent/context_compressor.py"; "agent/conversation_compression.py";
          "agent/prompt_caching.py" ];
      doc_anchors = [ "website/docs/developer-guide/context-compression-and-caching.md" ] };
    { id = "turn_finalization"; family_id = "agent_loop";
      label = "Turn context, finalization, and summary";
      source_anchors = [ "agent/turn_context.py"; "agent/turn_finalizer.py"; "agent/turn_summary.py" ];
      doc_anchors = [ "website/docs/developer-guide/agent-loop.md" ] };
    { id = "interrupt_control"; family_id = "agent_loop";
      label = "Interrupts and iteration budget";
      source_anchors = [ "agent/interrupt_compat.py"; "agent/iteration_budget.py"; "tools/interrupt.py" ];
      doc_anchors = [ "website/docs/developer-guide/agent-loop.md" ] };
    { id = "message_hygiene"; family_id = "agent_loop";
      label = "Message sanitization and redaction";
      source_anchors =
        [ "agent/message_sanitization.py"; "agent/message_content.py"; "agent/redact.py" ];
      doc_anchors = [ "website/docs/user-guide/security.md" ] };

    (* model_routing *)
    { id = "provider_transports"; family_id = "model_routing";
      label = "Provider transport abstraction";
      source_anchors = [ "agent/transports/base.py"; "agent/transports/chat_completions.py" ];
      doc_anchors = [ "website/docs/developer-guide/provider-runtime.md" ] };
    { id = "anthropic_adapter"; family_id = "model_routing";
      label = "Anthropic adapter";
      source_anchors = [ "agent/anthropic_adapter.py"; "agent/transports/anthropic.py" ];
      doc_anchors = [ "website/docs/developer-guide/adding-providers.md" ] };
    { id = "codex_runtime"; family_id = "model_routing";
      label = "Codex app-server runtime";
      source_anchors =
        [ "agent/codex_runtime.py"; "agent/transports/codex.py"; "agent/transports/codex_app_server.py" ];
      doc_anchors = [ "website/docs/user-guide/features/codex-app-server-runtime.md" ] };
    { id = "cloud_vendor_adapters"; family_id = "model_routing";
      label = "Bedrock, Vertex, and Azure adapters";
      source_anchors =
        [ "agent/bedrock_adapter.py"; "agent/vertex_adapter.py"; "agent/azure_identity_adapter.py" ];
      doc_anchors = [ "website/docs/guides/aws-bedrock.md"; "website/docs/guides/google-vertex.md" ] };
    { id = "gemini_adapter"; family_id = "model_routing";
      label = "Gemini native adapter and schema";
      source_anchors = [ "agent/gemini_native_adapter.py"; "agent/gemini_schema.py" ];
      doc_anchors = [ "website/docs/guides/google-gemini.md" ] };
    { id = "route_resolution"; family_id = "model_routing";
      label = "Model catalog, routing, and fallback";
      source_anchors =
        [ "agent/model_metadata.py"; "agent/models_dev.py"; "hermes_cli/fallback_config.py" ];
      doc_anchors = [ "website/docs/user-guide/features/provider-routing.md" ] };
    { id = "rate_and_retry"; family_id = "model_routing";
      label = "Rate limit tracking and retry policy";
      source_anchors =
        [ "agent/rate_limit_tracker.py"; "agent/retry_utils.py"; "agent/nous_rate_guard.py" ];
      doc_anchors = [ "website/docs/user-guide/features/fallback-providers.md" ] };

    (* tool_execution *)
    { id = "tool_registry"; family_id = "tool_execution";
      label = "Tool registry and tool search";
      source_anchors = [ "tools/registry.py"; "tools/tool_search.py" ];
      doc_anchors = [ "website/docs/developer-guide/tools-runtime.md" ] };
    { id = "tool_dispatch"; family_id = "tool_execution";
      label = "Tool dispatch and execution";
      source_anchors = [ "agent/tool_executor.py"; "agent/tool_dispatch_helpers.py" ];
      doc_anchors = [ "website/docs/developer-guide/adding-tools.md" ] };
    { id = "approval_policy"; family_id = "tool_execution";
      label = "Approval policy and guardrails";
      source_anchors = [ "tools/approval.py"; "tools/write_approval.py"; "agent/tool_guardrails.py" ];
      doc_anchors = [ "website/docs/user-guide/security.md" ] };
    { id = "path_and_url_safety"; family_id = "tool_execution";
      label = "Path, URL, and website egress safety";
      source_anchors = [ "tools/path_security.py"; "tools/url_safety.py"; "tools/website_policy.py" ];
      doc_anchors = [ "website/docs/developer-guide/egress-internals.md" ] };
    { id = "file_operations"; family_id = "tool_execution";
      label = "File read, write, and patch operations";
      source_anchors = [ "tools/file_tools.py"; "tools/file_operations.py"; "tools/patch_parser.py" ];
      doc_anchors = [ "website/docs/reference/tools-reference.md" ] };
    { id = "result_normalization"; family_id = "tool_execution";
      label = "Tool result limits, storage, and classification";
      source_anchors =
        [ "tools/tool_output_limits.py"; "tools/tool_result_storage.py";
          "agent/tool_result_classification.py" ];
      doc_anchors = [ "website/docs/developer-guide/tools-runtime.md" ] };

    (* mcp *)
    { id = "mcp_client"; family_id = "mcp";
      label = "MCP client and schema cache";
      source_anchors = [ "tools/mcp_tool.py"; "tools/mcp_schema_cache.py" ];
      doc_anchors = [ "website/docs/user-guide/features/mcp.md" ] };
    { id = "mcp_oauth"; family_id = "mcp";
      label = "MCP OAuth acquisition and management";
      source_anchors = [ "tools/mcp_oauth.py"; "tools/mcp_oauth_manager.py" ];
      doc_anchors = [ "website/docs/guides/use-mcp-with-hermes.md" ] };
    { id = "mcp_configuration"; family_id = "mcp";
      label = "MCP configuration and catalog";
      source_anchors = [ "hermes_cli/mcp_config.py"; "hermes_cli/mcp_catalog.py" ];
      doc_anchors = [ "website/docs/reference/mcp-config-reference.md" ] };
    { id = "mcp_server_surface"; family_id = "mcp";
      label = "Hermes-as-MCP-server surface";
      source_anchors = [ "agent/transports/hermes_tools_mcp_server.py"; "mcp_serve.py" ];
      doc_anchors = [ "website/docs/user-guide/features/tool-gateway.md" ] };
    { id = "mcp_supervision"; family_id = "mcp";
      label = "MCP process supervision and security";
      source_anchors =
        [ "tools/mcp_stdio_watchdog.py"; "hermes_cli/mcp_startup.py"; "hermes_cli/mcp_security.py" ];
      doc_anchors = [ "website/docs/user-guide/features/mcp.md" ] };

    (* memory *)
    { id = "session_state"; family_id = "memory";
      label = "Session state schema and storage";
      source_anchors = [ "hermes_state.py"; "hermes_state_schema.py" ];
      doc_anchors = [ "website/docs/developer-guide/session-storage.md" ] };
    { id = "session_search"; family_id = "memory";
      label = "Full-text session search";
      source_anchors = [ "hermes_state_search.py"; "tools/session_search_tool.py"; "native/fts5_cjk" ];
      doc_anchors = [ "website/docs/user-guide/sessions.md" ] };
    { id = "memory_manager"; family_id = "memory";
      label = "Persistent memory manager and tool";
      source_anchors = [ "agent/memory_manager.py"; "tools/memory_tool.py" ];
      doc_anchors = [ "website/docs/user-guide/features/memory.md" ] };
    { id = "memory_providers"; family_id = "memory";
      label = "Pluggable memory providers";
      source_anchors = [ "agent/memory_provider.py" ];
      doc_anchors = [ "website/docs/user-guide/features/memory-providers.md" ] };
    { id = "state_portability"; family_id = "memory";
      label = "State portability, backup, and migration";
      source_anchors = [ "hermes_state_portability.py"; "hermes_cli/backup.py"; "hermes_cli/migrate.py" ];
      doc_anchors = [ "website/docs/user-guide/checkpoints-and-rollback.md" ] };

    (* context_files *)
    { id = "context_file_loading"; family_id = "context_files";
      label = "Project context file loading";
      source_anchors = [ "agent/coding_context.py" ];
      doc_anchors = [ "website/docs/user-guide/features/context-files.md" ] };
    { id = "subdirectory_hints"; family_id = "context_files";
      label = "Subdirectory context hints";
      source_anchors = [ "agent/subdirectory_hints.py" ];
      doc_anchors = [ "website/docs/user-guide/features/context-files.md" ] };
    { id = "context_breakdown"; family_id = "context_files";
      label = "Context budget breakdown reporting";
      source_anchors = [ "agent/context_breakdown.py" ];
      doc_anchors = [ "website/docs/developer-guide/context-compression-and-caching.md" ] };
    { id = "runtime_cwd_scope"; family_id = "context_files";
      label = "Runtime working-directory scoping";
      source_anchors = [ "agent/runtime_cwd.py"; "gateway/cwd_placeholder.py" ];
      doc_anchors = [ "website/docs/user-guide/git-worktrees.md" ] };

    (* skills *)
    { id = "skill_discovery"; family_id = "skills";
      label = "Skill discovery and invocation";
      source_anchors = [ "tools/skills_tool.py"; "agent/skill_commands.py" ];
      doc_anchors = [ "website/docs/user-guide/features/skills.md" ] };
    { id = "skill_bundles"; family_id = "skills";
      label = "Skill bundles and packaging";
      source_anchors = [ "agent/skill_bundles.py"; "hermes_cli/bundles.py" ];
      doc_anchors = [ "website/docs/developer-guide/creating-skills.md" ] };
    { id = "skill_preprocessing"; family_id = "skills";
      label = "Skill preprocessing and frontmatter";
      source_anchors = [ "agent/skill_preprocessing.py"; "agent/skill_utils.py" ];
      doc_anchors = [ "website/docs/developer-guide/creating-skills.md" ] };
    { id = "skill_sync"; family_id = "skills";
      label = "Skill hub synchronization";
      source_anchors = [ "tools/skills_sync.py"; "tools/skills_sync_client.py"; "tools/skills_hub.py" ];
      doc_anchors = [ "website/docs/guides/work-with-skills.md" ] };
    { id = "skill_provenance"; family_id = "skills";
      label = "Skill provenance and audit guards";
      source_anchors = [ "tools/skill_provenance.py"; "tools/skills_ast_audit.py"; "tools/skills_guard.py" ];
      doc_anchors = [ "website/docs/user-guide/security.md" ] };
    { id = "skill_catalog"; family_id = "skills";
      label = "Bundled and optional skill catalog";
      source_anchors = [ "skills"; "optional-skills" ];
      doc_anchors =
        [ "website/docs/reference/skills-catalog.md";
          "website/docs/reference/optional-skills-catalog.md" ] };

    (* learning_loop *)
    { id = "learning_graph"; family_id = "learning_loop";
      label = "Learning graph and rendering";
      source_anchors = [ "agent/learning_graph.py"; "agent/learning_graph_render.py" ];
      doc_anchors = [ "website/docs/user-guide/features/curator.md" ] };
    { id = "learning_mutations"; family_id = "learning_loop";
      label = "Learning mutations and prompts";
      source_anchors = [ "agent/learning_mutations.py"; "agent/learn_prompt.py" ];
      doc_anchors = [ "website/docs/user-guide/features/curator.md" ] };
    { id = "curated_insights"; family_id = "learning_loop";
      label = "Curator and insight extraction";
      source_anchors = [ "agent/curator.py"; "agent/insights.py" ];
      doc_anchors = [ "website/docs/user-guide/features/curator.md" ] };
    { id = "verification_feedback"; family_id = "learning_loop";
      label = "Verification evidence and stop hooks";
      source_anchors =
        [ "agent/verification_evidence.py"; "agent/verify_hooks.py"; "agent/verification_stop.py" ];
      doc_anchors = [ "website/docs/user-guide/features/hooks.md" ] };

    (* subagents *)
    { id = "subagent_lifecycle"; family_id = "subagents";
      label = "Subagent lifecycle API";
      source_anchors = [ "agent/subagent_lifecycle.py" ];
      doc_anchors = [ "website/docs/developer-guide/subagent-lifecycle-api.md" ] };
    { id = "delegation"; family_id = "subagents";
      label = "Delegation tool and context";
      source_anchors = [ "tools/delegate_tool.py"; "agent/delegation_context.py" ];
      doc_anchors = [ "website/docs/user-guide/features/delegation.md" ] };
    { id = "async_delegation"; family_id = "subagents";
      label = "Asynchronous delegation and live logs";
      source_anchors = [ "tools/async_delegation.py"; "tools/delegation_live_log.py" ];
      doc_anchors = [ "website/docs/guides/delegation-patterns.md" ] };
    { id = "mixture_of_agents"; family_id = "subagents";
      label = "Mixture-of-agents loop and trace";
      source_anchors = [ "agent/moa_loop.py"; "agent/moa_trace.py" ];
      doc_anchors = [ "website/docs/user-guide/features/mixture-of-agents.md" ] };
    { id = "kanban_swarm"; family_id = "subagents";
      label = "Kanban worker lanes and swarm";
      source_anchors = [ "hermes_cli/kanban_swarm.py"; "tools/kanban_tools.py" ];
      doc_anchors = [ "website/docs/user-guide/features/kanban-worker-lanes.md" ] };

    (* scheduled_automation *)
    { id = "job_registry"; family_id = "scheduled_automation";
      label = "Cron job registry";
      source_anchors = [ "cron/jobs.py" ];
      doc_anchors = [ "website/docs/user-guide/features/cron.md" ] };
    { id = "scheduler"; family_id = "scheduled_automation";
      label = "Scheduler and scheduler providers";
      source_anchors = [ "cron/scheduler.py"; "cron/scheduler_provider.py" ];
      doc_anchors = [ "website/docs/developer-guide/cron-internals.md" ] };
    { id = "executions"; family_id = "scheduled_automation";
      label = "Execution records and lifecycle guard";
      source_anchors = [ "cron/executions.py"; "cron/lifecycle_guard.py" ];
      doc_anchors = [ "website/docs/guides/cron-troubleshooting.md" ] };
    { id = "blueprints"; family_id = "scheduled_automation";
      label = "Automation blueprints and suggestions";
      source_anchors = [ "cron/blueprint_catalog.py"; "cron/suggestions.py" ];
      doc_anchors = [ "website/docs/guides/automation-blueprints.md" ] };
    { id = "cron_surface"; family_id = "scheduled_automation";
      label = "Cron CLI and agent tools";
      source_anchors = [ "hermes_cli/cron.py"; "tools/cronjob_tools.py" ];
      doc_anchors = [ "website/docs/guides/automate-with-cron.md" ] };

    (* messaging_gateway *)
    { id = "gateway_runtime"; family_id = "messaging_gateway";
      label = "Gateway runtime and session management";
      source_anchors = [ "gateway/run.py"; "gateway/session.py" ];
      doc_anchors = [ "website/docs/developer-guide/gateway-internals.md" ] };
    { id = "platform_registry"; family_id = "messaging_gateway";
      label = "Platform registry and adapter base";
      source_anchors = [ "gateway/platform_registry.py"; "gateway/platforms/base.py" ];
      doc_anchors = [ "website/docs/developer-guide/adding-platform-adapters.md" ] };
    { id = "delivery_ledger"; family_id = "messaging_gateway";
      label = "Delivery obligations and ledger";
      source_anchors = [ "gateway/delivery.py"; "gateway/delivery_ledger.py" ];
      doc_anchors = [ "website/docs/user-guide/messaging/index.md" ] };
    { id = "webhook_intake"; family_id = "messaging_gateway";
      label = "Webhook intake and filters";
      source_anchors = [ "gateway/platforms/webhook.py"; "gateway/platforms/webhook_filters.py" ];
      doc_anchors = [ "website/docs/user-guide/messaging/webhooks.md" ] };
    { id = "relay_channel"; family_id = "messaging_gateway";
      label = "Relay connector channel";
      source_anchors = [ "gateway/relay"; "agent/relay_runtime.py" ];
      doc_anchors = [ "website/docs/user-guide/messaging/relay.md" ] };
    { id = "profile_routing"; family_id = "messaging_gateway";
      label = "Multi-profile gateway routing";
      source_anchors = [ "gateway/profile_routing.py" ];
      doc_anchors = [ "website/docs/user-guide/multi-profile-gateways.md" ] };
    { id = "lifecycle_control"; family_id = "messaging_gateway";
      label = "Readiness, drain, and shutdown control";
      source_anchors = [ "gateway/readiness.py"; "gateway/drain_control.py"; "gateway/shutdown_watchdog.py" ];
      doc_anchors = [ "website/docs/developer-guide/gateway-internals.md" ] };

    (* voice_media *)
    { id = "text_to_speech"; family_id = "voice_media";
      label = "Text-to-speech synthesis and streaming";
      source_anchors = [ "tools/tts_tool.py"; "agent/tts_provider.py"; "tools/tts_streaming.py" ];
      doc_anchors = [ "website/docs/user-guide/features/tts.md" ] };
    { id = "transcription"; family_id = "voice_media";
      label = "Audio transcription providers";
      source_anchors = [ "agent/transcription_provider.py"; "tools/transcription_tools.py" ];
      doc_anchors = [ "website/docs/user-guide/features/voice-mode.md" ] };
    { id = "voice_mode"; family_id = "voice_media";
      label = "Voice mode and wake word";
      source_anchors = [ "tools/voice_mode.py"; "tools/wake_word.py" ];
      doc_anchors = [ "website/docs/user-guide/features/wake-word.md" ] };
    { id = "image_generation"; family_id = "voice_media";
      label = "Image generation providers and routing";
      source_anchors =
        [ "tools/image_generation_tool.py"; "agent/image_gen_provider.py"; "agent/image_routing.py" ];
      doc_anchors = [ "website/docs/user-guide/features/image-generation.md" ] };
    { id = "video_generation"; family_id = "voice_media";
      label = "Video generation providers";
      source_anchors = [ "tools/video_generation_tool.py"; "agent/video_gen_provider.py" ];
      doc_anchors = [ "website/docs/developer-guide/video-gen-provider-plugin.md" ] };
    { id = "vision"; family_id = "voice_media";
      label = "Vision and image understanding";
      source_anchors = [ "tools/vision_tools.py"; "tools/image_source.py" ];
      doc_anchors = [ "website/docs/user-guide/features/vision.md" ] };

    (* browser_research *)
    { id = "browser_tool"; family_id = "browser_research";
      label = "Browser tool and provider";
      source_anchors = [ "tools/browser_tool.py"; "agent/browser_provider.py" ];
      doc_anchors = [ "website/docs/user-guide/features/browser.md" ] };
    { id = "browser_supervisor"; family_id = "browser_research";
      label = "Browser supervision and stealth backends";
      source_anchors = [ "tools/browser_supervisor.py"; "tools/browser_camofox.py" ];
      doc_anchors = [ "website/docs/developer-guide/browser-supervisor.md" ] };
    { id = "cdp_control"; family_id = "browser_research";
      label = "Chrome DevTools protocol control";
      source_anchors = [ "tools/browser_cdp_tool.py"; "tools/browser_dialog_tool.py" ];
      doc_anchors = [ "website/docs/user-guide/features/browser.md" ] };
    { id = "web_search"; family_id = "browser_research";
      label = "Web search providers and fetch tools";
      source_anchors = [ "agent/web_search_provider.py"; "tools/web_tools.py" ];
      doc_anchors = [ "website/docs/user-guide/features/web-search.md" ] };
    { id = "computer_use"; family_id = "browser_research";
      label = "Computer use control loop";
      source_anchors = [ "tools/computer_use_tool.py"; "tools/computer_use" ];
      doc_anchors = [ "website/docs/user-guide/features/computer-use.md" ] };

    (* execution_backends *)
    { id = "local_execution"; family_id = "execution_backends";
      label = "Local execution environment";
      source_anchors = [ "tools/environments/local.py"; "tools/code_execution_tool.py" ];
      doc_anchors = [ "website/docs/user-guide/features/code-execution.md" ] };
    { id = "container_execution"; family_id = "execution_backends";
      label = "Container execution environment";
      source_anchors = [ "tools/environments/docker.py"; "docker" ];
      doc_anchors = [ "website/docs/user-guide/docker.md" ] };
    { id = "ssh_execution"; family_id = "execution_backends";
      label = "SSH execution and file sync";
      source_anchors = [ "tools/environments/ssh.py"; "tools/environments/file_sync.py" ];
      doc_anchors = [ "website/docs/user-guide/features/code-execution.md" ] };
    { id = "serverless_execution"; family_id = "execution_backends";
      label = "Serverless sandbox execution";
      source_anchors =
        [ "tools/environments/modal.py"; "tools/environments/vercel_sandbox.py";
          "tools/environments/daytona.py" ];
      doc_anchors = [ "website/docs/user-guide/features/code-execution.md" ] };
    { id = "terminal_sessions"; family_id = "execution_backends";
      label = "Persistent terminal sessions and process registry";
      source_anchors =
        [ "tools/terminal_tool.py"; "tools/read_terminal_tool.py"; "tools/process_registry.py" ];
      doc_anchors = [ "website/docs/reference/tools-reference.md" ] };

    (* trajectory_data *)
    { id = "trajectory_format"; family_id = "trajectory_data";
      label = "Trajectory record format";
      source_anchors = [ "agent/trajectory.py" ];
      doc_anchors = [ "website/docs/developer-guide/trajectory-format.md" ] };
    { id = "trace_upload"; family_id = "trajectory_data";
      label = "Trace upload and telemetry emission";
      source_anchors = [ "agent/trace_upload.py"; "agent/monitoring/emitter.py" ];
      doc_anchors = [ "website/docs/developer-guide/trajectory-format.md" ] };
    { id = "batch_generation"; family_id = "trajectory_data";
      label = "Batch trajectory generation";
      source_anchors = [ "batch_runner.py"; "mini_swe_runner.py"; "datagen-config-examples" ];
      doc_anchors = [ "website/docs/user-guide/features/batch-processing.md" ] };

    (* operations_cli *)
    { id = "setup_wizard"; family_id = "operations_cli";
      label = "Setup and onboarding flow";
      source_anchors = [ "hermes_cli/init_command.py"; "agent/onboarding.py" ];
      doc_anchors = [ "website/docs/getting-started/quickstart.md" ] };
    { id = "configuration"; family_id = "operations_cli";
      label = "Configuration load, defaults, and profiles";
      source_anchors = [ "hermes_cli/config.py"; "hermes_cli/config_defaults.py"; "hermes_cli/profiles.py" ];
      doc_anchors = [ "website/docs/user-guide/configuration.md" ] };
    { id = "doctor_diagnostics"; family_id = "operations_cli";
      label = "Doctor checks and diagnostics upload";
      source_anchors = [ "hermes_cli/doctor.py"; "hermes_cli/diagnostics_upload.py" ];
      doc_anchors = [ "website/docs/guides/tips.md" ] };
    { id = "migration"; family_id = "operations_cli";
      label = "Config and state migration";
      source_anchors = [ "hermes_cli/migrate.py"; "hermes_cli/config_migrations.py" ];
      doc_anchors = [ "website/docs/guides/migrate-from-openclaw.md" ] };
    { id = "usage_billing"; family_id = "operations_cli";
      label = "Account usage and billing views";
      source_anchors = [ "agent/account_usage.py"; "agent/billing_usage.py"; "agent/billing_view.py" ];
      doc_anchors = [ "docs/billing-lifecycle.md" ] };
    { id = "observability"; family_id = "operations_cli";
      label = "Monitoring policy and OTLP export";
      source_anchors =
        [ "agent/monitoring/policy.py"; "agent/monitoring/otlp_exporter.py"; "hermes_cli/observability" ];
      doc_anchors = [ "docs/observability" ] };

    (* application_surfaces *)
    { id = "desktop_app"; family_id = "application_surfaces";
      label = "Desktop application surface";
      source_anchors = [ "apps/desktop" ];
      doc_anchors = [ "website/docs/user-guide/desktop.md" ] };
    { id = "web_dashboard"; family_id = "application_surfaces";
      label = "Web dashboard surface";
      source_anchors = [ "web/src" ];
      doc_anchors = [ "website/docs/user-guide/features/web-dashboard.md" ] };
    { id = "api_server"; family_id = "application_surfaces";
      label = "HTTP API server surface";
      source_anchors = [ "gateway/platforms/api_server.py" ];
      doc_anchors = [ "website/docs/user-guide/features/api-server.md" ] };
    { id = "acp_surface"; family_id = "application_surfaces";
      label = "Agent client protocol surface";
      source_anchors = [ "acp_adapter" ];
      doc_anchors = [ "website/docs/user-guide/features/acp.md" ] };
  ]

let node_id capability = "hermes." ^ capability.family_id ^ "." ^ capability.id
let semantic_key capability = capability.family_id ^ "." ^ capability.id
let parent_node_id capability = "hermes." ^ capability.family_id
let anchors capability = capability.source_anchors @ capability.doc_anchors

let for_family family_id =
  List.filter (fun capability -> capability.family_id = family_id) all

(* Core dependency edges between capability slices, keyed by semantic key. An
   edge means the target has to be contracted, implemented, and differentially
   proven before its dependent can claim the same. Slices absent from the table
   depend on nothing and are implementable first. Edges cross family
   boundaries wherever the reference does. *)
let dependencies =
  [
    ("interactive_cli.repl_session", [ "agent_loop.conversation_loop" ]);
    ("interactive_cli.slash_commands", [ "interactive_cli.repl_session" ]);
    ("interactive_cli.terminal_ui", [ "interactive_cli.repl_session" ]);
    ("interactive_cli.approval_prompts", [ "tool_execution.approval_policy" ]);
    ("interactive_cli.shell_passthrough", [ "interactive_cli.repl_session" ]);

    ("agent_loop.conversation_loop",
     [ "model_routing.provider_transports"; "tool_execution.tool_dispatch";
       "agent_loop.prompt_assembly" ]);
    ("agent_loop.prompt_assembly", [ "agent_loop.message_hygiene" ]);
    ("agent_loop.context_engine", [ "agent_loop.prompt_assembly" ]);
    ("agent_loop.context_compression", [ "agent_loop.context_engine" ]);
    ("agent_loop.turn_finalization", [ "agent_loop.conversation_loop" ]);
    ("agent_loop.interrupt_control", [ "agent_loop.conversation_loop" ]);

    ("model_routing.anthropic_adapter", [ "model_routing.provider_transports" ]);
    ("model_routing.codex_runtime", [ "model_routing.provider_transports" ]);
    ("model_routing.cloud_vendor_adapters", [ "model_routing.provider_transports" ]);
    ("model_routing.gemini_adapter", [ "model_routing.provider_transports" ]);
    ("model_routing.route_resolution", [ "model_routing.provider_transports" ]);
    ("model_routing.rate_and_retry", [ "model_routing.provider_transports" ]);

    ("tool_execution.approval_policy", [ "tool_execution.tool_registry" ]);
    ("tool_execution.tool_dispatch",
     [ "tool_execution.tool_registry"; "tool_execution.approval_policy" ]);
    ("tool_execution.file_operations",
     [ "tool_execution.tool_registry"; "tool_execution.path_and_url_safety" ]);
    ("tool_execution.result_normalization", [ "tool_execution.tool_dispatch" ]);

    ("mcp.mcp_client", [ "tool_execution.tool_registry" ]);
    ("mcp.mcp_oauth", [ "mcp.mcp_client" ]);
    ("mcp.mcp_configuration", [ "mcp.mcp_client" ]);
    ("mcp.mcp_server_surface", [ "mcp.mcp_client" ]);
    ("mcp.mcp_supervision", [ "mcp.mcp_client" ]);

    ("memory.session_search", [ "memory.session_state" ]);
    ("memory.memory_manager", [ "memory.session_state" ]);
    ("memory.memory_providers", [ "memory.memory_manager" ]);
    ("memory.state_portability", [ "memory.session_state" ]);

    ("context_files.subdirectory_hints", [ "context_files.context_file_loading" ]);
    ("context_files.context_breakdown", [ "agent_loop.context_engine" ]);

    ("skills.skill_discovery", [ "tool_execution.tool_registry" ]);
    ("skills.skill_bundles", [ "skills.skill_discovery" ]);
    ("skills.skill_preprocessing", [ "skills.skill_discovery" ]);
    ("skills.skill_sync", [ "skills.skill_discovery" ]);
    ("skills.skill_provenance", [ "skills.skill_discovery" ]);
    ("skills.skill_catalog", [ "skills.skill_discovery" ]);

    ("learning_loop.learning_graph", [ "memory.session_state" ]);
    ("learning_loop.learning_mutations", [ "learning_loop.learning_graph" ]);
    ("learning_loop.curated_insights", [ "learning_loop.learning_graph" ]);
    ("learning_loop.verification_feedback", [ "agent_loop.turn_finalization" ]);

    ("subagents.subagent_lifecycle", [ "agent_loop.conversation_loop" ]);
    ("subagents.delegation", [ "subagents.subagent_lifecycle" ]);
    ("subagents.async_delegation", [ "subagents.delegation" ]);
    ("subagents.mixture_of_agents", [ "agent_loop.conversation_loop" ]);
    ("subagents.kanban_swarm", [ "subagents.delegation" ]);

    ("scheduled_automation.job_registry", [ "memory.session_state" ]);
    ("scheduled_automation.scheduler", [ "scheduled_automation.job_registry" ]);
    ("scheduled_automation.executions", [ "scheduled_automation.scheduler" ]);
    ("scheduled_automation.blueprints", [ "scheduled_automation.job_registry" ]);
    ("scheduled_automation.cron_surface", [ "scheduled_automation.job_registry" ]);

    ("messaging_gateway.gateway_runtime",
     [ "agent_loop.conversation_loop"; "memory.session_state" ]);
    ("messaging_gateway.platform_registry", [ "messaging_gateway.gateway_runtime" ]);
    ("messaging_gateway.delivery_ledger", [ "messaging_gateway.gateway_runtime" ]);
    ("messaging_gateway.webhook_intake", [ "messaging_gateway.platform_registry" ]);
    ("messaging_gateway.relay_channel", [ "messaging_gateway.platform_registry" ]);
    ("messaging_gateway.profile_routing", [ "messaging_gateway.gateway_runtime" ]);
    ("messaging_gateway.lifecycle_control", [ "messaging_gateway.gateway_runtime" ]);

    ("voice_media.text_to_speech", [ "tool_execution.tool_registry" ]);
    ("voice_media.transcription", [ "tool_execution.tool_registry" ]);
    ("voice_media.voice_mode", [ "voice_media.text_to_speech"; "voice_media.transcription" ]);
    ("voice_media.image_generation", [ "tool_execution.tool_registry" ]);
    ("voice_media.video_generation", [ "tool_execution.tool_registry" ]);
    ("voice_media.vision", [ "tool_execution.tool_registry" ]);

    ("browser_research.browser_tool", [ "tool_execution.tool_registry" ]);
    ("browser_research.browser_supervisor", [ "browser_research.browser_tool" ]);
    ("browser_research.cdp_control", [ "browser_research.browser_tool" ]);
    ("browser_research.web_search", [ "tool_execution.path_and_url_safety" ]);
    ("browser_research.computer_use", [ "browser_research.browser_tool" ]);

    ("execution_backends.local_execution", [ "tool_execution.tool_dispatch" ]);
    ("execution_backends.container_execution", [ "execution_backends.local_execution" ]);
    ("execution_backends.ssh_execution", [ "execution_backends.local_execution" ]);
    ("execution_backends.serverless_execution", [ "execution_backends.local_execution" ]);
    ("execution_backends.terminal_sessions", [ "execution_backends.local_execution" ]);

    ("trajectory_data.trajectory_format", [ "agent_loop.turn_finalization" ]);
    ("trajectory_data.trace_upload", [ "trajectory_data.trajectory_format" ]);
    ("trajectory_data.batch_generation", [ "trajectory_data.trajectory_format" ]);

    ("operations_cli.setup_wizard", [ "operations_cli.configuration" ]);
    ("operations_cli.doctor_diagnostics", [ "operations_cli.configuration" ]);
    ("operations_cli.migration", [ "operations_cli.configuration" ]);
    ("operations_cli.usage_billing", [ "model_routing.route_resolution" ]);
    ("operations_cli.observability", [ "operations_cli.configuration" ]);

    ("application_surfaces.api_server", [ "messaging_gateway.gateway_runtime" ]);
    ("application_surfaces.desktop_app", [ "messaging_gateway.gateway_runtime" ]);
    ("application_surfaces.web_dashboard", [ "application_surfaces.api_server" ]);
    ("application_surfaces.acp_surface", [ "agent_loop.conversation_loop" ]);
  ]

let depends_on capability =
  match List.assoc_opt (semantic_key capability) dependencies with
  | Some keys -> keys
  | None -> []

let find key = List.find_opt (fun capability -> semantic_key capability = key) all

(* Depth-first topological order: every slice appears after everything it
   depends on. Catalog order breaks ties, so the result is deterministic. *)
let topological_order () =
  let state = Hashtbl.create 128 in
  let ordered = ref [] in
  let rec visit trail key =
    match Hashtbl.find_opt state key with
    | Some `Placed -> Ok ()
    | Some `Visiting ->
        Error ("capability dependency cycle: " ^ String.concat " -> " (List.rev (key :: trail)))
    | None ->
        (match find key with
        | None -> Error ("unknown capability dependency: " ^ key)
        | Some capability ->
            Hashtbl.replace state key `Visiting;
            let result =
              List.fold_left
                (fun result dependency ->
                  match result with
                  | Error _ -> result
                  | Ok () -> visit (key :: trail) dependency)
                (Ok ()) (depends_on capability)
            in
            (match result with
            | Error _ as error -> error
            | Ok () ->
                Hashtbl.replace state key `Placed;
                ordered := capability :: !ordered;
                Ok ()))
  in
  let result =
    List.fold_left
      (fun result capability ->
        match result with Error _ -> result | Ok () -> visit [] (semantic_key capability))
      (Ok ()) all
  in
  match result with Error _ as error -> error | Ok () -> Ok (List.rev !ordered)
