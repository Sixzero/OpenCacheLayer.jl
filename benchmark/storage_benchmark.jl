using BenchmarkTools
using JLD2
using SQLite
using LMDB
using Random
using Serialization

BenchmarkTools.DEFAULT_PARAMETERS.seconds = 0.50

# Test data generation
function generate_test_data(n)
    Dict(
        "key_$i" => rand(Float64, 100) for i in 1:n
    )
end

# Benchmark configurations
const SMALL_N = 100
const LARGE_N = 10_000
const test_data_small = generate_test_data(SMALL_N)
const test_data_large = generate_test_data(LARGE_N)

# Helper functions for each storage type
function bench_jld2(data, file="test_jld2.jld2")
    # Single key updates
    single_bench = @benchmarkable begin
        jldopen($file, "w") do f
            f[key] = value
        end
    end setup=(key = string(rand(1:1000)); value = rand(Float64, 100)) teardown=(rm($file, force=true))
    
    # Bulk updates
    bulk_bench = @benchmarkable begin
        jldopen($file, "w") do f
            for (k, v) in data_dict
                f[k] = v
            end
        end
    end setup=(data_dict = $data) teardown=(rm($file, force=true))
    
    run(single_bench), run(bulk_bench)
end

function bench_sqlite(data, file="test_sqlite.db")
    # Single key updates
    single_bench = @benchmarkable begin
        db = SQLite.DB($file)
        SQLite.execute(db, "CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY, value BLOB)")
        buf = IOBuffer()
        serialize(buf, value)
        blob = take!(buf)
        SQLite.execute(db, "INSERT OR REPLACE INTO cache VALUES (?, ?)", (key, blob))
        SQLite.close(db)
    end setup=(key = string(rand(1:1000)); value = rand(Float64, 100)) teardown=(rm($file, force=true))
    
    # Bulk updates
    bulk_bench = @benchmarkable begin
        db = SQLite.DB($file)
        SQLite.execute(db, "CREATE TABLE IF NOT EXISTS cache (key TEXT PRIMARY KEY, value BLOB)")
        SQLite.transaction(db) do
            for (k, v) in data_dict
                buf = IOBuffer()
                serialize(buf, v)
                blob = take!(buf)
                SQLite.execute(db, "INSERT OR REPLACE INTO cache VALUES (?, ?)", (k, blob))
            end
        end
        SQLite.close(db)
    end setup=(data_dict = $data) teardown=(rm($file, force=true))
    
    run(single_bench), run(bulk_bench)
end

function bench_lmdb(data, dir="test_lmdb")
    # Single key updates
    single_bench = @benchmarkable begin
        env = LMDB.create()
        open(env, $dir)
        txn = LMDB.start(env)
        dbi = LMDB.open(txn)
        buf = IOBuffer()
        serialize(buf, value)
        blob = take!(buf)
        LMDB.put!(txn, dbi, key, blob)
        LMDB.commit(txn)
        LMDB.close(env, dbi)
        LMDB.close(env)
    end setup=(begin
        mkpath($dir)
        key = string(rand(1:1000))
        value = rand(Float64, 100)
    end) teardown=(rm($dir, force=true, recursive=true))
    
    # Bulk updates
    bulk_bench = @benchmarkable begin
        env = LMDB.create()
        open(env, $dir)
        txn = LMDB.start(env)
        dbi = LMDB.open(txn)
        for (k, v) in data_dict
            buf = IOBuffer()
            serialize(buf, v)
            blob = take!(buf)
            LMDB.put!(txn, dbi, k, blob)
        end
        LMDB.commit(txn)
        LMDB.close(env, dbi)
        LMDB.close(env)
    end setup=(begin
        mkpath($dir)
        data_dict = $data
    end) teardown=(rm($dir, force=true, recursive=true))
    
    run(single_bench), run(bulk_bench)
end

# Print results in a nice format
function print_benchmark_results(title, single_bench, bulk_bench)
    println("\n", title)
    println("Single key update:")
    println("  Median time: ", median(single_bench.times) / 1e6, " ms")
    println("  Memory: ", single_bench.memory / 1024, " KB")
    
    println("\nBulk update:")
    println("  Median time: ", median(bulk_bench.times) / 1e6, " ms")
    println("  Memory: ", bulk_bench.memory / 1024, " KB")
end

# Run benchmarks
println("Running benchmarks with small dataset (n=$SMALL_N)...")
jld2_single_small, jld2_bulk_small = bench_jld2(test_data_small)
print_benchmark_results("JLD2 (Small Dataset)", jld2_single_small, jld2_bulk_small)

println("\nSQLite (Small Dataset):")
sqlite_single_small, sqlite_bulk_small = bench_sqlite(test_data_small)
print_benchmark_results("SQLite (Small Dataset)", sqlite_single_small, sqlite_bulk_small)

println("\nLMDB (Small Dataset):")
lmdb_single_small, lmdb_bulk_small = bench_lmdb(test_data_small)
print_benchmark_results("LMDB (Small Dataset)", lmdb_single_small, lmdb_bulk_small)

println("\nRunning benchmarks with large dataset (n=$LARGE_N)...")
jld2_single_large, jld2_bulk_large = bench_jld2(test_data_large)
print_benchmark_results("JLD2 (Large Dataset)", jld2_single_large, jld2_bulk_large)

println("\nSQLite (Large Dataset):")
sqlite_single_large, sqlite_bulk_large = bench_sqlite(test_data_large)
print_benchmark_results("SQLite (Large Dataset)", sqlite_single_large, sqlite_bulk_large)

println("\nLMDB (Large Dataset):")
lmdb_single_large, lmdb_bulk_large = bench_lmdb(test_data_large)
print_benchmark_results("LMDB (Large Dataset)", lmdb_single_large, lmdb_bulk_large)
