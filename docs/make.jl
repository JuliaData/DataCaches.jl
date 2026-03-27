using DataCaches
using Documenter

DocMeta.setdocmeta!(DataCaches, :DocTestSetup, :(using DataCaches); recursive=true)

makedocs(;
    modules=[DataCaches],
    authors="Jeet Sukumaran <jeetsukumaran@gmail.com>",
    sitename="DataCaches.jl",
    format=Documenter.HTML(;
        canonical="https://jeetsukumaran.github.io/DataCaches.jl",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/jeetsukumaran/DataCaches.jl",
    devbranch="main",
)
