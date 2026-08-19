using Dates
using Base.Threads: ReentrantLock
using BoilerplateCvikli: @async_showerr

# Entries live in their own files, so nothing is loaded up front and a process only pays
# for the keys it touches. `cache` is a write-through memo of what this process has seen;
# the lock only ever guards that Dict, never disk.
struct DictCacheLayer{T<:ContentAdapter} <: AbstractCacheLayer
    adapter::T
    cache_dir::String
    cache::Dict{String,Any}
    mem_lock::ReentrantLock
end

DictCacheLayer(adapter::ContentAdapter, cache_dir::String=default_cache_dir(adapter)) =
    DictCacheLayer(adapter, cache_dir, Dict{String,Any}(), ReentrantLock())

# The write is synchronous: it only ever follows a network fetch, which dwarfs one small
# file write, and it keeps rm from racing an in-flight write.
function fetch!(cache::DictCacheLayer, key; kw...)
    content = get_content(cache.adapter, key; kw...)
    lock(() -> cache.cache[key] = content, cache.mem_lock)
    store_entry!(cache.cache_dir, key, content)
    content
end

function get_content(cache::DictCacheLayer, key; kw...)
    content = lock(() -> get(cache.cache, key, nothing), cache.mem_lock)
    if isnothing(content)
        # Not seen by this process — it may still be on disk from an earlier run
        content = read_entry(cache.cache_dir, key)
        # Entries written by the previous version were (content, stats...) tuples
        content isa NamedTuple && hasproperty(content, :content) && (content = content.content)
        isnothing(content) && return fetch!(cache, key; kw...)
        lock(() -> get!(cache.cache, key, content), cache.mem_lock)
    end

    status = is_cache_valid(content, cache.adapter)
    status === STALE && return fetch!(cache, key; kw...)

    status === ASYNC && @async_showerr try
        fetch!(cache, key; kw...)
    catch e
        @warn "Background refresh failed" key exception=e
    end
    content
end

function Base.rm(cache::DictCacheLayer)
    lock(() -> empty!(cache.cache), cache.mem_lock)
    rm(cache.cache_dir; force=true, recursive=true)
end
