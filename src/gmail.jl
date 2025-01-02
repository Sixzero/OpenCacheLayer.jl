using HTTP
using JSON3
using Dates
using Base64
using URIs

# OAuth2 configuration for Gmail
const GMAIL_OAUTH_CONFIG = Dict(
    "auth_uri" => "https://accounts.google.com/o/oauth2/v2/auth",
    "token_uri" => "https://oauth2.googleapis.com/token",
    "scope" => "https://www.googleapis.com/auth/gmail.readonly",
    "redirect_uri" => "http://localhost:8080"
)

# Gmail specific message type
struct GmailMessage
    subject::String
    body::String
    from::String
    to::Vector{String}
    message_id::String
    thread_id::String
    labels::Vector{String}
end

struct GmailAdapter <: ChatsLikeAdapter
    config::AdapterConfig
    token_manager::OAuth2TokenManager
end

# Updated constructor without last_history_id
function GmailAdapter(credentials::Dict{String, String}, token_storage::TokenStorage=FileStorage("OpenContentBroker"))
    config = AdapterConfig(
        Minute(1),
        Dict("max_retries" => 3, "retry_delay" => 1),
        Dict("labels" => ["INBOX"], "max_results" => 100)
    )
    
    oauth = OAuth2Config(
        GMAIL_OAUTH_CONFIG["auth_uri"],
        GMAIL_OAUTH_CONFIG["token_uri"],
        GMAIL_OAUTH_CONFIG["scope"],
        GMAIL_OAUTH_CONFIG["redirect_uri"],
        credentials["client_id"],
        credentials["client_secret"]
    )
    
    token_manager = OAuth2TokenManager(oauth, token_storage)
    GmailAdapter(config, token_manager)
end

# Remove token-related methods from GmailAdapter
function ensure_token!(adapter::GmailAdapter)
    ensure_access_token!(adapter.token_manager)
end

# Add this new method
function authorize!(adapter::GmailAdapter)
    authorize!(adapter.token_manager)
end

# Modify the authorize! method for the token manager
function authorize!(manager::OAuth2TokenManager)
    start_oauth_flow!(manager.config; service_name="Gmail") do token
        store_token!(manager.storage, "REFRESH_TOKEN", token.refresh_token)
        manager.token[] = token
    end
end

# Process raw Gmail message data
function process_raw(adapter::GmailAdapter, raw::Vector{UInt8})
    msg_data = JSON3.read(raw)
    
    # Extract headers
    headers = Dict(h.name => h.value for h in msg_data.payload.headers)
    
    # Process body (assuming text/plain for simplicity)
    body = ""
    if haskey(msg_data.payload, :body) && haskey(msg_data.payload.body, :data)
        body = String(base64decode(replace(msg_data.payload.body.data, '-'=>'+', '_'=>'/')))
    end
    
    GmailMessage(
        get(headers, "Subject", ""),
        body,
        get(headers, "From", ""),
        split(get(headers, "To", ""), ","),
        msg_data.id,
        msg_data.threadId,
        msg_data.labelIds
    )
end

# Validate content
function validate_content(adapter::GmailAdapter, content::ContentItem)
    # Check if message still exists and labels haven't changed
    # For mock, always return true
    true
end

const GMAIL_API_BASE = "https://www.googleapis.com/gmail/v1"

# Get new messages since last check
function get_new_content(adapter::GmailAdapter, from::DateTime=now() - Day(1))
    access_token = ensure_token!(adapter)
    
    headers = [
        "Authorization" => "Bearer $access_token",
        "Accept" => "application/json"
    ]
    
    # Convert DateTime to Gmail's query format (YYYY/MM/DD)
    after = Dates.format(from, "yyyy/mm/dd")
    
    query = Dict(
        "maxResults" => get(adapter.config.filters, "max_results", 100),
        "labelIds" => join(get(adapter.config.filters, "labels", ["INBOX"]), ","),
        "q" => "after:$after"
    )
    
    response = HTTP.get(
        "$GMAIL_API_BASE/users/me/messages?$(URIs.escapeuri(query))",
        headers
    )
    
    messages_data = JSON3.read(response.body)
    isnothing(messages_data.messages) && return ContentItem[]
    
    items = ContentItem[]
    for msg in messages_data.messages
        msg_response = HTTP.get(
            "$GMAIL_API_BASE/users/me/messages/$(msg.id)?format=full",
            headers
        )
        
        raw_content = msg_response.body
        processed = process_raw(adapter, raw_content)
        
        push!(items, ContentItem(
            processed.message_id,
            raw_content,
            processed,
            MessageMetadata(
                "gmail",
                processed.from,
                processed.to,
                processed.thread_id,  # Gmail uses thread_id as chat_id
                now()
            ),
            now()
        ))
    end
    
    items
end

# Implement base get_content for specific queries
function get_content(adapter::GmailAdapter, query::Dict)
    from = get(query, "from", now() - Day(1))
    get_new_content(adapter, from)
end
