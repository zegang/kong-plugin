# Kong Authentication Plugin - Usage Guide

## Installation

### Prerequisites
- Kong Gateway (3.0+)
- kong-pongo for local development and testing
- Lua 5.1+

### Setup
1. Place the plugin in your Kong plugins directory
2. Add to Kong configuration: `plugins = bundled,remote-auth`
3. Restart Kong

### Using with Kong-Pongo
```bash
# Start Kong with this plugin
pongo up

# Run full test suite
pongo run

# Run specific tests
pongo run spec/remote-auth/
```

## Configuration

### Via Kong Admin API
```bash
# Create a service
curl -X POST http://kong:8001/services \
  -d "name=my-service" \
  -d "url=http://backend.example.com"

# Create a route
curl -X POST http://kong:8001/services/my-service/routes \
  -d "name=routing-rule" \
  -d "paths[]=/api"

# Configure the plugin on the route
curl -X POST http://kong:8001/routes/routing-rule/plugins \
  -d "name=remote-auth" \
  -d "config.auth_server_url=http://auth.example.com/verify" \
  -d "config.auth_header_name=Authorization" \
  -d "config.cache_ttl=300"
```

### Via YAML/Declarative Config
```yaml
services:
  - name: my-service
    url: http://backend.example.com

routes:
  - name: api-route
    service: my-service
    paths:
      - /api

plugins:
  - name: remote-auth
    route: api-route
    config:
      auth_server_url: http://auth.example.com/verify
      auth_header_name: Authorization
      cache_ttl: 300
      jwt_response_key: access_token
      jwt_header_name: X-Token
```

## How It Works

### Basic Flow
1. Client sends request with Authorization header
2. Plugin intercepts request in access phase
3. Plugin forwards Authorization header to auth server
4. Auth server returns 200 OK or error
5. If 200: Request proceeds to backend
6. If error: Request returns 401/403 to client

### With JWT Forwarding
1. Auth server returns JSON with JWT: `{"access_token": "..."}`
2. Plugin extracts JWT from response
3. Plugin adds JWT to request header (e.g., X-Token)
4. Backend receives request with JWT for further authorization

### With Caching
1. First request: Full auth check against server
2. Result cached for configured TTL
3. Subsequent requests with same credential: Use cache
4. Cache miss: Auth server is consulted again

## Common Use Cases

### API Gateway with External Auth Service
```json
{
  "auth_server_url": "http://oauth2.example.com/introspect",
  "auth_header_name": "Authorization",
  "auth_failure_status": 401,
  "cache_ttl": 300
}
```

### Microservices with JWT Forwarding
```json
{
  "auth_server_url": "http://auth-service:3000/validate",
  "auth_header_name": "Authorization",
  "jwt_response_key": "user_token",
  "jwt_header_name": "X-User-Token",
  "cache_ttl": 600
}
```

### Service-to-Service Authentication
```json
{
  "auth_server_url": "http://internal-auth:8080/verify",
  "auth_header_name": "Service-Token",
  "auth_header_value": "secret-service-token-xyz",
  "cache_ttl": 900
}
```

### Flexible Status Codes
```json
{
  "auth_server_url": "http://auth.example.com/verify",
  "auth_header_name": "Authorization",
  "auth_success_status": 204,
  "auth_failure_status": 403,
  "cache_ttl": 300
}
```

## Testing Your Setup

### With httpbin.org (External Service)
```bash
# Test with httpbin status endpoint
curl -X POST http://kong:8001/routes/api-route/plugins \
  -d "name=remote-auth" \
  -d "config.auth_server_url=https://httpbin.org/status/200" \
  -d "config.auth_header_name=Authorization"
```

### With Local Mock Server
```bash
# Start mock auth server on port 8888
python -m http.server 8888

# Configure plugin to use local server
curl -X POST http://kong:8001/routes/api-route/plugins \
  -d "name=remote-auth" \
  -d "config.auth_server_url=http://127.0.0.1:8888/auth" \
  -d "config.auth_header_name=Authorization"
```

## Monitoring and Debugging

### Enable Debug Logs
Check Kong container logs for debug output:
```bash
# View Kong logs
docker logs kong

# Or check log file
tail -f /var/log/kong/error.log
```

### Log Messages to Watch For
```
[debug] Auth cache hit for key: ...
[debug] Making auth request to: http://auth.example.com/verify
[debug] Auth server response status: 200
[debug] JWT header set: X-Token
[warn] Auth header not found: Authorization
[err] Auth server request failed: timeout
```

### Test with curl
```bash
# Request with valid auth header
curl -H "Authorization: Bearer valid-token" http://kong/api

# Request with invalid auth header
curl -H "Authorization: Bearer invalid-token" http://kong/api

# Request without auth header
curl http://kong/api
```

## Troubleshooting

### Plugin Not Loading
1. Check plugin is in plugins directory
2. Verify plugin name in Kong config: `plugins = bundled,remote-auth`
3. Restart Kong
4. Check logs for load errors

### Auth Server Not Responding
1. Verify auth server is running and accessible
2. Check firewall/network rules
3. Verify URL is correct
4. Check auth server logs

### Cache Not Working
1. Verify Kong has shared memory enabled
2. Check cache TTL is positive
3. Monitor ngx.shared.kong usage
4. Review logs for "cache hit" messages

### JWT Not Forwarded
1. Verify auth server returns JSON
2. Check jwt_response_key matches auth response
3. Verify jwt_header_name is set (both fields required)
4. Check backend is receiving the header

## Performance Tips

1. **Increase Cache TTL**: Reduces auth server calls (tradeoff: less frequent updates)
2. **Use Service Auth**: Set `auth_header_value` for fixed tokens (avoids per-request parsing)
3. **Monitor Auth Server**: Ensure it responds quickly (5-second timeout)
4. **Rate Limiting**: Consider adding rate limiting before this plugin

## Security Best Practices

1. **Use HTTPS**: Always use HTTPS for auth server URLs in production
2. **Validate Certificates**: Configure Kong to validate SSL certificates
3. **Secure Tokens**: Don't log auth tokens (use anonymized cache keys)
4. **Network Isolation**: Place auth server on secure network
5. **Timeout Protection**: 5-second timeout prevents slowloris attacks
6. **Cache Invalidation**: Consider cache TTL for token expiration

## Reference

### Configuration Options

| Option | Type | Required | Default | Description |
|--------|------|----------|---------|-------------|
| auth_server_url | string | Yes | - | URL of auth server |
| auth_header_name | string | Yes | - | Header name to validate |
| auth_header_value | string | No | - | Fixed header value (instead of reading from request) |
| cache_ttl | integer | No | 300 | Cache duration in seconds |
| jwt_response_key | string | No | - | JSON key containing JWT (requires jwt_header_name) |
| jwt_header_name | string | No | - | Header to forward JWT (requires jwt_response_key) |
| auth_success_status | integer | No | 200 | HTTP status for successful auth |
| auth_failure_status | integer | No | 401 | HTTP status for failed auth |

### Schema Validation
- `auth_server_url`: Valid HTTP(S) URL
- `auth_header_name`: Valid HTTP header name
- `cache_ttl`: Positive integer
- `auth_success_status`: HTTP status 100-599
- `auth_failure_status`: HTTP status 400-599
- JWT fields: Conditional - both required together
