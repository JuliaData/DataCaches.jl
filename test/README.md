# DataCaches.jl — Tests

The test suite lives in `runtests.jl` and uses Julia's built-in `Test`
standard library.

## Setup

Run once from the **repository root** to instantiate the test environment:

```bash
julia --project=test -e 'import Pkg; Pkg.instantiate()'
```

## Run all tests

From the repository root (recommended — uses the package manager's test
integration, which handles environment setup automatically):

```bash
julia -e 'import Pkg; Pkg.test("DataCaches")'
```

Or, using the package manager REPL mode (press `]` at the Julia prompt):

```
pkg> test DataCaches
```

## Run tests directly

To iterate quickly without going through `Pkg.test`:

```bash
julia --project=test test/runtests.jl
```

## Test environment

| Package | Purpose |
|---|---|
| `Test` | Julia standard-library test framework (`@test`, `@testset`) |
| `DataFrames` | Required to exercise DataFrame caching paths |
| `Aqua` | (Available) Automated code quality checks |
| `JET` | (Available) Static type-inference analysis |
