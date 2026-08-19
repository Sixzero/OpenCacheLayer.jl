using Dates
using JLD2
using BaseDirs
using SHA

# One file per entry, written to a temp name and renamed into place. rename(2) is atomic,
# so a reader sees either the whole old entry or the whole new one: no torn files, and
# concurrent writers of the same key just race to be last. A damaged entry costs one
# refetch, not the cache.

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
# The file is left alone — "unreadable" also covers a content type whose module is not
# loaded in this process; a refetch overwrites it atomically anyway.
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
    isdir(cache_dir) || return Any[]
    paths = filter(endswith(".jld2"), readdir(cache_dir; join=true))  # skips leftover temp files
    filter(!isnothing, map(read_entry, paths))
end
