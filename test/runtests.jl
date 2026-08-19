using OpenCacheLayer
using OpenCacheLayer: entry_path, read_entry, store_entry!
using Test
using Aqua
using Dates

include("test_adapter.jl")

@testset failfast=true  "OpenCacheLayer.jl" begin
    # @testset "Code quality (Aqua.jl)" begin
        # Aqua.test_all(OpenCacheLayer)
    # end

    @testset "a torn write cannot damage a stored entry" begin
        mktempdir() do dir
            store_entry!(dir, "k", (content="good", hits=1))

            # What a process killed mid-write leaves behind: a half-written temp file.
            # The rename never happened, so the entry itself must be untouched.
            write(joinpath(dir, "jl_halfwritten"), rand(UInt8, 64))
            @test read_entry(dir, "k").content == "good"

            # A damaged entry is a miss, not an error. It is left on disk: "unreadable"
            # also covers a content type this process cannot load, and deleting on that
            # would discard an entry another process reads fine. A refetch replaces it.
            path = entry_path(dir, "k")
            write(path, rand(UInt8, 64))
            @test read_entry(dir, "k") === nothing
            @test isfile(path)
            store_entry!(dir, "k", (content="refetched", hits=1))
            @test read_entry(dir, "k").content == "refetched"
        end
    end

    @testset "concurrent writers across processes" begin
        mktempdir() do dir
            # Two processes writing the same directory is exactly the overlapping-deploy
            # case that used to tear the single shared file
            writer = """
            using OpenCacheLayer: store_entry!
            for i in 1:100
                store_entry!($(repr(dir)), "p\$(ARGS[1])_\$i", (content="v\$i", hits=1))
            end
            """
            procs = [run(`$(Base.julia_cmd()) --startup-file=no --project=$(dirname(@__DIR__)) -e $writer $p`; wait=false)
                     for p in 1:2]
            foreach(wait, procs)
            @test all(p -> p.exitcode == 0, procs)

            for p in 1:2, i in 1:100
                @test read_entry(dir, "p$(p)_$i").content == "v$i"
            end
        end
    end

    @testset "DictCacheLayer" begin
        mktempdir() do dir
            cache = DictCacheLayer(KeyedTestAdapter(), joinpath(dir, "cache"))

            @test get_content(cache, "a").value == "content for a"
            @test cache.cache["a"].hits == 1
            @test get_content(cache, "a").value == "content for a"  # served from memory
            @test cache.cache["a"].hits == 2

            # Entries survive a reload from disk, and load lazily: a fresh layer starts
            # empty and only pulls in the key it is asked for
            wait(cache)
            reloaded = DictCacheLayer(KeyedTestAdapter(), cache.cache_dir)
            @test isempty(reloaded.cache)
            @test get_content(reloaded, "a").value == "content for a"
            # Stats are memory-only, so disk still holds the hits=1 from the first fetch:
            # the reload continues from there rather than starting over
            @test reloaded.cache["a"].hits == 2

            rm(cache)
            @test isempty(cache.cache)
            @test !isdir(cache.cache_dir)
        end
    end

    @testset "DictCacheLayer concurrent access" begin
        Threads.nthreads() == 1 && @warn "Running single-threaded: the concurrency test cannot catch races"
        mktempdir() do dir
            cache = DictCacheLayer(KeyedTestAdapter(), joinpath(dir, "cache"))

            # Hammer the shared Dict from many tasks: an unguarded setindex! can rehash
            # while another task reads, which throws or loses entries
            keys_used = ["key_$i" for i in 1:200]
            @sync for k in keys_used
                Threads.@spawn get_content(cache, k)
            end
            @test length(cache.cache) == length(keys_used)

            # Same key from every task: hits is a read-modify-write, so an increment is
            # lost unless the whole update happens in one critical section
            hammered = "key_1"
            before = cache.cache[hammered].hits
            @sync for _ in 1:200
                Threads.@spawn get_content(cache, hammered)
            end
            @test cache.cache[hammered].hits == before + 200

            # Writes are fire-and-forget: drain them before mktempdir pulls the dir out
            # from under an in-flight write
            rm(cache)
        end
    end

    @testset "VectorCacheLayer" begin
        mktempdir() do dir
            cache = VectorCacheLayer(TestAdapter(), joinpath(dir, "cache"))
            base_date = DateTime(2024, 1, 1)

            # No cached data yet
            items = get_content(cache; from=base_date, to=base_date+Day(2))
            @test length(items) == 3  # one message per day
            @test all(base_date <= item.timestamp <= base_date+Day(2) for item in items)

            # Query within the cached range
            items = get_content(cache; from=base_date+Day(1), to=base_date+Day(2))
            @test length(items) == 2
            @test all(base_date+Day(1) <= item.timestamp <= base_date+Day(2) for item in items)

            # Query reaching before the cached range
            items = get_content(cache; from=base_date-Day(2), to=base_date+Day(1))
            @test length(items) == 4
            @test all(base_date-Day(2) <= item.timestamp <= base_date+Day(1) for item in items)

            # Items survive a reload from disk
            wait(cache)
            reloaded = VectorCacheLayer(TestAdapter(), cache.cache_dir)
            @test length(reloaded.items) == length(cache.items)

            rm(cache)
            @test isempty(cache.items)
            @test !isdir(cache.cache_dir)
        end
    end

    @testset "VectorCacheLayer skips only the unreadable item" begin
        mktempdir() do dir
            cache = VectorCacheLayer(TestAdapter(), joinpath(dir, "cache"))
            get_content(cache; from=DateTime(2024, 1, 1), to=DateTime(2024, 1, 3))
            wait(cache)

            # One damaged file used to quarantine the whole store; now it costs one item
            damaged = first(filter(endswith(".jld2"), readdir(cache.cache_dir; join=true)))
            write(damaged, rand(UInt8, 64))
            reloaded = VectorCacheLayer(TestAdapter(), cache.cache_dir)
            @test length(reloaded.items) == length(cache.items) - 1

            rm(cache)
        end
    end
end
;
