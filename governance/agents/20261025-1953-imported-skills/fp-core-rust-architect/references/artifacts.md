# fp-core Rust Artifact Map

## Sources Checked

- GitHub: `https://github.com/JasonShin/fp-core.rs`
- Docs.rs: `https://docs.rs/fp-core`
- Docs.rs all items: `https://docs.rs/fp-core/latest/fp_core/all.html`
- Crate version observed: `fp-core 0.1.9`
- Installation from README: `fp-core = "0.1.9"`
- Local Firecrawl artifact: `/home/an/dev/ver/work/.firecrawl/fp-core-rust-artifacts.json`

## Crate Shape

Modules:

- `applicative`
- `apply`
- `chain`
- `comonad`
- `compose`
- `empty`
- `extend`
- `extract`
- `foldable`
- `functor`
- `hkt`
- `identity`
- `lens`
- `monad`
- `monoid`
- `pure`
- `semigroup`
- `setoid`

Traits:

- `Applicative`
- `Apply`
- `Chain`
- `Comonad`
- `Empty`
- `Extend`
- `Extract`
- `Foldable`
- `Functor`
- `HKT`
- `HKT3`
- `Lens`
- `Monad`
- `Monoid`
- `Pure`
- `Semigroup`
- `Setoid`

Macro/function utilities:

- `compose`
- `compose::compose_two`
- `foldable::fold_map`
- `identity::identity`

## C3I Guidance

- Use `fp-core` for functional abstractions but keep Rust safety and performance constraints intact.
- Prefer Rust standard iterator combinators when they already express the functional transformation; import `fp_core` for explicit typeclass/composition/fold/lens semantics and to satisfy the operator rule in touched logic.
- Do not blindly force `fp-core` into low-level unsafe/FFI glue; isolate that glue and keep adjacent pure logic functional.
- Add law tests for new algebraic abstractions when feasible.
