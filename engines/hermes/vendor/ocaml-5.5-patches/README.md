# OCaml 5.5 compatibility patches

These patches are external-dependency transforms, not ZigVM implementation
code. `scripts/setup_ocaml_550.ml` clones each upstream at the recorded base,
applies the corresponding patch with `git am`, verifies the resulting Git tree,
and pins the local source through opam.

The full `gen_js_api` upstream test graph also requires the external Binaryen
toolchain (`wasm-opt`) for `wasm_of_ocaml-compiler`. Install the host `binaryen`
package before running `scripts/setup_ocaml_550.ml --install`; setup remains
fail-closed when that declared depext is unavailable.

| Package | Upstream base | Expected tree | Patch |
|---|---|---|---|
| Jane Street preview repository | `6789b91abef324f0f9dc2a07332afc4843c7dbe5` | `3efc7b7407c07292ddb5f4726f1635131804b5e3` | `janestreet-opam/ocaml-5.5.patch` |
| base preview | `28d466710aa1858a70fd3c1fcbeae07a07ac8106` | `5a6bf70c4367fb055c89901dcf801e2b391988c6` | `base/ocaml-5.5.patch` |
| core preview | `dbceee5ddaf6b2fe88a9a395ffe9646b1c21f14a` | `896df751156646ba325cd8a45574007eaef2f123` | `core/ocaml-5.5.patch` |
| ppxlib 0.38.0 | `3a791083c612e91fa4e6a9660ef69776ea750324` | `94c2c37c31e50137f455ef13eca86eb7753fff15` | `ppxlib/ocaml-5.5.patch` |
| ppxlib_jane preview | `7b8f20f517f208f87a6349d791258d09df2b9209` | `1b10ae959a2c65a2150d92989da78a5c79825df3` | `ppxlib_jane/ocaml-5.5.patch` |
| ppx_template preview | `4c44de2ac26f17d4d284498540dfde1b710bfe00` | `d4910e0bbd4e07be054fe8aa1938201e8c68c72c` | `ppx_template/ocaml-5.5.patch` |
| ppx_deriving 6.0.3 | `275140702ca6f97e0407f80e86de9d3940ee3ac8` | `d2a22ada9e2a9ebbac26324f2062006580e7ddcd` | `ppx_deriving/ocaml-5.5.patch` |
| ppx_cold v0.17.0 | `150c14534f8bdafdda98f55f08ce414ec29d05d3` | `031b09c4b4b13782cea7c0a620b88970e57634f3` | `ppx_cold/ocaml-5.5.patch` |
| ppx_yojson_conv_lib preview | `5025d6179f17b11580512e1400912768d22779b2` | `5957dd61218aca9b3d8909c81f06ffeec1db411b` | `ppx_yojson_conv_lib/ocaml-5.5.patch` |
| gen_js_api 1.1.7 | `dcdd0b1dd852b4566745e864d98d95e4e838a763` | `6ddc2cc1139031db6ae19f5df4854048427c1d56` | `gen_js_api/ocaml-5.5.patch` |
| lwt_ppx 5.9.3 | `bfd18ca21965a348ff3fe0e09ffd822e07610cae` | `8ddd662aa566e0c744c9e0c35f61b4a5e2ef19f3` | `lwt/ocaml-5.5.patch` |
| ppx_expect preview | `54e2846ae50ffd72c00e528f62fb4a33948d0be2` | `5c8d0ddb36cc513f593e37fa76471d4de0672576` | `ppx_expect/ocaml-5.5.patch` |
| expect_test_helpers_base preview | `d5b095618eea6aefde4fdf143b99c0042f07aacc` | `a964831fa0f72c3d437af1f8f22f98467ff3dc19` | `expect_test_helpers_base/ocaml-5.5.patch` |
| expect_test_helpers_core preview | `83f95987c4fd1dcd8e6118038dcc07758f31dfff` | `d0ffc3fb674b406d721cf3be6ec25c4189eea12f` | `expect_test_helpers_core/ocaml-5.5.patch` |
| virtual_dom preview | `4e9549cdd71dc62f0e78917e088d607b219f1ba3` | `df8c6c56bfb9dc29322c1f28aed63b71a97c083c` | `virtual_dom/ocaml-5.5.patch` |
| bonsai preview | `f31661450eb133fe89564219d97669c2735c6622` | `3f66f7a5ef9d98756c7a3933859e0f113b36483c` | `bonsai/ocaml-5.5.patch` |
| bonsai_web preview | `989c18b5381cad767365923d4f0b758c6f3c602c` | `18b5aba22047129330d26d3c19d90fc50d6239de` | `bonsai_web/ocaml-5.5.patch` |
| Dream main | `2ce65e1010f2501f9319e8735eec8e1eeb676d4e` | `92a7f6e73842ebec54e5b9e528dffd64ba096392` | `dream/ocaml-5.5.patch` |
| stanc3 | `d9ed7977fd92f7fe1a737fd44ea44f22ee39472d` | `26272b0c35598ea7cd9a043243706d299a8b2f32` | `stanc3/ocaml-5.5.patch` |
| ocamlformat 0.29.0 | `195e470387ecdcfb0f9ce309b0d8d17807bde25d` | `288717170d7c4fc20de99079b3922a424a09c22c` | `ocamlformat/ocaml-5.5.patch` |
| ocaml-lsp-server 1.27.0 | `b90cbe7cdfb096eaf32df92b8db6681c428a5643` | `b58b67dd1066c9a34d4430a87414531cc34d3bb0` | `ocaml-lsp-server/ocaml-5.5.patch` |
| config 0.0.3 | `f850715406b2ea28bbbed76826f0b97c4f933857` | `12b2b031058b20b20111283f2e440fede9af751c` | `config/ocaml-5.5.patch` |
| riot 0.0.9 | `310a486` | `f968f524ffd1e2c1adbb018ef89154dc1b73c37a` | `riot/0001-fix-support-OCaml-5.5-runtime-stack.patch` |
| notty 0.2.3 | `e035d06` | `18a0c72af8886aed40fb2ca03b4f5c51948a12ea` | `notty/0001-Patch-out_width.patch` |
| bisect_ppx 2.8.3 | `2d8dffbbfc0c431a37319d4d9a143836c9ec542e` | `ba5c1cbc797e13f8582ed22958602173181779cc` | `bisect_ppx/ocaml-5.5.patch` |
| gluon 0.0.9 | `0b9e2f648ddb6e88fe13a3fa39e1644a53ba44d1` | `b0d46081c855908616792d5869da1e498ea75f4e` | none; upstream includes the explicit C cast fix |

