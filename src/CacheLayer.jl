using Dates
using JLD2
using BaseDirs
using SHA

abstract type AbstractCacheLayer{T<:ContentAdapter} end

struct CacheLayer{T<:ContentAdapter} <: AbstractCacheLayer{T}
    adapter::T
    cache_dir::String
    max_age::Period
end

function CacheLayer(adapter::T; max_age::Period=Day(30)) where T<:ContentAdapter
    project = BaseDirs.Project("OpenCacheLayer")
    cache_dir = BaseDirs.User.cache(project; create=true)
    CacheLayer(adapter, cache_dir, max_age)
end

function get_cache_path(cache::AbstractCacheLayer, from::DateTime)
    adapter_type = string(typeof(cache.adapter).name.name)
    adapter_hash = bytes2hex(sha256(get_adapter_hash(cache.adapter)))
    cache_id = isempty(adapter_hash) ? adapter_type : "$(adapter_type)_$(adapter_hash)"
    joinpath(cache.cache_dir, "$(cache_id).jld2")
end

function load_cache(cache::CacheLayer, from::DateTime)
    cache_path = get_cache_path(cache, from)
    !isfile(cache_path) && return nothing, nothing
    
    data = load(cache_path)
    data["items"], DateTime(data["last_timestamp"])
end

function save_cache(cache::CacheLayer, from::DateTime, items::Vector{ContentItem})
    isempty(items) && return
    
    cache_path = get_cache_path(cache, from)
    
    last_timestamp = maximum(item.timestamp for item in items)
    
    save(cache_path, Dict(
        "items" => items,
        "last_timestamp" => string(last_timestamp)
    ))
end

function get_new_content(cache::CacheLayer; from::DateTime=now() - Day(1), to::Union{DateTime,Nothing}=nothing)
    cached_items, last_timestamp = load_cache(cache, from)
    
    if !isnothing(cached_items)
        earliest_cached = minimum(item.timestamp for item in cached_items)
        
        if from < earliest_cached && supports_time_range(cache.adapter)
            historical_items = get_new_content(cache.adapter; from=from, to=earliest_cached)
            new_items = get_new_content(cache.adapter; from=last_timestamp, to)
            items = vcat(historical_items, cached_items, new_items)
        elseif from < earliest_cached
            items = get_new_content(cache.adapter; from, to)
        else
            new_items = get_new_content(cache.adapter; from=last_timestamp, to)
            items = vcat(cached_items, new_items)
        end
    else
        items = get_new_content(cache.adapter; from, to)
    end
    
    save_cache(cache, from, items)
    items
end
