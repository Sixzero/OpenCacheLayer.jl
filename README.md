# OpenCacheLayer [![Stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://sixzero.github.io/OpenCacheLayer.jl/stable/) [![Dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://sixzero.github.io/OpenCacheLayer.jl/dev/) [![Build Status](https://github.com/sixzero/OpenCacheLayer.jl/actions/workflows/CI.yml/badge.svg?branch=master)](https://github.com/sixzero/OpenCacheLayer.jl/actions/workflows/CI.yml?query=branch%3Amaster) [![Coverage](https://codecov.io/gh/sixzero/OpenCacheLayer.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/sixzero/OpenCacheLayer.jl) [![Aqua](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

A minimalistic yet general-purpose caching layer implementation, designed with practicality in mind. The project aims to maintain simplicity while providing essential caching functionality. Initially developed for [OpenContentBroker.jl](https://github.com/sixzero/OpenContentBroker.jl) as its primary use case.

## Use Cases

### Message-Based Content Caching
- Cache email messages from various providers (Gmail, IMAP)
- Store chat messages from messaging platforms
- Cache social media feeds and posts

### Status-Based Content Caching
- Cache API responses with ETag support
- Monitor and cache RSS/Atom feeds
- Track changes in web content

### Chat-Based Content Organization
- Group and cache chat messages by conversation
- Maintain chat history with automatic cleanup
- Handle multi-participant conversations

Each use case leverages the library's simple adapter system - implement the required interface methods for your content type, and the caching layer handles the rest.
