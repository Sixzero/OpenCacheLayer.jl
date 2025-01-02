using OpenCacheLayer
using Documenter

DocMeta.setdocmeta!(OpenCacheLayer, :DocTestSetup, :(using OpenCacheLayer); recursive=true)

makedocs(;
    modules=[OpenCacheLayer],
    authors="SixZero <havliktomi@hotmail.com> and contributors",
    sitename="OpenCacheLayer.jl",
    format=Documenter.HTML(;
        canonical="https://sixzero.github.io/OpenCacheLayer.jl",
        edit_link="master",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

deploydocs(;
    repo="github.com/sixzero/OpenCacheLayer.jl",
    devbranch="master",
)
