# hermes_wiki — the wiki, Zettelkasten and knowledge-management subsystem

**The dependency contract:** no Dune file in this tree references a
`hermes_harness_*` library, enforced by the guard in
`test/test_hermes_wiki.ml`. The parity harness may depend on this subsystem;
never the reverse. That guard is not a standalone-liftability proof: the MBSE
source library depends on `hermes_sysml`, and the topology source library
depends on `hermes_fpp_window_authority`. Moving the complete subsystem today
therefore requires that transitive Dune closure.

## Layout

    src/engine/   the core: corpus model (Hermes_wiki), recursive AST
                  (Wiki_ast + line-machine oracle), zkquery (Wiki_query),
                  dependency sheaf (Dep_sheaf), zero-dep HTTP (Hermes_httpd)
    src/fpp/      the diagnostic substrate, the F Prime metamodel + pure
                  simulator, and Wiki_topology — the system itself as an
                  actor topology (9 components, 2 control-loop machines)
    src/core/     render-baseline model + sha256 declared oracle
    src/render/   TyXML typed views
    src/server/   Dream server over the typed route ADT
    src/frontend/ Bonsai (js_of_ocaml) progressive enhancement
    src/tools/    gen_render_baseline (re-pinning is DELIBERATE, never in
                  the battery)
    test/         the wiki battery, including corpus differential and the
                  no-harness-dependency guard
    pages/        the corpus (git-tracked = member)
    baseline/     the pinned render digests
    import/       reference mirrors from zigvm (86 files) and c3i (19),
                  provenance-manifested, deliberately NOT in the build

## Dependencies (by tier — take only what you use)

- engine + core: OCaml stdlib, `unix`, `yojson`, `threads.posix`
  (httpd only); `sha256sum` as a declared external oracle
- MBSE + FPP topology: `hermes_sysml`, `hermes_fpp_window_authority`
- server: `dream`, `tyxml`
- frontend: `bonsai`, `js_of_ocaml`

## Run

    dune exec modules/hermes_wiki/test/test_hermes_wiki.exe        # the core laws
    dune exec modules/hermes_wiki/src/tools/gen_render_baseline.exe -- .   # re-pin (deliberate)

The knowledge discipline (PKM schema, mandatory ingestion, recall-before-
action) is documented in `pages/` and `import/*/rules/`.
