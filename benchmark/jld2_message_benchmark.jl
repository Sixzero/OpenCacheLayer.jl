using BenchmarkTools
using JLD2
using Random
using Dates

BenchmarkTools.DEFAULT_PARAMETERS.seconds = 0.50

struct SomeMessage
    timestamp::DateTime
    value::Vector{Float64}
    text::String
end

# Test data generation
function generate_messages(n)
    start_time = now() - Day(n)
    texts = ["Hello", "World", "Testing", "Message", "Content"]
    SomeMessage[
        SomeMessage(
            start_time + Hour(i), 
            rand(Float64, 100),
            rand(texts) * " " * string(i)
        ) for i in 1:n
    ]
end

# Benchmark configurations
const SMALL_N = 100
const LARGE_N = 10_000
const test_data_small_msg = generate_messages(SMALL_N)
const test_data_large_msg = generate_messages(LARGE_N)

# Full rewrite approach
function bench_jld2_rewrite(initial_data, new_data, file="test_rewrite.jld2")
    append_bench = @benchmarkable begin
        existing_data = jldopen($file, "r") do f
            f["messages"]
        end
        jldopen($file, "w") do f
            f["messages"] = vcat(existing_data, $new_data)
        end
    end setup=(
        jldopen($file, "w") do f
            f["messages"] = $initial_data
        end
    ) teardown=(rm($file, force=true))
    
    run(append_bench)
end

# Append mode approach
function bench_jld2_append(initial_data, new_data, file="test_append.jld2")
    append_bench = @benchmarkable begin
        jldopen($file, "a+") do f
            f["messages/$(length(f["messages"])+1)"] = $new_data
        end
    end setup=(
        jldopen($file, "w") do f
            for (i, msg) in enumerate($initial_data)
                f["messages/$i"] = msg
            end
        end
    ) teardown=(rm($file, force=true))
    
    run(append_bench)
end

function print_results(title, bench)
    println("\n", title)
    println("  Median time: ", median(bench.times) / 1e6, " ms")
    println("  Memory: ", bench.memory / 1024, " KB")
end

# Generate append data (10% of original size)
small_append = generate_messages(SMALL_N ÷ 10)
large_append = generate_messages(LARGE_N ÷ 10)

println("\nRunning append benchmarks with small dataset (n=$SMALL_N)...")
println("Append size: $(length(small_append)) items")

rewrite_small = bench_jld2_rewrite(test_data_small_msg, small_append)
print_results("Full Rewrite (Small Dataset)", rewrite_small)

append_small = bench_jld2_append(test_data_small_msg, small_append)
print_results("Append Mode (Small Dataset)", append_small)

println("\nRunning append benchmarks with large dataset (n=$LARGE_N)...")
println("Append size: $(length(large_append)) items")

rewrite_large = bench_jld2_rewrite(test_data_large_msg, large_append)
print_results("Full Rewrite (Large Dataset)", rewrite_large)

append_large = bench_jld2_append(test_data_large_msg, large_append)
print_results("Append Mode (Large Dataset)", append_large)
