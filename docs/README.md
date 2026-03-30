# DataCaches.jl — Documentation

This directory contains the [Documenter.jl](https://documenter.juliadocs.org)
source for the DataCaches.jl documentation.

## Setup

Run once from the **repository root** to install the docs dependencies and
dev-link the local package into the docs environment:

```bash
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
```

Re-run this step after adding new dependencies to `docs/Project.toml`.

## Build

From the repository root:

```bash
julia --project=docs docs/make.jl
```

The generated HTML is written to `docs/build/` (git-ignored).

## View

Open the built site in your default browser:

```bash
# Linux
xdg-open docs/build/index.html

# macOS
open docs/build/index.html
```

Or just navigate to `docs/build/index.html` directly in a browser.

## Structure

| Path | Purpose |
|---|---|
| `make.jl` | Documenter build script |
| `Project.toml` | Docs-environment dependencies |
| `src/index.md` | Documentation homepage (intro + `@autodocs` API reference) |
| `build/` | Generated output (git-ignored) |
