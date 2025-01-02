using OpenCacheLayer
using Test
using Aqua

@testset "OpenCacheLayer.jl" begin
    @testset "Code quality (Aqua.jl)" begin
        Aqua.test_all(OpenCacheLayer)
    end
    # Write your tests here.
end
