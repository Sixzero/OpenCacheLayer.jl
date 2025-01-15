using OpenCacheLayer
using OpenCacheLayer: get_cache_path
using Test
using Aqua
using Dates

include("test_adapter.jl")

@testset failfast=true  "OpenCacheLayer.jl" begin
    # @testset "Code quality (Aqua.jl)" begin
        # Aqua.test_all(OpenCacheLayer)
    # end

    @testset "VectorCacheLayer" begin
        adapter = TestAdapter()
        cache = VectorCacheLayer(adapter)
        try 
        base_date = DateTime(2024, 1, 1)
        
        # Test case 1: No cached data
        items = get_content(cache; from=base_date, to=base_date+Day(2))
        @show items
        @test length(items) == 3  # 3 days of messages
        @test all(item.timestamp >= base_date for item in items)
        @test all(item.timestamp <= base_date+Day(2) for item in items)
        
        # Test case 2: Query within cached range
        items = get_content(cache; from=base_date+Day(1), to=base_date+Day(2))
        @show items
        @test length(items) == 2  # 2 days of messages
        @test all(item.timestamp >= base_date+Day(1) for item in items)
        @test all(item.timestamp <= base_date+Day(2) for item in items)
        
        # Test case 3: Query before cached range
        items = get_content(cache; from=base_date-Day(2), to=base_date+Day(1))
        @test length(items) == 4  # 4 days of messages
        @test all(item.timestamp >= base_date-Day(2) for item in items)
        @test all(item.timestamp <= base_date+Day(1) for item in items)
        
        # Cleanup using the safe rm method
        finally
        rm(cache)
        end
    end
end
;