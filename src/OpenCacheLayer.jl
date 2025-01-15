module OpenCacheLayer

using Dates
using Base64
using HTTP
using JSON3

include("interface.jl")
include("DictCacheLayer.jl")
include("VectorCacheLayer.jl")

# Export core types
export ContentAdapter, StatusBasedAdapter, ChatsLikeAdapter
export AbstractContent, AbstractMessage, AbstractWebContent

# Export interface functions
export get_content
export is_cache_valid, supports_time_range
export get_adapter_hash

# Export cache layers
export DictCacheLayer, ChatsCacheLayer, VectorCacheLayer
export get_chat  # Helper for chat operations

end
