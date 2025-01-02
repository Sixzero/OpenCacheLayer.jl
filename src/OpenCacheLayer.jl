module OpenCacheLayer

using Dates
using Base64
using HTTP
using JSON3

include("types.jl")
include("interface.jl")
include("CacheLayer.jl")
include("ChatCacheLayer.jl")

# Export core types
export ContentAdapter, StatusBasedAdapter, ChatsLikeAdapter
export ContentItem, MessageMetadata, StatusMetadata, AdapterConfig

# Export interface functions
export get_content, process_raw, validate_content
export get_new_content, refresh_content

# Export cache layers
export CacheLayer, ChatsCacheLayer
export get_chat  # Helper for chat operations

end
