//// T17 MCP prompts. Prompts are advisory only: they can never mint or carry
//// effect authority. Deprecated `sampling`/`roots` prompts are never
//// advertised, and authority-escalation arguments are refused outright.

import cepaf_gleam/mcp/types.{type ToolError, NonRetryable, ToolError}
import gleam/dict.{type Dict}
import gleam/list
import gleam/result
import gleam/string

pub const authority_escalation_args = [
  "grant_id",
  "authorize_effect",
  "bypass_sa_plan",
  "execute_effect",
]

pub const deprecated_prompts = ["sampling", "roots"]

pub type PromptSpec {
  PromptSpec(
    name: String,
    description: String,
    required_args: List(String),
    template_body: String,
  )
}

pub type RenderedPrompt {
  RenderedPrompt(
    name: String,
    messages: List(String),
    advisory_only: Bool,
    effect_authority: Bool,
  )
}

/// Advertises only prompts that are present in the registry and are not on the
/// deprecated list. Sampling and roots are intentionally omitted.
pub fn list_prompts(registry: List(PromptSpec)) -> List(PromptSpec) {
  list.filter(registry, fn(prompt) {
    !list.contains(deprecated_prompts, prompt.name)
  })
}

pub fn get_prompt(
  registry: List(PromptSpec),
  name: String,
  args: Dict(String, String),
) -> Result(RenderedPrompt, ToolError) {
  use _ <- result.try(refuse_deprecated_name(name))
  use _ <- result.try(refuse_escalation_args(args))
  case list.find(registry, fn(spec) { spec.name == name }) {
    Error(_) ->
      Error(ToolError(
        "PROMPT_NOT_FOUND",
        "No prompt registered with name " <> name,
        NonRetryable,
      ))
    Ok(spec) ->
      case missing_required_args(spec, args) {
        [] ->
          Ok(RenderedPrompt(
            name: spec.name,
            messages: [render_body(spec, args)],
            advisory_only: True,
            effect_authority: False,
          ))
        missing ->
          Error(ToolError(
            "PROMPT_MISSING_ARGUMENT",
            "Missing required prompt arguments: " <> string.join(missing, ", "),
            NonRetryable,
          ))
      }
  }
}

fn refuse_deprecated_name(name: String) -> Result(Nil, ToolError) {
  case list.contains(deprecated_prompts, string.lowercase(string.trim(name))) {
    True ->
      Error(ToolError(
        "DEPRECATED_PROMPT_FORBIDDEN",
        "Prompt " <> name <> " is deprecated and cannot be rendered",
        NonRetryable,
      ))
    False -> Ok(Nil)
  }
}

fn refuse_escalation_args(
  args: Dict(String, String),
) -> Result(Nil, ToolError) {
  case
    list.find(authority_escalation_args, fn(arg) { dict.has_key(args, arg) })
  {
    Ok(found) ->
      Error(ToolError(
        "PROMPT_CANNOT_AUTHORIZE_EFFECT",
        "Prompt argument "
          <> found
          <> " cannot mint or authorize effect authority",
        NonRetryable,
      ))
    Error(_) -> Ok(Nil)
  }
}

fn missing_required_args(
  spec: PromptSpec,
  args: Dict(String, String),
) -> List(String) {
  list.filter(spec.required_args, fn(arg) { !dict.has_key(args, arg) })
}

fn render_body(spec: PromptSpec, args: Dict(String, String)) -> String {
  list.fold(spec.required_args, spec.template_body, fn(acc, key) {
    case dict.get(args, key) {
      Ok(value) -> string.replace(acc, "{{" <> key <> "}}", value)
      Error(_) -> acc
    }
  })
}
