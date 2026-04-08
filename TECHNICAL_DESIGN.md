# Kong Authentication Plugin - Technical Design

## Design Philosophy

This plugin follows Kong's best practices and OpenResty patterns:
1. **Single Responsibility**: Focus purely on authentication validation
2. **Configurability**: All behaviors configurable via schema
3. **Performance**: Caching to reduce external calls
4. **Robustness**: Timeouts, error handling, graceful degradation
5. **Observability**: Comprehensive logging at multiple levels

## Architecture Decisions

### 1. Handler Phase Selection
**Choice**: `access` phase  
**Rationale**:
- Executes after routing but before upstream forwarding
- Has access to route context
- Early enough to prevent unnecessary processing
- Perfect for request filtering

Alternatives considered:
- `rewrite` phase: Too early, routing not complete
- `header_filter` phase: Too late, request already sent
- `log` phase: Too late, cannot block request

### 2. HTTP Method for Auth Check
**Choice**: GET request  
**Rationale**:
- Simple, idempotent operation
- No request body needed
- Safe to retry on timeout
- Standard for validation endpoints
- Reduces latency vs POST

Alternative: POST with body data
- More complex for this use case
- No additional data to send

### 3. Caching Strategy
**Choice**: ngx.shared.kong dictionary  
**Rationale**:
- Shared across all Kong workers
- No external dependency
- Built-in to Kong
- Efficient for auth results
- Automatic cleanup on TTL

Alternative: Redis
- Unnecessary complexity for this use case
- External dependency
- Higher latency
- More resource overhead

### 4. Cache Key Design
**Format**: `auth_result:` + base64-encoded(auth_header_value)  
**Rationale**:
- Base64 encoding: Ensures binary-safe keys (though usually strings)
- URL-safe: Can safely use in any context
- Prefix: Avoids collisions with other cache keys
- Deterministic: Same header value always produces same key
- Privacy: Obfuscates credential in logs (not hashed, as we need to hash varied secrets)

Alternative: Hash functions
- Would lose ability to validate same credential appears multiple times
- More complex implementation
- Better privacy but less useful for our needs

### 5. JWT Extraction
**Choice**: JSON parsing with error handling  
**Rationale**:
- Flexible: Allows any JSON structure
- Error-safe: pcall prevents crashes on malformed JSON
- Simple: Direct key lookup
- Extensible: Easy to add nested path support later

Alternative: Assume JWT in specific field
- Less flexible
- Harder to adapt to different auth servers

### 6. Configuration Validation
**Choice**: Conditional validation with entity_checks  
**Rationale**:
- JWT fields both required together (interdependent)
- Validates at config time, not runtime
- Clear error messages to operators
- Prevents invalid configurations

Schema pattern:
```lua
entity_checks = {
  { conditional = {
      if_field = "jwt_response_key",
      if_match = { exists = true },
      then_field = "jwt_header_name",
      then_match = { exists = true },
  } },
}
```

### 7. Error Response Format
**Choice**: JSON with `message` field  
**Rationale**:
- Consistent with Kong conventions
- Human and machine readable
- Structured for API error handling
- Extensible for additional fields

Format:
```json
{
  "message": "Missing authentication header"
}
```

### 8. Timeout Strategy
**Choice**: 5-second timeout on all HTTP calls  
**Rationale**:
- Prevents hanging requests
- Balances availability vs auth latency
- Reasonable for most auth servers
- Prevents resource exhaustion
- Configurable in future versions if needed

Calculation: 5000 milliseconds = 5 seconds
- Acceptable latency for authentication gate
- Prevents slowdown of platform
- Auth server should respond much faster

## Code Organization

### Function Breakdown
```
handler.lua
├── get_cache_key()
│   └── Generate cache key from auth value
├── get_cached_result()
│   └── Retrieve cached auth result
├── cache_result()
│   └── Store auth result in cache
├── authenticate()
│   └── Make HTTP request to auth server
├── extract_jwt()
│   └── Parse JWT from auth response
└── plugin:access()
    └── Main handler orchestrating flow
```

### Separation of Concerns
1. **Caching logic**: Isolated in three functions
2. **HTTP logic**: Isolated in authenticate()
3. **Parsing logic**: Isolated in extract_jwt()
4. **Orchestration**: Main access() handler

Benefits:
- Easy to test each function
- Easy to modify caching strategy
- Easy to change HTTP method
- Clear flow in main handler

## Flow Diagrams

### Request Processing Flow
```
Client Request arrives
         ↓
   [plugin:access]
         ↓
   Has auth header?
   ├─ No → Return 401 ❌
   └─ Yes ↓
         ↓
   Check cache?
   ├─ Hit → Use cached result
   └─ Miss ↓
         ↓
   Call auth server with header
         ↓
   Auth server responds
         ↓
   Cache the result
         ↓
   Result successful?
   ├─ No → Return 401 ❌
   └─ Yes ↓
         ↓
   Extract JWT if configured?
   ├─ Yes → Add to request headers
   └─ No ↓
         ↓
   Allow request to proceed ✅
```

