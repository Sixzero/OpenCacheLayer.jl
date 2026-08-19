# Converts caches written as one shared JLD2 file into the one-file-per-entry layout.
# Non-destructive: the old `<name>.jld2` is left in place, so a rollback just means
# running the previous version again. Re-running is safe — entries are overwritten.
#
# Run it from the environment that DEFINES the cached content types, so that they are
# loaded here:
#
#   julia --project=path/to/agent -e 'using OpenContentBroker
#         include("path/to/scripts/migrate_to_entry_files.jl")' [cache_dir]
#
# Without those modules JLD2 hands back placeholder `Reconstructed*` values, and writing
# those back out produces entries nothing can read. The script refuses to do that.

# Reached through OpenCacheLayer, so the environment running this only has to depend on
# it — not on JLD2 and BaseDirs directly.
using OpenCacheLayer: store_entry!, default_cache_dir, JLD2, BaseDirs

is_reconstructed(x) = occursin("JLD2.Reconstructed", string(typeof(x)))

unescape_key(key::AbstractString) = replace(key, "_SLASH_" => "/")

function migrate_file(path::String)
    dir = first(splitext(path))  # `<name>.jld2` becomes the `<name>/` directory
    moved = skipped = 0
    JLD2.jldopen(path, "r") do f
        # The Vector layout nested everything under `items/`, the Dict layout is flat
        keyed = haskey(f, "items") ? ["items/$id" => id for id in keys(f["items"])] :
                                     [k => unescape_key(k) for k in keys(f)]
        for (group, key) in keyed
            entry = try
                f[group]
            catch e
                @warn "Skipping unreadable entry" path key exception=e
                skipped += 1
                continue
            end
            entry isa JLD2.Group && continue  # a nested group is not an entry
            is_reconstructed(entry) && error("""
                $(basename(path)) holds types this process cannot load, so every entry \
                would be migrated as an unreadable placeholder. Re-run with the package \
                that defines them loaded (e.g. `using OpenContentBroker`).""")
            store_entry!(dir, key, entry)
            moved += 1
        end
    end
    println("  $(basename(path)): $moved migrated, $skipped skipped -> $(basename(dir))/")
    moved
end

function main(cache_dir::String)
    files = filter(p -> endswith(p, ".jld2"), readdir(cache_dir; join=true))
    isempty(files) && return println("Nothing to migrate in $cache_dir")
    println("Migrating $(length(files)) cache file(s) in $cache_dir")
    for path in files
        try
            migrate_file(path)
        catch e
            @error "Could not migrate, leaving it alone" path exception=e
        end
    end
    println("Done. The original .jld2 files were kept — delete them once this looks right.")
end

main(isempty(ARGS) ? BaseDirs.User.cache(BaseDirs.Project("OpenCacheLayer")) : ARGS[1])
