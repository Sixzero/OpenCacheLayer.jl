module OpenCacheLayer

using Dates
using Base64
using HTTP
using JSON3

include("types.jl")
include("interface.jl")
include("token_storage.jl")
include("oauth2.jl")  
include("cache.jl")
include("adapters/gmail.jl")
include("cache/CacheLayer.jl")
include("cache/ChatCacheLayer.jl")

# Export core types
export ContentAdapter, MessageBasedAdapter, StatusBasedAdapter
export ContentItem, MessageMetadata, StatusMetadata, AdapterConfig
export OAuth2Config, OAuth2Token, TokenStorage, FileStorage

# Export interface functions
export get_content, process_raw, validate_content
export get_new_content, refresh_content

# Export adapters
export GmailAdapter, GmailMessage

# Add to exports
export authorize!
export OAuth2Token
export CacheLayer, ChatCacheLayer
export get_thread  # Helper for chat operations

end