### Cache Lifecycle
```
Time 0: First request with "token123"
  → Cache miss
  → Auth check: Success
  → Cache[key]="success" (TTL=300)
  → Request proceeds

Time 30s: Another request with "token123"
  → Cache hit (TTL=270 remaining)
  → Use cached result
  → Request proceeds (no auth server call)

Time 300s+: Third request with "token123"
  → Cache expired
  → Cache miss
  → Auth check again
  → Cache[key]="success" (TTL=300)
```

### JWT Extraction Flow
```
Auth server response:
{
  "user_id": "123",
  "access_token": "eyJhbGc...",
  "scope": "read write"
}

Config: jwt_response_key = "access_token"

Process:
1. Parse JSON from response
2. Lookup data["access_token"]
3. Found: "eyJhbGc..."
4. Add header: X-Token = "eyJhbGc..."
5. Forward to backend
```

## Testing Strategy

### Test Pyramid
```
                /\
               /  \
              /    \  Integration Tests (3)
             /      \
            /________\
           /          \
          /            \ Unit Tests (4)
         /              \
        /________________\
       /                  \
      /                    \ Schema Tests (11)
     /                      \
    /________________________\
```

### Schema Tests
- Validation of all fields
- Default values
- Constraints (required, bounds)
- Conditional rules

### Unit Tests
- Missing headers
- Configuration options
- Error status codes
- Mock Kong functions

### Integration Tests
- Full plugin loading
- Auth flow with Kong
- Route configuration
- End-to-end authentication

## Performance Characteristics

### Time Complexity
- Cache hit: O(1) - direct lookup
- Cache miss: O(1) + network latency
- JWT extraction: O(n) - JSON parsing

### Space Complexity
- Cache: O(m*a) where m=number of credentials, a=result size
- Auth header value: Typically <1KB
- Cache result: ~100-200 bytes

### Network Calls
- Without cache: 1 call per request
- With cache: ~0 calls (depends on hit rate)
- JWT extraction: Included in auth call

## Security Considerations

### Data Protection
1. **Cache keys**: Base64-encoded (not hashed)
   - Rationale: Need deterministic keys for same credentials
   - Privacy: Logs show obfuscated keys
   
2. **Credentials**: Never logged directly
   - Only cache keys logged
   - Auth headers passed as-is to auth server
   
3. **JWT**: Stored in cache like any auth result
   - TTL ensures eventual expiration
   - Kong's security model protects cache

### Attack Prevention
1. **Timeout**: 5 seconds prevents slowloris
2. **Cache**: Prevents brute force on auth server
3. **HTTP only**: No sensitive data in responses
4. **Error messages**: Generic to prevent info leakage

### TLS/HTTPS
- Not enforced by plugin (operator responsibility)
- Should be enforced in production Kong config
- Auth server URL should use HTTPS

## Extensibility Points

### Future Enhancements

1. **Support different HTTP methods**
   ```lua
   config.auth_method = {
     type = "string",
     enum = { "GET", "POST", "HEAD" },
     default = "GET"
   }
   ```

2. **Custom request bodies**
   ```lua
   config.auth_request_body = {
     type = "string", -- JSON template
   }
   ```

3. **Path-based configuration**
   ```lua
   config.paths = {
     type = "array",
     elements = { type = "string" },
   }
   ```

4. **Multiple auth backends**
   ```lua
   config.auth_servers = {
     type = "array",
     elements = { type = "record", ... },
   }
   ```

5. **Custom cache implementations**
   ```lua
   local cache = cache_backend:new(plugin_conf.cache_type)
   ```

## Code Quality Metrics

### Complexity
- Cyclomatic complexity: ~8 (low)
- Main handler: ~15 lines of logic
- Individual functions: Single purpose

### Maintainability
- No external dependencies (except resty.http)
- Clear variable names
- Functions decomposed logically
- Comments for non-obvious logic

### Robustness
- All network calls have timeouts
- All JSON parsing wrapped in pcall
- Null checks before operations
- Graceful degradation on errors

### Performance
- Minimal memory footprint
- Single HTTP call per request (or cache hit)
- No string concatenation loops
- Efficient cache lookups

## References

### Kong Documentation
- Plugin Development: https://docs.konghq.com/latest/plugin-development
- Plugin Development Kit: https://docs.konghq.com/gateway/latest/pdk/
- Schema Reference: https://docs.konghq.com/gateway/latest/plugin-development/

### OpenResty/Lua
- ngx.shared: https://github.com/openresty/lua-nginx-module
- http.request_uri: http://github.com/ledgetech/lua-resty-http

### Patterns Used
- Access phase handler pattern
- Shared memory caching pattern
- JSON parsing with error handling pattern
- Conditional schema validation pattern
