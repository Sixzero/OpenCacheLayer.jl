# Required methods for all adapters
"""
    get_content(adapter::ContentAdapter, query::Dict) -> Vector{ContentItem}

Retrieve content based on query parameters.
"""
function get_content end

"""
    process_raw(adapter::ContentAdapter, raw::Vector{UInt8}) -> ContentType

Process raw content into structured format.
"""
function process_raw end

"""
    validate_content(adapter::ContentAdapter, content::ContentItem) -> Bool

Verify if stored content is still valid.
"""
function validate_content end

"""
    supports_time_range(adapter::ContentAdapter) -> Bool

Check if adapter supports both 'from' and 'to' parameters for time range queries.
Default implementation returns false for backward compatibility.
"""
supports_time_range(::ContentAdapter) = false

# Methods for message-based adapters
"""
    get_new_content(adapter::MessageBasedAdapter; from::DateTime, to::Union{DateTime,Nothing}=nothing) -> Vector{ContentItem}

Fetch new content within the specified time range. The 'to' parameter is optional.
"""
function get_new_content end

# Methods for status-based adapters
"""
    refresh_content(adapter::StatusBasedAdapter) -> ContentItem

Refresh the content to get the latest state.
"""
function refresh_content end

function get_adapter_hash end