using BenchmarkTools
using JLD2
using Random
using Dates

BenchmarkTools.DEFAULT_PARAMETERS.seconds = 0.50

# Test data generation
function generate_time_series_data(n)
    start_time = now() - Day(n)
    [(timestamp = start_time + Hour(i), value = rand(Float64, 100)) for i in 1:n]
end

# Test data generation for Dict approach
function generate_time_series_data_with_ids(n)
    start_time = now() - Day(n)
    Dict(
        string(i) => (timestamp = start_time + Hour(i), value = rand(Float64, 100))
        for i in 1:n
    )
end

# Benchmark configurations
const SMALL_N = 100
const LARGE_N = 10_000
const test_data_small = generate_time_series_data(SMALL_N)
const test_data_large = generate_time_series_data(LARGE_N)
const test_data_small_dict = generate_time_series_data_with_ids(SMALL_N)
const test_data_large_dict = generate_time_series_data_with_ids(LARGE_N)

# New Dict-based approach
function bench_jld2_dict(initial_data, new_data, file="test_dict.jld2")
    append_bench = @benchmarkable begin
        jldopen($file, "r+") do f
            existing = copy(f["data"])  # Make a copy of the existing data
            merge!(existing, $new_data) # Merge new data into the copy
            delete!(f, "data")         # Delete existing data
            f["data"] = existing       # Write merged data
        end
    end setup=(data = jldopen($file, "w") do f
        f["data"] = $initial_data
    end) teardown=(rm($file, force=true))
    
    run(append_bench)
end

# Full rewrite approach
function bench_jld2_rewrite(initial_data, new_data, file="test_rewrite.jld2")
    append_bench = @benchmarkable begin
        existing_data = jldopen($file, "r") do f
            f["data"]
        end
        jldopen($file, "w") do f
            f["data"] = vcat(existing_data, $new_data)
        end
    end setup=(data=jldopen($file, "w") do f
        f["data"] = $initial_data
    end) teardown=(rm($file, force=true))
    
    run(append_bench)
end

# Append mode approach
function bench_jld2_append(initial_data, new_data, file="test_append.jld2")
    append_bench = @benchmarkable begin
        jldopen($file, "a+") do f
            current_n = length(f["data"])
            for (i, data) in enumerate($new_data)
                key = "data/$(current_n+i)"
                !haskey(f, key) && (f[key] = data)
            end
        end
    end setup=(data = jldopen($file, "w") do f
            for (i, data) in enumerate($initial_data)
                f["data/$i"] = data
            end
    end) teardown=(rm($file, force=true))
    
    run(append_bench)
end

function print_results(title, bench)
    println("\n", title)
    println("  Median time: ", median(bench.times) / 1e6, " ms")
    println("  Memory: ", bench.memory / 1024, " KB")
    println("  Allocations: ", bench.allocs)
end

# Generate append data (10% of original size)
small_append = generate_time_series_data(SMALL_N ÷ 10)
large_append = generate_time_series_data(LARGE_N ÷ 10)
small_append_dict = generate_time_series_data_with_ids(SMALL_N ÷ 10)
large_append_dict = generate_time_series_data_with_ids(LARGE_N ÷ 10)

println("\nRunning append benchmarks with small dataset (n=$SMALL_N)...")
println("Append size: $(length(small_append)) items")

rewrite_small = bench_jld2_rewrite(test_data_small, small_append)
print_results("Full Rewrite (Small Dataset)", rewrite_small)

append_small = bench_jld2_append(test_data_small, small_append)
print_results("Append Mode (Small Dataset)", append_small)

dict_small = bench_jld2_dict(test_data_small_dict, small_append_dict)
print_results("Dict Mode (Small Dataset)", dict_small)

println("\nRunning append benchmarks with large dataset (n=$LARGE_N)...")
println("Append size: $(length(large_append)) items")

rewrite_large = bench_jld2_rewrite(test_data_large, large_append)
print_results("Full Rewrite (Large Dataset)", rewrite_large)

append_large = bench_jld2_append(test_data_large, large_append)
print_results("Append Mode (Large Dataset)", append_large)

dict_large = bench_jld2_dict(test_data_large_dict, large_append_dict)
print_results("Dict Mode (Large Dataset)", dict_large)

# Compare file sizes
println("\nComparing file sizes:")
jldopen("test_rewrite.jld2", "w") do f
    f["data"] = test_data_large
end
jldopen("test_append.jld2", "w") do f
    f["data/1"] = test_data_large
end
jldopen("test_dict.jld2", "w") do f
    f["data"] = test_data_large_dict
end

println("  Rewrite file size: ", filesize("test_rewrite.jld2") / 1024^2, " MB")
println("  Append file size: ", filesize("test_append.jld2") / 1024^2, " MB")
println("  Dict file size: ", filesize("test_dict.jld2") / 1024^2, " MB")

rm("test_rewrite.jld2", force=true)
rm("test_append.jld2", force=true)
rm("test_dict.jld2", force=true)
