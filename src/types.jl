# Core types for content adapters
abstract type ContentAdapter end
abstract type ChatsLikeAdapter <: ContentAdapter end
abstract type StatusBasedAdapter <: ContentAdapter end

# Base content item type
struct ContentItem{ContentType, MetadataType}
    id::String
    raw_content::Vector{UInt8}
    processed_content::ContentType
    metadata::MetadataType
    timestamp::DateTime
end

# Common metadata types
struct MessageMetadata
    source_id::String
    sender::String
    recipients::Vector{String}
    chat_id::Union{String, Nothing}
    timestamp::DateTime
end

struct StatusMetadata
    source_id::String
    last_checked::DateTime
    etag::Union{String, Nothing}
end

# Configuration type
struct AdapterConfig
    refresh_interval::Period
    retry_policy::Dict{String, Any}
    filters::Dict{String, Any}
end
