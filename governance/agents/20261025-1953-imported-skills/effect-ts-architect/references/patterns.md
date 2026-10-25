# Effect TS Patterns

## Internal Effect, External Promise

```ts
import { Effect, pipe } from "effect"

export const fetchJsonEffect = (url: string): Effect.Effect<unknown, Error> =>
  Effect.tryPromise({
    try: async () => {
      const response = await fetch(url)
      return response.json()
    },
    catch: (reason) => reason instanceof Error ? reason : new Error(String(reason))
  })

export const fetchJson = (url: string): Promise<unknown> =>
  Effect.runPromise(fetchJsonEffect(url))
```

Use the `Promise` wrapper only where the host API requires it.

## Option for Missing Values

```ts
import { Option, pipe } from "effect"

export const firstNonEmpty = (values: readonly string[]): Option.Option<string> =>
  pipe(values, Option.liftPredicate((items) => items.length > 0), Option.map((items) => items[0]!))
```

Do not add new `null`/`undefined` branch cascades for business logic.

## Schema Boundary

```ts
import { Effect, Schema, pipe } from "effect"

const Payload = Schema.Struct({
  id: Schema.String,
  count: Schema.Number
})

export const decodePayload = (input: unknown) =>
  pipe(
    Schema.decodeUnknown(Payload)(input),
    Effect.mapError((parseError) => new Error(String(parseError)))
  )
```

Decode env/config/API/MCP/JSON once at the boundary.

## Layer Service

```ts
import { Context, Effect, Layer } from "effect"

interface Vault {
  readonly get: (name: string) => Effect.Effect<string, Error>
}

export class VaultService extends Context.Tag("VaultService")<VaultService, Vault>() {}

export const VaultLive = Layer.succeed(VaultService, {
  get: (name) => Effect.fail(new Error(`missing secret: ${name}`))
})
```

Use `Layer`/`Context` when a dependency crosses module boundaries.

## Retry and Timeout

```ts
import { Duration, Effect, Schedule, pipe } from "effect"

export const withRetry = <A, E, R>(effect: Effect.Effect<A, E, R>) =>
  pipe(
    effect,
    Effect.timeoutFail({
      duration: Duration.seconds(10),
      onTimeout: () => new Error("timeout")
    }),
    Effect.retry(Schedule.exponential(Duration.millis(100)).pipe(Schedule.compose(Schedule.recurs(3))))
  )
```

Use `Schedule` and `Duration`, not hand-rolled timers.

## Browser IIFE

- Source lives in TS.
- Source imports from `effect`.
- Browser-loaded output is an esbuild IIFE bundle.
- No new raw `.js` logic.
- Selectors live in typed constants.

## Platform HTTP API

Use when TypeScript owns the API contract:

```ts
import { HttpApi, HttpApiBuilder, HttpApiEndpoint, HttpApiGroup } from "@effect/platform"
import { Effect, Layer, Schema } from "effect"

const Api = HttpApi.make("Api").add(
  HttpApiGroup.make("Health").add(
    HttpApiEndpoint.get("health")`/health`.addSuccess(Schema.Struct({ ok: Schema.Boolean }))
  )
)

const HealthLive = HttpApiBuilder.group(Api, "Health", (handlers) =>
  handlers.handle("health", () => Effect.succeed({ ok: true }))
)

export const ApiLive = HttpApiBuilder.api(Api).pipe(Layer.provide(HealthLive))
```

## RPC Group

Use when TypeScript owns both sides of a request group:

```ts
import { Rpc, RpcGroup } from "@effect/rpc"
import { Effect, Schema } from "effect"

class User extends Schema.Class<User>("User")({
  id: Schema.String,
  name: Schema.String
}) {}

export class UserRpcs extends RpcGroup.make(
  Rpc.make("UserById", {
    payload: { id: Schema.String },
    success: User,
    error: Schema.String
  })
) {}

export const handlers = UserRpcs.toLayer(
  Effect.succeed({
    UserById: ({ id }) => Effect.succeed(new User({ id, name: "Ada" }))
  })
)
```

## SQL Service

Keep SQL behind a service layer:

```ts
import { SqlClient } from "@effect/sql"
import { Effect, Schema } from "effect"

class Person extends Schema.Class<Person>("Person")({
  id: Schema.Number,
  name: Schema.String
}) {}

export const findPeople = Effect.gen(function* () {
  const sql = yield* SqlClient.SqlClient
  return yield* sql<ReadonlyArray<Person>>`SELECT id, name FROM people`
})
```

## Effect Tests

When `@effect/vitest` is available:

```ts
import { it, expect } from "@effect/vitest"
import { Effect } from "effect"

it.effect("computes inside Effect", () =>
  Effect.gen(function* () {
    const value = yield* Effect.succeed(2)
    expect(value).toBe(2)
  })
)
```

## Migration from fp-ts

| fp-ts | Effect |
|-------|--------|
| `TaskEither<E, A>` | `Effect.Effect<A, E, never>` |
| `Option<A>` | `Option.Option<A>` from `effect` |
| `Either<E, A>` | `Either.Either<A, E>` from `effect` |
| `pipe` from `fp-ts/function` | `pipe` from `effect` |
| `TE.tryCatch` | `Effect.tryPromise` |
| `E.getOrElse` | `Either.match` or `Effect.catchAll` |
