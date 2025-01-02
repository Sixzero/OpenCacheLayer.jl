using BaseDirs

abstract type TokenStorage end

"""
FileStorage that uses BaseDirs to store tokens in the appropriate config directory
"""
struct FileStorage <: TokenStorage
    project::BaseDirs.Project
end

FileStorage(name::AbstractString) = FileStorage(BaseDirs.Project(name))

function get_token_path(storage::FileStorage)
    BaseDirs.User.config(storage.project, "tokens.env"; create=true)
end

function get_token(storage::FileStorage, key::String)
    token_path = get_token_path(storage)
    !isfile(token_path) && return nothing
    
    for line in eachline(token_path)
        k, v = split(line, "=", limit=2)
        k == key && return v
    end
    nothing
end

function store_token!(storage::FileStorage, key::String, value::String)
    token_path = get_token_path(storage)
    
    # Read existing tokens
    tokens = Dict{String,String}()
    isfile(token_path) && for line in eachline(token_path)
        k, v = split(line, "=", limit=2)
        tokens[k] = v
    end
    
    # Update token
    tokens[key] = value
    
    # Write back all tokens
    open(token_path, "w") do io
        for (k, v) in sort(collect(tokens))
            println(io, "$k=$v")
        end
    end
end
