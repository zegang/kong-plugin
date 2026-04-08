local helpers = require "spec.helpers"
local cjson = require "cjson"


local PLUGIN_NAME = "remote-auth"


for _, strategy in helpers.all_strategies() do if strategy ~= "cassandra" then
  describe(PLUGIN_NAME .. ": (integration) [#" .. strategy .. "]", function()
    local client
    local httpbin_host = os.getenv("HTTPBIN_HOST") or "httpbin"
    local httpbin_port = tonumber(os.getenv("HTTPBIN_PORT") or "80")
    local httpbin_url = string.format("http://%s:%s", httpbin_host, httpbin_port)

    lazy_setup(function()
      local dbu = helpers.get_db_utils(strategy, nil, { PLUGIN_NAME })

      local service1 = dbu.services:insert({
        name = "httpbin",
        protocol = "http",
        host = httpbin_host,
        port = httpbin_port,
      })

      local route1 = dbu.routes:insert({
        hosts = { "auth-test.com" },
        paths = { "/bearer" },
        service = service1,
      })
      
      local auth_server_url = httpbin_url .. "/bearer"
      
      dbu.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route1.id },
        config = {
          auth_server_url = auth_server_url,
          auth_header_name = "Authorization",
          cache_ttl = 300,
          jwt_response_key = "token",
          jwt_header_name = "Authorization",
        },
      }

      -- start kong
      assert(helpers.start_kong({
        -- set the strategy
        database   = strategy,
        -- make sure our plugin gets loaded
        plugins = "bundled," .. PLUGIN_NAME,
        -- write & load declarative config, only if 'strategy=off'
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)


    describe("Authentication Flow", function()
      
      it("should block requests without Authorization header", function()
        local r = client:get("/bearer", {
          headers = {
            host = "auth-test.com"
          }
        })
        assert.response(r).has.status(401)
      end)

      it("should validate Authorization header against local httpbin and allow valid bearer tokens", function()
        local r = client:get("/bearer", {
          headers = {
            host = "auth-test.com",
            authorization = "Bearer test-token"
          }
        })
        assert.response(r).has.status(200)
      end)

    end)

  end)

end end
