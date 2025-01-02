using HTTP
using URIs
using JSON3

"""
OAuth2 configuration and helper functions for authentication flows.
"""
struct OAuth2Config
    auth_uri::String
    token_uri::String
    scope::String
    redirect_uri::String
    client_id::String
    client_secret::String
end

"""
Represents OAuth2 tokens returned from authorization
"""
struct OAuth2Token
    access_token::String
    refresh_token::String
    token_type::String
    expires_in::Int
end

# Convert JSON response to OAuth2Token
function OAuth2Token(data::Dict)
    OAuth2Token(
        data["access_token"],
        get(data, "refresh_token", ""),  # Optional in refresh flow
        data["token_type"],
        data["expires_in"]
    )
end

"""
    get_auth_url(config::OAuth2Config) -> String

Generate the OAuth2 authorization URL.
"""
function get_auth_url(config::OAuth2Config)
    auth_params = Dict(
        "client_id" => config.client_id,
        "redirect_uri" => config.redirect_uri,
        "scope" => config.scope,
        "response_type" => "code",
        "access_type" => "offline",
        "prompt" => "consent"
    )
    string(config.auth_uri, "?", URIs.escapeuri(auth_params))
end

"""
    exchange_code_for_tokens(config::OAuth2Config, code::String) -> OAuth2Token

Exchange authorization code for access and refresh tokens.
"""
function exchange_code_for_tokens(config::OAuth2Config, code::String)::OAuth2Token
    response = HTTP.post(
        config.token_uri,
        ["Content-Type" => "application/x-www-form-urlencoded"],
        URIs.escapeuri(Dict(
            "client_id" => config.client_id,
            "client_secret" => config.client_secret,
            "code" => code,
            "redirect_uri" => config.redirect_uri,
            "grant_type" => "authorization_code"
        ))
    )
    data = JSON3.read(response.body, Dict)
    OAuth2Token(data)
end

"""
    refresh_access_token(config::OAuth2Config, refresh_token::String) -> OAuth2Token

Get a new access token using a refresh token.
"""
function refresh_access_token(config::OAuth2Config, refresh_token::AbstractString)::OAuth2Token
    response = HTTP.post(
        config.token_uri,
        ["Content-Type" => "application/x-www-form-urlencoded"],
        URIs.escapeuri(Dict(
            "client_id" => config.client_id,
            "client_secret" => config.client_secret,
            "refresh_token" => refresh_token,
            "grant_type" => "refresh_token"
        ))
    )
    data = JSON3.read(response.body, Dict)
    OAuth2Token(
        data["access_token"],
        get(data, "refresh_token", refresh_token),  # Keep existing refresh token if not provided
        data["token_type"],
        data["expires_in"]
    )
end

"""
Manages token refresh and authorization flow
"""
struct OAuth2TokenManager
    config::OAuth2Config
    token::Ref{Union{OAuth2Token, Nothing}}
    storage::TokenStorage
end

OAuth2TokenManager(config::OAuth2Config, storage::TokenStorage=FileStorage("OpenContentBroker")) = 
    OAuth2TokenManager(config, Ref{Union{OAuth2Token, Nothing}}(nothing), storage)

"""
Get a valid refresh token, handling authorization if needed
"""
function ensure_refresh_token!(manager::OAuth2TokenManager)
    refresh_token = get_token(manager.storage, "REFRESH_TOKEN")
    if isnothing(refresh_token)
        @info "No refresh token found. Starting authorization flow..."
        authorize!(manager)
        refresh_token = get_token(manager.storage, "REFRESH_TOKEN")
    else
        # Test if token is valid
        try
            # Pass both config and refresh_token
            manager.token[] = refresh_access_token(manager.config, refresh_token)
        catch e
            if e isa HTTP.ExceptionRequest.StatusError && e.status in [400, 401]
                @info "Refresh token expired. Starting authorization flow..."
                authorize!(manager)
                refresh_token = get_token(manager.storage, "REFRESH_TOKEN")
            else
                rethrow(e)
            end
        end
    end
    refresh_token
end

"""
Get a valid access token, handling refresh if needed
"""
function ensure_access_token!(manager::OAuth2TokenManager)
    if isnothing(manager.token[])
        refresh_token = ensure_refresh_token!(manager)
        manager.token[] = refresh_access_token(manager.config, refresh_token)
    end
    manager.token[].access_token
end

"""
Start OAuth2 authorization flow
"""
function authorize!(manager::OAuth2TokenManager)
    start_oauth_flow!(manager.config) do token
        store_token!(manager.storage, "REFRESH_TOKEN", token.refresh_token)
        manager.token[] = token
    end
end

const OAUTH_SUCCESS_TEMPLATE = """
<html>
    <head>
        <style>
            body { 
                font-family: Arial, sans-serif;
                max-width: 600px;
                margin: 40px auto;
                text-align: center;
                line-height: 1.6;
            }
            .success { color: #28a745; }
            .note { color: #666; font-size: 0.9em; }
        </style>
    </head>
    <body>
        <h1 class="success">Authorization Successful!</h1>
        <p>Your {service} account has been successfully connected.</p>
        <p class="note">You can close this window and return to Julia.</p>
    </body>
</html>
"""

"""
    start_oauth_flow!(token_handler::Function, config::OAuth2Config; service_name::String="Service") -> Nothing

Start OAuth2 authorization flow and handle the received tokens with the provided handler function.
The service_name parameter is used in the success message shown to the user.
"""
function start_oauth_flow!(token_handler::Function, config::OAuth2Config; service_name::String="Service")
    auth_url = get_auth_url(config)
    println("\nOpen this URL in your browser:\n", auth_url)
    println("\nWaiting for authorization...")
    
    server = HTTP.serve!("127.0.0.1", 8080) do request
        try
            request.target == "/favicon.ico" && return HTTP.Response(404)
            params = HTTP.queryparams(HTTP.URI(request.target))
            
            !haskey(params, "code") && return HTTP.Response(400, "Missing authorization code")
            
            tokens = exchange_code_for_tokens(config, params["code"])
            token_handler(tokens)
            
            return HTTP.Response(200, replace(OAUTH_SUCCESS_TEMPLATE, "{service}" => service_name))
        catch e
            @error "Error handling OAuth callback" exception=e
            return HTTP.Response(500, "Authorization failed: $(sprint(showerror, e))")
        end
    end
    
    println("\nPress Enter to exit...")
    readline()
    close(server)
    nothing
end
