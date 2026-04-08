local PLUGIN_NAME = "remote-auth"


describe(PLUGIN_NAME .. ": (unit)", function()

  local plugin
  local headers_set = {}
  local response_exited = false
  local exit_status = nil
  local exit_body = nil


  setup(function()
    -- Mock Kong functions
    _G.kong = {
      log = {
        debug = function(...) end,
        warn = function(...) end,
        err = function(...) end,
      },
      request = {
        get_header = function(name)
          return headers_set[name]
        end,
      },
      service = {
        request = {
          set_header = function(name, value)
            headers_set[name] = value
          end,
        },
      },
      response = {
        exit = function(status, body)
          response_exited = true
          exit_status = status
          exit_body = body
          error("Response exit called")  -- Exit the handler
        end,
      },
    }

    -- Mock ngx functions
    _G.ngx = {
      log = function() end,
      encode_base64 = function(str)
        return "base64_" .. str
      end,
      shared = {
        kong = {
          get = function() return nil end,
          set = function() end,
        }
      }
    }

    -- Load and mock the authenticate function in module utils
    local utils = require("kong.plugins."..PLUGIN_NAME..".utils")
    _G.package.loaded["kong.plugins."..PLUGIN_NAME..".utils"]["authenticate"] =
      function(auth_server_url, auth_header_name, auth_header_value, success_status)
        print("calling mocked utils.authentication......")
        return { 
          authenticated = true,
          status = 200,
          body = '{ "authenticated": true, "status":'..success_status..', "token": "'..auth_header_value..'" }'
        }
      end

    -- Load the plugin code
    plugin = require("kong.plugins."..PLUGIN_NAME..".handler")
  end)


  before_each(function()
    headers_set = {}
    response_exited = false
    exit_status = nil
    exit_body = nil
  end)


  describe("Missing authentication header", function()
    it("returns 401 when auth header is missing", function()
      headers_set = {}
      local config = {
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
      }

      local ok, err = pcall(function()
        plugin:access(config)
      end)

      assert.is_false(ok)
      assert.is_true(response_exited)
      assert.equal(401, exit_status)
    end)

    it("uses configured auth_failure_status", function()
      headers_set = {}
      local config = {
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
        auth_failure_status = 403,
      }

      local ok, err = pcall(function()
        plugin:access(config)
      end)

      assert.is_false(ok)
      assert.is_true(response_exited)
      assert.equal(403, exit_status)
    end)
  end)


  describe("Configuration options", function()
    it("handles auth_header_value configuration (fixed value)", function()
      local fixed_token = "fixed-token-123"
      -- When auth_header_value is configured in the plugin, it should use that
      -- instead of reading from the request header
      local config = {
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
        auth_header_value = fixed_token,
        jwt_response_key = "token",
        jwt_header_name = "X-JWT-Header",
      }

      local ok, err = pcall(function()
        plugin:access(config)
      end)

      assert.is_true(ok)
      assert.equal(fixed_token, headers_set[config.jwt_header_name])
    end)

    it("accepts cache_ttl configuration", function()
      local config = {
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
        cache_ttl = 600,
      }
      assert.equal(600, config.cache_ttl)
    end)

    it("accepts JWT configuration", function()
      local config = {
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
        jwt_response_key = "token",
        jwt_header_name = "X-Token",
      }
  
      local mycustomtoken = 'mycustomtoken'
      headers_set[config.auth_header_name] = mycustomtoken

      local ok, err = pcall(function()
        plugin:access(config)
      end)

      assert.is_true(ok)
      assert.equal(mycustomtoken, headers_set[config.jwt_header_name])
    end)

    it("accepts custom auth_success_status", function()
      local config = {
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
        jwt_response_key = "token",
        jwt_header_name = "X-Token",
        auth_success_status = 204,
      }
  
      local mycustomtoken = 'mycustomtoken'
      headers_set[config.auth_header_name] = mycustomtoken
  
      local ok, err = pcall(function()
        plugin:access(config)
      end)

      assert.is_true(ok)
      assert.equal(mycustomtoken, headers_set[config.jwt_header_name])
    end)
  end)

end)
