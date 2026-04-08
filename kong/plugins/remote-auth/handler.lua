local utils = require "kong.plugins.remote-auth.utils"


local plugin = {
  PRIORITY = 1000, -- set the plugin priority, which determines plugin execution order
  VERSION = "0.1", -- version in X.Y.Z format. Check hybrid-mode compatibility requirements.
}


-- Main access handler
function plugin:access(plugin_conf)
  
  -- Get the auth header value from the incoming request
  -- Use configured value if provided, otherwise read from request header
  local auth_header_value = plugin_conf.auth_header_value
  if not auth_header_value then
    auth_header_value = kong.request.get_header(plugin_conf.auth_header_name)
  end
  
  if not auth_header_value then
    kong.log.warn("Auth header not found: ", plugin_conf.auth_header_name)
    return kong.response.exit(
      plugin_conf.auth_failure_status or 401,
      { message = "Missing authentication header" }
    )
  end
  
  -- Try to get from cache
  local cache_key = utils.get_cache_key(auth_header_value)
  local cached_result = utils.get_cached_result(cache_key)
  
  local auth_result
  if cached_result then
    auth_result = cached_result
  else
    -- Make the auth request
    auth_result = utils.authenticate(
      plugin_conf.auth_server_url,
      plugin_conf.auth_header_name,
      auth_header_value,
      plugin_conf.auth_success_status or 200
    )
    
    -- Cache the result
    if auth_result and auth_result.authenticated ~= nil then
      utils.cache_result(cache_key, auth_result, plugin_conf.cache_ttl or 300)
    end
  end
  
  -- Check if authentication succeeded
  if not auth_result.authenticated then
    kong.log.warn("Authentication failed with status: ", auth_result.status)
    return kong.response.exit(
      plugin_conf.auth_failure_status or 401,
      { message = "Authentication failed" }
    )
  end
  
  kong.log.debug("Authentication successful")
  
  -- Extract and forward JWT if configured
  if plugin_conf.jwt_response_key and plugin_conf.jwt_header_name and auth_result.body then
    local jwt = utils.extract_jwt(auth_result.body, plugin_conf.jwt_response_key)
    if jwt then
        kong.service.request.set_header(plugin_conf.jwt_header_name, jwt)
        kong.log.debug("JWT header set: ", plugin_conf.jwt_header_name, ", ", jwt)
    end
  end
  
end

-- return our plugin object
return plugin
