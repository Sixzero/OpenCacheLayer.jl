using Dates
using Base.Threads: ReentrantLock
using BoilerplateCvikli: @async_showerr, @typeof

# Entries live in their own files, so nothing is loaded up front and a process only pays
# for the keys it touches. `cache` is a write-through memo of what this process has seen;
# mem_lock only ever guards that Dict, never disk.
struct DictCacheLayer{T<:ContentAdapter} <: AbstractCacheLayer
    adapter::T
    cache_dir::String
    cache::Dict{String,NamedTuple}
    pending_writes::Vector{Task}
    mem_lock::ReentrantLock
end

DictCacheLayer(adapter::ContentAdapter, cache_dir::String=default_cache_dir(adapter)) =
    DictCacheLayer(adapter, cache_dir, Dict{String,NamedTuple}(), Task[], ReentrantLock())

# Persisting is async to keep get_content off the disk path, so nothing else can observe
# when an entry actually lands. wait(cache) drains the queue — rm needs it, an in-flight
# write would recreate a file it just deleted.
function track_write!(f, cache::AbstractCacheLayer)
    task = @async_showerr f()
    lock(cache.mem_lock) do
        filter!(!istaskdone, cache.pending_writes)  # keep the queue bounded
        push!(cache.pending_writes, task)
    end
end

function Base.wait(cache::AbstractCacheLayer)
    while true
        pending = lock(() -> filter(!istaskdone, cache.pending_writes), cache.mem_lock)
        isempty(pending) && return
        foreach(wait, pending)  # a write can queue another, so loop until quiet
    end
end

# Access stats stay in memory: persisting them rewrote the entry on every read, which
# kept a write in flight almost permanently. The read-modify-write happens in one
# critical section, so a concurrent hit cannot lose an increment.
function touch_entry!(cache::DictCacheLayer, key)
    lock(cache.mem_lock) do
        entry = get(cache.cache, key, nothing)
        isnothing(entry) && return nothing
        cache.cache[key] = merge(entry, (accessed_at=now(), hits=entry.hits + 1))
    end
end

# A key this process has not seen yet may still be on disk from an earlier run or another
# process — that is the only read that touches the filesystem. The disk copy is stale by
# construction (stats live in memory), so it must never overwrite an entry another task
# put there while we were reading.
function load_entry!(cache::DictCacheLayer, key)
    entry = read_entry(cache.cache_dir, key)
    entry isa NamedTuple || return nothing
    lock(cache.mem_lock) do
        current = get(cache.cache, key, nothing)
        isnothing(current) || return current
        cache.cache[key] = merge(entry, (accessed_at=now(), hits=entry.hits + 1))
    end
end

function fetch!(cache::DictCacheLayer, key, previous; kw...)
    content = get_content(cache.adapter, key; kw...)
    entry = isnothing(previous) ?
        (content=content, created_at=now(), accessed_at=now(), refreshed_at=now(), hits=1) :
        merge(previous, (content=content, refreshed_at=now()))
    lock(() -> cache.cache[key] = entry, cache.mem_lock)
    track_write!(cache) do
        store_entry!(cache.cache_dir, key, entry)
    end
    content
end

function get_content(cache::DictCacheLayer, key; kw...)
    # Only fall through to disk on a memory miss: `something` would read on every hit
    entry = touch_entry!(cache, key)
    isnothing(entry) && (entry = load_entry!(cache, key))
    isnothing(entry) && return fetch!(cache, key, nothing; kw...)

    status = is_cache_valid(entry.content, cache.adapter)
    status === STALE && return fetch!(cache, key, entry; kw...)

    status === ASYNC && @async_showerr try
        fetch!(cache, key, entry; kw...)
    catch e
        @warn "Background refresh failed" key exception=e
    end
    entry.content
end

function Base.rm(cache::DictCacheLayer)
    wait(cache)  # else a queued write recreates a file we are about to delete
    lock(() -> empty!(cache.cache), cache.mem_lock)
    rm(cache.cache_dir; force=true, recursive=true)
end
