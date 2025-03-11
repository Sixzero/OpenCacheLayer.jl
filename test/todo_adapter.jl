using Dates
using OpenCacheLayer

struct TODOMessage <: AbstractMessage
    id::String
    content::String
    timestamp::DateTime
end
struct TODOPostProcessed
    id_of_todo
    post_processed_task::Task
end

OpenCacheLayer.get_unique_id(msg::TODOMessage) = msg.id
OpenCacheLayer.get_timestamp(msg::TODOMessage) = msg.timestamp

struct TestAdapter <: ChatsLikeAdapter end

OpenCacheLayer.supports_time_range(::TestAdapter) = true

function OpenCacheLayer.get_content(::TestAdapter; from::DateTime=now()-Day(1), to::Union{DateTime,Nothing}=nothing, kw...)
    to = something(to, now())
    
    # Generate messages for each day in the range [from, to)
    days = Vector{TODOMessage}()
    current = Date(from)
    while current <= Date(to)
        push!(days, TODOMessage(
            "msg_$(Dates.format(current, "yyyymmdd"))",
            "Message from day $(current)",
            DateTime(current)
        ))
        current += Day(1)
    end
    days
end

OpenCacheLayer.get_adapter_hash(::TestAdapter) = "test_adapter_v1"