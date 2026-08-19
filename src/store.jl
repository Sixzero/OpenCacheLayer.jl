using Dates
using JLD2
using BaseDirs
using SHA

# One file per entry, written to a temp name and renamed into place. rename(2) is atomic,
# so a reader sees either the whole old entry or the whole new one: a process killed
# mid-write can no longer leave a torn file, and two processes writing the same key just
# race to be last. That is what makes the cross-process flock and the whole-file
# corruption recovery unnecessary — a damaged entry costs one refetch, not the cache.

# The adapter hash identifies the configuration (credentials, engine, options), so two
# differently-configured adapters of the same type never share a directory.
function default_cache_dir(adapter::ContentAdapter, suffix::String="")
    project = BaseDirs.Project("OpenCacheLayer")
    cache_dir = BaseDirs.User.cache(project; create=true)
    adapter_type = string(typeof(adapter).name.name)
    adapter_hash = bytes2hex(sha256(get_adapter_hash(adapter)))
    joinpath(cache_dir, "$(adapter_type)_$(adapter_hash)$(suffix)")
end

# Keys are URLs and message ids: hashing them sidesteps path separators, length limits
# and case-insensitive filesystems in one step.
entry_path(cache_dir::String, key::AbstractString) =
    joinpath(cache_dir, bytes2hex(sha256(key)) * ".jld2")

function store_entry!(cache_dir::String, key::AbstractString, entry)
    mkpath(cache_dir)
    path = entry_path(cache_dir, key)
    tmp = tempname(cache_dir)  # same filesystem, so the rename cannot fall back to a copy
    try
        jldopen(tmp, "w") do f
            f["key"] = key  # the filename is a digest, so keep the key for enumeration
            f["entry"] = entry
        end
        Base.Filesystem.rename(tmp, path)
    catch
        rm(tmp; force=true)
        rethrow()
    end
    path
end

# An unreadable entry is a miss, never an error: refetching is always a correct answer.
# The file is left alone rather than deleted — "unreadable" also covers conditions that
# say nothing about the file, such as a content type whose module is not loaded in this
# process, and deleting on those would throw away a perfectly good entry that another
# caller can still read. A refetch overwrites it atomically anyway.
function read_entry(path::String)
    isfile(path) || return nothing
    try
        jldopen(path, "r") do f
            f["entry"]
        end
    catch e
        @warn "Ignoring unreadable cache entry" path exception=e
        nothing
    end
end

read_entry(cache_dir::String, key::AbstractString) = read_entry(entry_path(cache_dir, key))

function read_all_entries(cache_dir::String)
    isdir(cache_dir) || return Pair{String,Any}[]
    entries = Pair{String,Any}[]
    for name in readdir(cache_dir)
        endswith(name, ".jld2") || continue  # skip temp files a crashed writer left behind
        path = joinpath(cache_dir, name)
        try
            jldopen(path, "r") do f
                push!(entries, f["key"] => f["entry"])
            end
        catch e
            @warn "Ignoring unreadable cache entry" path exception=e
        end
    end
    entries
end
