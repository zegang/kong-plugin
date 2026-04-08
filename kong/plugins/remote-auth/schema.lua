local typedefs = require "kong.db.schema.typedefs"


local PLUGIN_NAME = "remote-auth"


local schema = {
  name = PLUGIN_NAME,
  fields = {
    -- the 'fields' array is the top-level entry with fields defined by Kong
    { consumer = typedefs.no_consumer },  -- this plugin cannot be configured on a consumer (typical for auth plugins)
    { protocols = typedefs.protocols_http },
    { config = {
        -- The 'config' record is the custom part of the plugin schema
        type = "record",
        fields = {
          -- Required: Auth server URL
          { auth_server_url = typedefs.url {
              required = true } },
          
          -- Required: Name of the header containing the auth credential
          { auth_header_name = typedefs.header_name {
              required = true } },
          
          -- Optional: Value to send as the header (if not provided, use the value from incoming request)
          { auth_header_value = {
              type = "string",
              required = false } },
          
          -- Optional: Cache TTL in seconds
          { cache_ttl = {
              type = "integer",
              default = 300,
              required = false,
              gt = 0 } },
          
          -- Optional: Key name in auth server response containing JWT
          { jwt_response_key = {
              type = "string",
              required = false } },
          
          -- Optional: Header name to forward JWT token to backend
          { jwt_header_name = typedefs.header_name {
              type = "string",
              required = false } },
          
          -- Optional: HTTP status to treat as success (default: 200)
          { auth_success_status = {
              type = "integer",
              default = 200,
              required = false,
              between = { 100, 599 } } },
          
          -- Optional: HTTP status to return on auth failure (default: 401)
          { auth_failure_status = {
              type = "integer",
              default = 401,
              required = false,
              between = { 400, 599 } } },
        },
      },
    },
  },
  entity_checks = {
    { custom_entity_check = {
        field_sources = { "config.jwt_response_key", "config.jwt_header_name" },
        fn = function(entity)
          local config = entity.config
          
          -- Check if jwt_response_key is a valid string (not nil and not ngx.null)
          local has_response_key = config.jwt_response_key ~= nil and config.jwt_response_key ~= ngx.null
          
          -- Check if jwt_header_name is missing or null
          local no_header_name = config.jwt_header_name == nil or config.jwt_header_name == ngx.null
  
          if has_response_key and no_header_name then
             return nil, "jwt_header_name is required when jwt_response_key is provided"
          end
          
          return true
        end
    } },
  }
}

return schema
