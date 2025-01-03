using Dates
using JLD2

struct ChatsCacheLayer{T<:ChatsLikeAdapter} <: AbstractCacheLayer{T}
    adapter::T
    cache_dir::String
    max_age::Period
end

function ChatsCacheLayer(adapter::T; max_age::Period=Day(30)) where T<:ChatsLikeAdapter
    project = BaseDirs.Project("OpenContentBroker")
    cache_dir = BaseDirs.User.cache(project, "chats_cache"; create=true)
    ChatsCacheLayer(adapter, cache_dir, max_age)
end

function load_chat_cache(cache::ChatsCacheLayer, from::DateTime)
    cache_path = get_cache_path(cache, from)
    !isfile(cache_path) && return Dict{String,Vector{ContentItem}}(), nothing
    
    data = load(cache_path)
    data["chats"], DateTime(data["last_timestamp"])
end

function save_chat_cache(cache::ChatsCacheLayer, from::DateTime, chats::Dict{String,Vector{ContentItem}})
    isempty(chats) && return
    
    cache_path = get_cache_path(cache, from)
    last_timestamp = maximum(maximum(item.timestamp for item in msgs) for msgs in values(chats))
    
    save(cache_path, Dict(
        "chats" => chats,
        "last_timestamp" => string(last_timestamp)
    ))
end

function group_by_chat(items::Vector{ContentItem})
    chats = Dict{String,Vector{ContentItem}}()
    for item in items
        chat_id = string(item.metadata.chat_id)
        push!(get!(chats, chat_id, ContentItem[]), item)
    end
    sort!.(values(chats), by = x -> x.timestamp)
    chats
end

function get_new_content(cache::ChatsCacheLayer; from::DateTime=now() - Day(1), to::Union{DateTime,Nothing}=nothing)
    cached_chats, last_timestamp = load_chat_cache(cache, from)
    
    if !isnothing(last_timestamp)
        new_items = get_new_content(cache.adapter; from=last_timestamp, to=to)
        for (chat_id, messages) in group_by_chat(new_items)
            if haskey(cached_chats, chat_id)
                append!(cached_chats[chat_id], messages)
                sort!(cached_chats[chat_id], by = x -> x.timestamp)
            else
                cached_chats[chat_id] = messages
            end
        end
    else
        cached_chats = group_by_chat(get_new_content(cache.adapter; from=from, to=to))
    end
    
    save_chat_cache(cache, from, cached_chats)
    cached_chats
end

# Update the helper function too
get_chat(cache::ChatsCacheLayer, chat_id::String; from::DateTime=now() - Day(7), to::Union{DateTime,Nothing}=nothing) = 
    get(get_new_content(cache; from, to), chat_id, ContentItem[])
