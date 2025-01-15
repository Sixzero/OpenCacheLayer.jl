using Dates
using JLD2
using BaseDirs
using SHA
using Base.Threads: ReentrantLock

mutable struct VectorCacheLayer{T<:ContentAdapter} <: AbstractCacheLayer
    adapter::T
    cache_dir::String
    max_age::Period
    cache::Union{Dict{String,Vector{AbstractMessage}},Nothing}
    file_lock::ReentrantLock
end

function VectorCacheLayer(adapter::T; max_age::Period=Day(30)) where T<:ContentAdapter
    project = BaseDirs.Project("OpenCacheLayer")
    cache_dir = BaseDirs.User.cache(project; create=true)
    VectorCacheLayer(adapter, cache_dir, max_age, nothing, ReentrantLock())
end

function get_cache_path(cache::AbstractCacheLayer)
    adapter_type = string(typeof(cache.adapter).name.name)
    adapter_hash = bytes2hex(sha256(get_adapter_hash(cache.adapter)))
    cache_id = isempty(adapter_hash) ? adapter_type : "$(adapter_type)_$(adapter_hash)_v2"
    joinpath(cache.cache_dir, "$(cache_id).jld2")
end

function ensure_cache_loaded!(cache::VectorCacheLayer)
    isnothing(cache.cache) || return
    
    cache_path = get_cache_path(cache)
    cache.cache = Dict{String,Vector{AbstractMessage}}()
    
    isfile(cache_path) || return
    
    lock(cache.file_lock) do
        jldopen(cache_path, "r") do f
            haskey(f, "items") || return
            item_keys = keys(f["items"])
            items = Vector{AbstractMessage}(undef, length(item_keys))
            for (i, id) in enumerate(item_keys)
                items[i] = f["items/$id"]
            end
            cache.cache[cache_path] = items
        end
    end
end

function append_to_store!(cache::VectorCacheLayer, items::Vector{<:AbstractMessage})
    isempty(items) && return Vector{AbstractMessage}()
    
    ensure_cache_loaded!(cache)
    cache_path = get_cache_path(cache)
    
    # Filter new items based on existing ones
    existing_items = get!(Vector{AbstractMessage}, cache.cache, cache_path)
    existing_ids = Set(string(something(get_unique_id(item), hash(item))) for item in existing_items)
    new_items = filter(items) do item
        id = string(something(get_unique_id(item), hash(item)))
        !in(id, existing_ids)
    end
    
    isempty(new_items) && return Vector{AbstractMessage}()

    append!(existing_items, new_items)
    
    @async_showerr lock(cache.file_lock) do
        jldopen(cache_path, "a+") do f
            for item in new_items
                id = string(something(get_unique_id(item), hash(item)))
                f["items/$id"] = item
            end
        end
    end
    
    new_items
end

function get_content(cache::VectorCacheLayer; from::DateTime=now() - Day(1), to::DateTime=now(), kw...)
    ensure_cache_loaded!(cache)
    cached_items = get(cache.cache, get_cache_path(cache), nothing)
    
    if !isnothing(cached_items)
        earliest_cached = minimum(get_timestamp(item) for item in cached_items)
        latest_cached = maximum(get_timestamp(item) for item in cached_items)
        
        if from < earliest_cached && supports_time_range(cache.adapter)
            historical = get_content(cache.adapter; from=from, to=earliest_cached, kw...)
            latest = get_content(cache.adapter; from=latest_cached, to, kw...)
            new_historical = append_to_store!(cache, historical)
            new_latest = append_to_store!(cache, latest)
            items = vcat(new_historical, cached_items, new_latest)
        elseif from < earliest_cached
            new_content = get_content(cache.adapter; from, to, kw...)
            items = append_to_store!(cache, new_content)
        else
            latest = get_content(cache.adapter; from=latest_cached, to, kw...)
            new_items = append_to_store!(cache, latest)
            items = vcat(cached_items, new_items)
        end
    else
        new_content = get_content(cache.adapter; from, to, kw...)
        items = append_to_store!(cache, new_content)
    end
    
    # Filter items based on the requested time range
    filter(item -> from <= get_timestamp(item) <= to, items)
end

function Base.rm(cache::VectorCacheLayer)
    cache_path = get_cache_path(cache)
    lock(cache.file_lock) do
        cache.cache = nothing
        isfile(cache_path) && rm(cache_path, force=true)
    end
end
