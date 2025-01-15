# Core types
abstract type AbstractCacheLayer end

# Core adapter types
abstract type ContentAdapter end
abstract type ChatsLikeAdapter <: ContentAdapter end
abstract type StatusBasedAdapter <: ContentAdapter end

# Core content types
abstract type AbstractContent end
abstract type AbstractMessage <: AbstractContent end
abstract type AbstractWebContent <: AbstractContent end

# Configuration type
struct AdapterConfig
    refresh_interval::Period
    retry_policy::Dict{String, Any}
    filters::Dict{String, Any}
end

"""
    get_unique_id(content::AbstractContent) -> String

Get a unique identifier for the content item.
Default implementation returns nothing to indicate fallback to index-based storage.
"""
function get_unique_id(content::AbstractContent)
    @warn "unimplemented" content
    nothing
end

# Methods for web/status based content
@enum CacheState begin
    VALID
    ASYNC
    STALE
end

"""
    is_cache_valid(content::AbstractContent, adapter::ContentAdapter) -> CacheState

Returns cache validity status as CacheState enum:
VALID - Content is fresh and valid
ASYNC - Content usable but should be refreshed asynchronously
STALE - Content is stale and should be refreshed before use
"""
function is_cache_valid(content::AbstractContent, adapter::ContentAdapter)
    @warn "unimplemented" content adapter
    ASYNC
end

# Required methods for all adapters
"""
    get_content(adapter::ContentAdapter, query::Dict) -> Vector{AbstractContent}

Retrieve content based on query parameters.
Typical query parameters:
- from::DateTime - Start time for content retrieval
- to::Union{DateTime,Nothing} - Optional end time
"""
function get_content(adapter::ContentAdapter, query::Dict)
    @warn "unimplemented" adapter
    Vector{AbstractContent}()
end

"""
    supports_time_range(adapter::ContentAdapter) -> Bool

Check if adapter supports both 'from' and 'to' parameters for time range queries.
Default implementation returns false for backward compatibility.
"""
supports_time_range(::ContentAdapter) = false

# Optional method for adapter-specific hash generation
"""
    get_adapter_hash(adapter::ContentAdapter) -> String

Returns a unique identifier string for the adapter configuration. This is used to:
- Separate cache storage between different adapter configurations
- Enable multiple instances of the same adapter type with different settings
- Distinguish between authenticated and non-authenticated adapters

For example:
- Web adapter might use headers as part of the hash
- Gmail adapter might use client_id and email
- Simple adapters might just return their type name
"""
function get_adapter_hash(adapter::ContentAdapter)
    @warn "unimplemented" adapter
    UInt8[]
end

"""
    get_timestamp(message::AbstractMessage) -> DateTime

Get the timestamp of the message. Must be implemented for each concrete message type.
"""
function get_timestamp(message::AbstractMessage)
    error("get_timestamp not implemented for $(typeof(message))")
end