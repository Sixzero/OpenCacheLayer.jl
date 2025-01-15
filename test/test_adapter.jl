using Dates
using OpenCacheLayer

struct DummyMessage <: AbstractMessage
    id::String
    content::String
    timestamp::DateTime
end

OpenCacheLayer.get_unique_id(msg::DummyMessage) = msg.id
OpenCacheLayer.get_timestamp(msg::DummyMessage) = msg.timestamp

struct TestAdapter <: ChatsLikeAdapter end

OpenCacheLayer.supports_time_range(::TestAdapter) = true

function OpenCacheLayer.get_content(::TestAdapter; from::DateTime=now()-Day(1), to::Union{DateTime,Nothing}=nothing, kw...)
    to = something(to, now())
    
    # Generate messages for each day in the range [from, to)
    days = Vector{DummyMessage}()
    current = Date(from)
    while current <= Date(to)
        push!(days, DummyMessage(
            "msg_$(Dates.format(current, "yyyymmdd"))",
            "Message from day $(current)",
            DateTime(current)
        ))
        current += Day(1)
    end
    days
end

OpenCacheLayer.get_adapter_hash(::TestAdapter) = "test_adapter_v1"