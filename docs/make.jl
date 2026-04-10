using DataCaches
using Documenter

DocMeta.setdocmeta!(DataCaches, :DocTestSetup, :(using DataCaches); recursive=true)

makedocs(;
    modules=[DataCaches, DataCaches.Caches, DataCaches.CacheAssets],
    authors="Jeet Sukumaran <jeetsukumaran@gmail.com>",
    sitename="DataCaches.jl",
    format=Documenter.HTML(;
        canonical="https://JuliaData.github.io/DataCaches.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home"                => "index.md",
        "API Reference"       => "api.md",
        "Caches"              => "caches.md",
        "Cache Assets"        => "cache_assets.md",
        "Library Integration" => "integration.md",
    ],
)

deploydocs(;
    repo="github.com/JuliaData/DataCaches.jl",
    devbranch="main",
)
