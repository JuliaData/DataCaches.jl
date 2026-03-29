```@meta
CurrentModule = DataCaches
```

# DataCaches.jl

[![CI](https://github.com/JuliaData/DataCaches.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/JuliaData/DataCaches.jl/actions/workflows/CI.yml)
[![Documentation (stable)](https://img.shields.io/badge/docs-stable-blue.svg)](https://JuliaData.github.io/DataCaches.jl/stable)
[![Documentation (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://JuliaData.github.io/DataCaches.jl/dev)

A lightweight, file-backed key-value cache for Julia workflows that make
frequent expensive function calls (remote API queries, long-running
computations) and need results available across Julia sessions.

Three caching levels are provided, from manual to fully automatic:

| Level     | Mechanism              | Persistence      | Library integration required? |
|-----------|------------------------|------------------|-------------------------------|
| Explicit  | `dc["label"] = result` | Across sessions  | No                            |
| Memoized  | `@filecache`           | Across sessions  | No                            |
| Memoized  | `@memcache`            | In-session only  | No                            |
| Automatic | `set_autocaching!`        | Across sessions  | Yes                           |

## Installation

At the Julia REPL, press `]` to enter package manager mode:

```
pkg> add DataCaches
```

## Quick Start

```julia
using DataCaches

dc = DataCache(joinpath(homedir(), ".datacaches", "myproject"))

dc["dinosaurs"] = some_expensive_query(; taxon = "Dinosauria")
df = dc["dinosaurs"]
```

## API Reference

```@index
```

```@autodocs
Modules = [DataCaches]
```
