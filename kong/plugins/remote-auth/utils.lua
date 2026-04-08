local http = require "resty.http"
local cjson = require "cjson"

local M = {}

-- Generate a cache key for the auth result
function M.get_cache_key(auth_header_value)
  return "auth_result:" .. ngx.encode_base64(auth_header_value)
end

-- Get cached auth result, if any
function M.get_cached_result(cache_key)
  if not ngx.shared.kong then
    return nil
  end

  local cached = ngx.shared.kong:get(cache_key)
  if cached then
    kong.log.debug("Auth cache hit for key: ", cache_key)
    return cjson.decode(cached)
  end
  return nil
end

-- Cache auth result
function M.cache_result(cache_key, result, ttl)
  if not ngx.shared.kong then
    kong.log.warn("ngx.shared.kong not available, caching disabled")
    return
  end

  local encoded = cjson.encode(result)
  ngx.shared.kong:set(cache_key, encoded, ttl)
  kong.log.debug("Cached auth result for key: ", cache_key, " with TTL: ", ttl)
end

-- Make HTTP request to auth server
function M.authenticate(auth_server_url, auth_header_name, auth_header_value, success_status)
  local httpc = http.new()

  -- Set timeout to 5 seconds
  httpc:set_timeout(5000)

  local headers = {
    [auth_header_name] = auth_header_value
  }

  kong.log.debug("Making auth request to: ", auth_server_url, " with header: ", auth_header_name)

  local res, err = httpc:request_uri(auth_server_url, {
    method = "GET",
    headers = headers,
  })

  if err then
    kong.log.err("Auth server request failed: ", err)
    return { authenticated = false, error = err }
  end

  local authenticated = res.status == (success_status or 200)
  local response_body = res.body

  kong.log.debug("Auth server response status: ", res.status)

  return {
    authenticated = authenticated,
    status = res.status,
    body = response_body,
  }
end

-- Parse JWT from auth server response
function M.extract_jwt(response_body, jwt_response_key)
  if not response_body or not jwt_response_key then
    return nil
  end

  local ok, data = pcall(function()
    return cjson.decode(response_body)
  end)

  if not ok then
    kong.log.warn("Failed to parse auth server response as JSON")
    return nil
  end

  local jwt = data[jwt_response_key]
  if jwt then
    kong.log.debug("Extracted JWT from response using key: ", jwt_response_key)
  end

  return jwt
end

return M