| gospel 0.3.1 | `5597c61db68efe950b838832f412aa6a9c8e6229` | `1acfeaba9fea2eaa7ba1b4365edc0570f8424559` | `gospel/ocaml-5.5.patch` |
| ortac 0.8.0 | `a86251abd76694e2e444bc88ea5c05e342053db9` | `76b21618fa8d5c386e121baae0ed4e28814a23f6` | `ortac/ocaml-5.5.patch` |
| ppx_deriving_qcheck 0.9 | `6cdd8409ce373807e1b541ae420dc7eb45537e91` | `caefbf73faf0e26c78347ed1c941470fa0dadce7` | `ppx_deriving_qcheck/ocaml-5.5.patch` |

The expected tree is the semantic identity. Commit hashes created by `git am`
may differ because committer metadata is local; a tree mismatch fails closed.

## Specification toolchain: what was changed in the upstream libraries

**Read this before trusting a Gospel or Ortac verdict.** Three patches above are
not ordinary compatibility shims, and two of them CHANGE BEHAVIOUR rather than
just restoring compilation. Every altered site carries an inline comment naming
the reason; this section is the index so an agent does not have to find them.

### Direction of the port — the thing that surprises everyone

These libraries were **not** ported forward to OCaml 5.5. They were ported
**backwards**. Gospel, Ortac and ppx_deriving_qcheck target the OCaml 5.2+
parsetree, while this switch pins `ppxlib` to the `zigvm-ocaml-5.5-ast500`
branch, which exposes the OCaml **5.0** AST. Compiler-libs 5.5 does have
`Ptyp_open`; ppxlib-ast500 does not. **Every one of these patches breaks if the
ppxlib pin moves forward**, and that is the first thing to check when one of
them stops compiling.

Mechanical, behaviour-preserving changes (safe):

| Construct | Why it changed |
|---|---|
| `Ptyp_open` arms removed | absent from ast500's `core_type_desc`; the arms were unreachable |
| `Ptyp_alias` payload | ast500 carries a bare `string`, not a `string loc` — hence `tyvar` instead of `tyvar_loc` |
| `pvb_constraint` field | absent from ast500's `value_binding` |
| `Pmod_apply_unit` arm removed | absent from ast500; unit application is a plain `Pmod_apply` |
| `Pexp_function (params, c, body)` | rewritten to curried `Pexp_fun` plus `Pexp_function` over cases, preserving the parenthesisation invariant the 5.2 `functionrhs` flag carried |

### Behaviour-changing edits — the two that bound what a verdict means

Both are in `src/typing.ml` of Gospel, both are commented in place, and both
exist because Gospel v0.3.1 could not read the **OCaml 5.5 standard library** at
all: every interface reaches `camlinternalFormatBasics.mli` through Printf or
Format, and that file uses constructs v0.3.1 rejected outright.

1. **Explicit universal quantification is ERASED.** `Ptyp_poly (vars, ct)` used
   to be a hard error; it now binds the quantified names as ordinary type
   variables and recurses into the body. Gospel's type language has no rank-n
   types, so the quantifier is not modelled — it is dropped.
2. **Polymorphic variants are admitted as OPAQUE.** `Ptyp_variant` used to be a
   hard error; it now yields a fresh type variable, exactly as `Ptyp_any` does.

**The consequence, stated plainly: a specification written about a
polymorphic-variant value is checked against an unknown type and therefore
constrains nothing.** This is an approximation, not support. It is admissible
only because the constructs actually reached are stdlib internals that no
specification refers to. **This bound must travel with any Gospel verdict cited
as evidence** — a green `gospel check` is not a claim about polymorphic-variant
code.

### Operational constraint found by the gate

`gospel check` writes a `.gospel` artifact **next to its input**. `harness/` is
OCaml-only by hard boundary, so running it there turns the gate red. Any wiring
of Gospel into the harness must direct output outside `harness/`; this was found
by `check_boundaries`, not by inspection.

### Cameleer and Why3gospel — vendored, NOT built, and why

Both are cloned under `third_party/` for reference and both are **disposition
`Unavailable_observed`**, with the reason measured rather than assumed:

- **why3gospel** (`aa4513e`, last upstream commit **2021-11-09**) expects a
  Gospel API roughly five years old: it references `lsymbol` and `ls_name`,
  which no longer exist.
- **cameleer** (`d9899b8`, 2026-03-11) references `Uast.s_structure`,
  `Uast.s_value_binding` and `sp_variant`. None of these appears in Gospel
  0.2.0, 0.3.0 or 0.3.1 — verified by grep over each tag, not inferred.

Ortac requires the v0.3.x API, so a single Gospel version cannot satisfy Ortac
and these two simultaneously. Making either build is **not** a mechanical AST
port like the patches above; it is a rewrite across Gospel API generations.
Recorded here so the next agent does not rediscover it at the same cost.
