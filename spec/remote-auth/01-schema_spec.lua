local PLUGIN_NAME = "remote-auth"


-- helper function to validate data against a schema
local validate do
  local validate_entity = require("spec.helpers").validate_plugin_config_schema
  local plugin_schema = require("kong.plugins."..PLUGIN_NAME..".schema")

  function validate(data)
    return validate_entity(data, plugin_schema)
  end
end


describe(PLUGIN_NAME .. ": (schema)", function()

  it("requires auth_server_url", function()
    local ok, err = validate({
        auth_header_name = "Authorization",
      })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  it("requires auth_header_name", function()
    local ok, err = validate({
        auth_server_url = "http://auth.example.com/verify",
      })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  it("accepts minimal required configuration", function()
    local ok, err = validate({
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts full configuration", function()
    local ok, err = validate({
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
        auth_header_value = "bearer-token-123",
        cache_ttl = 600,
        jwt_response_key = "access_token",
        jwt_header_name = "X-Token",
        auth_success_status = 200,
        auth_failure_status = 401,
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("provides default cache_ttl", function()
    local ok, err = validate({
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("rejects invalid cache_ttl (zero)", function()
    local ok, err = validate({
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
        cache_ttl = 0,
      })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  it("rejects invalid cache_ttl (negative)", function()
    local ok, err = validate({
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
        cache_ttl = -100,
      })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  it("provides default auth_success_status", function()
    local ok, err = validate({
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts custom auth_success_status", function()
    local ok, err = validate({
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
        auth_success_status = 204,
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("accepts custom auth_failure_status", function()
    local ok, err = validate({
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
        auth_failure_status = 403,
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

  it("rejects invalid auth_failure_status (too low)", function()
    local ok, err = validate({
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
        auth_failure_status = 301,
      })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  it("enforces conditional validation: jwt_response_key requires jwt_header_name", function()
    local ok, err = validate({
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
        jwt_response_key = "access_token",
        -- missing jwt_header_name
      })
    assert.is_falsy(ok)
    assert.is_truthy(err)
  end)

  it("allows jwt_response_key with jwt_header_name", function()
    local ok, err = validate({
        auth_server_url = "http://auth.example.com/verify",
        auth_header_name = "Authorization",
        jwt_response_key = "access_token",
        jwt_header_name = "X-Token",
      })
    assert.is_nil(err)
    assert.is_truthy(ok)
  end)

end)
