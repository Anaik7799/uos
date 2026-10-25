# fp-core Rust Patterns

## Cargo

```toml
[dependencies]
fp-core = "0.1.9"
```

## Fold Instead of Mutable Accumulation

```rust
use fp_core::foldable::*;

pub fn total(values: Vec<i64>) -> i64 {
    values.reduce(0, |value, acc| value + acc)
}
```

When `fp_core::foldable::Foldable` is not implemented for a local type, use standard `Iterator::fold` and consider adding a lawful trait implementation only if reusable.

## Option / Result Chain

```rust
use fp_core::chain::*;

pub fn next_positive(value: Option<i64>) -> Option<i64> {
    value.chain(|item| (item >= 0).then_some(item + 1))
}
```

Prefer `map`, `and_then`/`chain`, `filter`, `transpose`, and `?` over nested `match`.

## Compose Transformations

```rust
use fp_core::compose::*;

fn trim(input: String) -> String { input.trim().to_owned() }
fn lowercase(input: String) -> String { input.to_lowercase() }

pub fn normalize(input: String) -> String {
    compose_two(lowercase, trim)(input)
}
```

Use composition where transformations are reusable and named.

## Pure Boundary

```rust
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Command {
    pub topic: String,
    pub payload: String,
}

pub fn build_command(topic: &str, payload: &str) -> Option<Command> {
    (!topic.is_empty() && !payload.is_empty()).then(|| Command {
        topic: topic.to_owned(),
        payload: payload.to_owned(),
    })
}
```

Keep IO wrappers small:

```rust
pub fn publish(topic: &str, payload: &str) -> anyhow::Result<()> {
    let command = build_command(topic, payload).ok_or_else(|| anyhow::anyhow!("invalid command"))?;
    publish_effect(command)
}
```

## Law Test Shape

```rust
#[test]
fn semigroup_associative() {
    let a = vec![1];
    let b = vec![2];
    let c = vec![3];
    assert_eq!((&a + &b) + &c, &a + &(&b + &c));
}
```

Use local equivalent laws for new `Semigroup`, `Monoid`, `Functor`, `Chain`, and `Lens` implementations.
