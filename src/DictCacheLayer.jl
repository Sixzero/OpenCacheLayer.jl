using Dates
using JLD2
using BaseDirs
using SHA
using BoilerplateCvikli: @async_showerr, @typeof
using Base.Threads: ReentrantLock

# Add these helper functions at the top
function escape_key(key::AbstractString)
    replace(key, "/" => "_SLASH_")
end

function unescape_key(key::AbstractString)
    replace(key, "_SLASH_" => "/")
end

mutable struct DictCacheLayer{T<:ContentAdapter} <: AbstractCacheLayer
    adapter::T
    cache_dir::String
    cache::Union{Dict{String,NamedTuple},Nothing}
    file_lock::ReentrantLock
end

function DictCacheLayer(adapter::T) where T<:ContentAdapter
    project = BaseDirs.Project("OpenCacheLayer")
    cache_dir = BaseDirs.User.cache(project; create=true)
    DictCacheLayer(adapter, cache_dir, nothing, ReentrantLock())
end

function get_cache_path(cache::DictCacheLayer)
    adapter_type = string(typeof(cache.adapter).name.name)
    adapter_hash = bytes2hex(sha256(get_adapter_hash(cache.adapter)))
    cache_id = isempty(adapter_hash) ? adapter_type : "$(adapter_type)_$(adapter_hash)"
    joinpath(cache.cache_dir, "$(cache_id).jld2")
end

function ensure_cache_loaded!(cache::DictCacheLayer)
    isnothing(cache.cache) || return
    
    cache_path = get_cache_path(cache)
    
    if isfile(cache_path)
        lock(cache.file_lock) do
            jldopen(cache_path, "r") do f
                cache.cache = Dict{String,NamedTuple}()
                for escaped_key in keys(f)
                    # Convert JLD2 group to Dict
                    group = f[escaped_key]
                    entry = (
                        content = group.content,
                        created_at = group.created_at,
                        accessed_at = group.accessed_at,
                        hits = group.hits
                    )
                    key = unescape_key(escaped_key)
                    cache.cache[key] = entry
                end
            end
        end
    else
        cache.cache = Dict{String,NamedTuple}()
    end
end

function append_to_store!(cache::DictCacheLayer, new_entries::Dict{String,<:NamedTuple})
    isempty(new_entries) && return
    
    cache_path = get_cache_path(cache)
    @async_showerr lock(cache.file_lock) do
        # Use w+ if file doesn't exist, r+ if it does
        mode = isfile(cache_path) ? "r+" : "w+"
        jldopen(cache_path, mode) do f
            for (k, v) in new_entries
                escaped_key = escape_key(k)
                # Delete existing group if present
                haskey(f, escaped_key) && delete!(f, escaped_key)
                # Write new entry
                f[escaped_key] = v
            end
        end
    end
end

function get_content(cache::DictCacheLayer, key; kw...)
    ensure_cache_loaded!(cache)
    
    if haskey(cache.cache, key)
        entry = cache.cache[key]
        updated_entry = merge(entry, (accessed_at=now(), hits=entry.hits + 1))
        cache.cache[key] = updated_entry
        append_to_store!(cache, Dict(key => updated_entry))
        
        status = is_cache_valid(entry.content, cache.adapter)
        
        if status === VALID || status === ASYNC
            status === ASYNC && @async_showerr begin
                try
                    new_content = get_content(cache.adapter, key; kw...)
                    refresh_entry = merge(updated_entry, (content=new_content, refreshed_at=now()))
                    cache.cache[key] = refresh_entry
                    append_to_store!(cache, Dict(key => refresh_entry))
                catch e
                    @warn "Background refresh failed" key exception=e
                end
            end
            return entry.content
        end
        
        # STALE - refresh but keep metadata
        new_content = get_content(cache.adapter, key; kw...)
        refresh_entry = merge(updated_entry, (content=new_content, refreshed_at=now()))
        cache.cache[key] = refresh_entry
        append_to_store!(cache, Dict(key => refresh_entry))
        return new_content
    end
    
    # Not in cache - create new entry
    content = get_content(cache.adapter, key; kw...)
    new_entry = (content=content, created_at=now(), accessed_at=now(), refreshed_at=now(), hits=1)
    cache.cache[key] = new_entry
    append_to_store!(cache, Dict(key => new_entry))
    return content
end

function Base.rm(cache::DictCacheLayer)
    cache_path = get_cache_path(cache)
    lock(cache.file_lock) do
        cache.cache = nothing
        isfile(cache_path) && rm(cache_path, force=true)
    end
end