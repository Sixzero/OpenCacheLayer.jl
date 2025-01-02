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

# Methods for message-based adapters
"""
    get_new_content(adapter::MessageBasedAdapter) -> Vector{ContentItem}

Fetch new content since the last check.
"""
function get_new_content end

# Methods for status-based adapters
"""
    refresh_content(adapter::StatusBasedAdapter) -> ContentItem

Refresh the content to get the latest state.
"""
function refresh_content end
