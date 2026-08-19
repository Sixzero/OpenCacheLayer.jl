using Dates
using Base.Threads: ReentrantLock

# One file per message. The whole set is loaded up front because every query needs the
# cached span (min/max timestamp) to decide what is missing — unlike the Dict layer,
# there is no single key to look up.
struct VectorCacheLayer{T<:ContentAdapter} <: AbstractCacheLayer
    adapter::T
    cache_dir::String
    max_age::Period
    items::Vector{AbstractMessage}
    pending_writes::Vector{Task}
    mem_lock::ReentrantLock
end

function VectorCacheLayer(adapter::ContentAdapter, cache_dir::String=default_cache_dir(adapter, "_v2");
                          max_age::Period=Day(30))
    items = AbstractMessage[v for (_, v) in read_all_entries(cache_dir) if v isa AbstractMessage]
    VectorCacheLayer(adapter, cache_dir, max_age, items, Task[], ReentrantLock())
end

item_id(item::AbstractMessage) = string(something(get_unique_id(item), hash(item)))

function append_to_store!(cache::VectorCacheLayer, items::Vector{<:AbstractMessage})
    # Dedupe and append in one critical section, so a concurrent reader never observes
    # the vector mid-append. `known` grows as we go, so a batch containing the same id
    # twice still only adds it once.
    new_items = lock(cache.mem_lock) do
        known = Set(item_id(item) for item in cache.items)
        fresh = filter(item -> item_id(item) ∉ known && (push!(known, item_id(item)); true), items)
        append!(cache.items, fresh)
        fresh
    end
    isempty(new_items) && return new_items

    track_write!(cache) do
        for item in new_items
            store_entry!(cache.cache_dir, item_id(item), item)
        end
    end
    new_items
end

function get_content(cache::VectorCacheLayer; from::DateTime=now() - Day(1), to::DateTime=now(), kw...)
    cached = lock(() -> copy(cache.items), cache.mem_lock)

    if isempty(cached)
        append_to_store!(cache, get_content(cache.adapter; from, to, kw...))
    else
        earliest = minimum(get_timestamp(item) for item in cached)
        latest = maximum(get_timestamp(item) for item in cached)
        # Only the ends of the requested range can be missing; the cached span is covered
        from < earliest && append_to_store!(cache,
            get_content(cache.adapter; from, to=supports_time_range(cache.adapter) ? earliest : to, kw...))
        to > latest && append_to_store!(cache, get_content(cache.adapter; from=latest, to, kw...))
    end

    lock(cache.mem_lock) do
        filter(item -> from <= get_timestamp(item) <= to, cache.items)
    end
end

function Base.rm(cache::VectorCacheLayer)
    wait(cache)  # else a queued write recreates a file we are about to delete
    lock(() -> empty!(cache.items), cache.mem_lock)
    rm(cache.cache_dir; force=true, recursive=true)
end
