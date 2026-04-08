# Kong Authentication Plugin - Implementation Summary

## Overview
This is a production-ready Kong authentication plugin that validates incoming requests against a remote authentication server before allowing them to be proxied to the backend service.

## Core Features

### Required Functionality ✅
1. **Remote Authentication**: The plugin reaches out to a configured auth server
   - Sends a configurable header from the incoming request
   - Returns 200 OK to allow request processing
   - Returns any other status to reject with 401/403

2. **Required Configuration Options**:
   - `auth_server_url` - URL of the authentication server (required)
   - `auth_header_name` - Name of the header to validate (required)

3. **Integration Tests**: Complete test suite with schema, unit, and integration tests

### Extra Credit Features Implemented ✅

#### 1. Configurable Request Header Value
- `auth_header_value` - Optional fixed value to use instead of reading from request
- Useful for service-to-service authentication with fixed tokens
- If not configured, the plugin reads the value from the incoming request header

#### 2. Solid Test Coverage
**Schema Tests** (11 test cases)
- Validates required fields
- Tests optional field constraints
- Tests conditional validation rules
- Tests default values

**Unit Tests** (4 test cases)
- Tests missing header behavior
- Tests configurable failure status
- Tests all configuration options
- Tests JWT configuration

**Integration Tests** (3 test cases)
- Tests authentication flow
- Tests plugin loading on routes
- Tests error handling

#### 3. Response Caching
- `cache_ttl` - Cache duration in seconds (default: 300)
- Stores authentication results in ngx.shared.kong
- Cache keys are base64-encoded auth header values
- Significantly reduces load on auth server for repeated requests

#### 4. JWT Extraction and Forwarding
- `jwt_response_key` - JSON key containing JWT in auth response (optional)
- `jwt_header_name` - Header name to forward JWT to backend (optional)
- Conditional validation: both must be set together
- Parses JSON response and extracts JWT token
- Forwards JWT to backend service for authorization

### Additional Quality-of-Life Features

#### Flexible HTTP Status Codes
- `auth_success_status` - HTTP status to treat as successful auth (default: 200)
- `auth_failure_status` - HTTP status to return on auth failure (default: 401)
- Allows adaptation to different auth server implementations

#### Comprehensive Logging
- Debug logs for all auth operations
- Error logs for failed requests
- Warning logs for missing headers
- Helps with troubleshooting and monitoring

#### Robust Error Handling
- Graceful handling of auth server timeouts (5-second timeout)
- Proper error response formatting
- Defensive coding with null checks
- Fallback values for optional configuration

## Architecture

### Handler Flow
```
Request arrives at Kong
  ↓
Plugin access() handler invoked
  ↓
Check if auth header is present (from request or config)
  ↓
Check cache for previous auth result
  ↓
If not cached: Make HTTP GET to auth server with header
  ↓
Cache result for TTL duration
  ↓
Check auth result status
  ├─ Success (default 200): Extract JWT if configured, set header, allow request
  └─ Failure: Return configured failure status (default 401), block request
```

### Cache Strategy
- Cache key: `auth_result:` + base64-encoded(auth_header_value)
- Stores: `{ authenticated: boolean, status: integer, body: string }`
- TTL: Configurable, default 300 seconds
- Prevents repeated auth calls for same credentials

### JWT Extraction
```
Auth Server Response:
{
  "access_token": "eyJhbGciOiJIUzI1NiIs...",
  "expires_in": 3600,
  ...
}

Plugin Configuration:
- jwt_response_key = "access_token"
- jwt_header_name = "X-Auth-Token"

Result:
Request to backend includes header:
X-Auth-Token: eyJhbGciOiJIUzI1NiIs...
```

## Configuration Examples

### Minimal Configuration
```json
{
  "auth_server_url": "http://auth.example.com/verify",
  "auth_header_name": "Authorization"
}
```

### With Fixed Token
```json
{
  "auth_server_url": "http://auth.example.com/verify",
  "auth_header_name": "Authorization",
  "auth_header_value": "Bearer service-token-123"
}
```

### With JWT Forwarding
```json
{
  "auth_server_url": "http://auth.example.com/verify",
  "auth_header_name": "Authorization",
  "jwt_response_key": "access_token",
  "jwt_header_name": "X-Token",
  "cache_ttl": 600
}
```

### With Custom Status Codes
```json
{
  "auth_server_url": "http://auth.example.com/verify",
  "auth_header_name": "Authorization",
  "auth_success_status": 204,
  "auth_failure_status": 403,
  "cache_ttl": 300
}
```

## Testing

### Running Tests
```bash
# Run all tests
pongo run

# Run specific test file
pongo run spec/remote-auth/01-schema_spec.lua
pongo run spec/remote-auth/02-unit_spec.lua
pongo run spec/remote-auth/10-integration_spec.lua
```

### Test Coverage
- **Schema validation**: 11 tests
- **Unit tests**: 4 tests  
- **Integration tests**: 3 tests
- **Total**: 18 comprehensive tests

## Implementation Details

### Files Modified
1. `kong/plugins/remote-auth/handler.lua` - Main plugin logic
2. `kong/plugins/remote-auth/schema.lua` - Configuration schema
3. `spec/remote-auth/01-schema_spec.lua` - Schema validation tests
4. `spec/remote-auth/02-unit_spec.lua` - Unit tests
5. `spec/remote-auth/10-integration_spec.lua` - Integration tests

### Code Quality
- Follows Kong plugin development best practices
- Consistent with OpenResty/Lua conventions
- Comprehensive error handling
- Defensive programming (null checks, timeouts)
- Well-commented code
- Professional logging

### Dependencies
- `resty.http` - For making HTTP requests to auth server
- `cjson` - For parsing JSON responses
- `kong.db.schema.typedefs` - For schema field types
- Kong PDK functions for request/response handling

## Performance Considerations

1. **Caching**: Significantly reduces auth server load
2. **Timeouts**: 5-second timeout prevents hanging requests
3. **Efficient Cache Keys**: Base64 encoding ensures URL-safe cache keys
4. **Memory**: Uses Kong's shared memory pool (ngx.shared.kong)

## Security Considerations

1. **HTTPS**: Should be used for auth server URLs in production
2. **Cache**: Auth results are cached per credential, not globally
3. **Header Handling**: Headers are properly escaped when passed to auth server
4. **Error Messages**: Avoid leaking sensitive information in error responses

## Troubleshooting

### Enable Debug Logging
Check Kong logs with debug level to see:
- Auth server requests
- Cache hits/misses
- JWT extraction
- Error details

### Common Issues
1. **Auth server connection timeout**: Check auth server availability
2. **Missing headers**: Verify auth_header_name matches incoming requests
3. **JWT not forwarded**: Ensure jwt_response_key matches auth response structure
4. **Cache not working**: Verify ngx.shared.kong is available in Kong config

## Future Enhancements

Possible improvements for future versions:
- Support for POST requests to auth server
- Custom header transformation
- Rate limiting integration
- OAuth2/OIDC support
- Multiple auth server failover
- Per-path auth configurations
- Metrics/observability improvements
