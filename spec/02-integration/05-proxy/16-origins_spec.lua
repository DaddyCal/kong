local helpers = require "spec.helpers"

describe("origins config option", function()
  describe("format checking", function()
    after_each(function()
      helpers.stop_kong()
    end)
    it("rejects an invalid origins config option", function()
      local ok, err = helpers.start_kong({
        origins = "invalid_origin",
      })
      assert.falsy(ok)
      assert.matches("origins must be of form", err)
    end)
    it("rejects an invalid origins config option", function()
      local ok, err = helpers.start_kong({
        origins = "http://foo:42=http://",
      })
      assert.falsy(ok)
      assert.matches("origins must be of form", err)
    end)
    it("rejects an unknown scheme", function()
      local ok, err = helpers.start_kong({
        origins = "http://foo:42=ftp://example.com",
      })
      assert.falsy(ok)
      assert.matches("origins must be of form", err)
    end)
    it("rejects duplicates", function()
      local ok, err = helpers.start_kong({
        origins = table.concat({
          "http://src:42=https://foo",
          "http://src:42=https://bar",
        }, ",")
      })
      assert.falsy(ok)
      assert.matches("duplicate", err)
    end)
    it("accepts an authority with no port as destination", function()
      assert.truthy(helpers.start_kong({
        origins = "http://foo:42=https://example.com",
      }))
    end)
    it("accepts both ips and hosts", function()
      assert.truthy(helpers.start_kong({
        origins = table.concat({
          "http://src1:42=https://dst:55",
          "http://src2:42=https://127.0.0.1:55",
          "http://src3:42=https://[::1]:55",
          "http://127.0.0.1:42=https://dst:55",
          "http://127.0.0.2:42=https://127.0.0.1:55",
          "http://127.0.0.3:42=https://[::1]:55",
          "http://[::1]:42=https://dst:55",
          "http://[::2]:42=https://127.0.0.1:55",
          "http://[::3]:42=https://[::1]:55",
        }, ",")
      }))
    end)
  end)
  describe("end-to-end tests", function()
    local proxy_client
    local bp, db, dao

    before_each(function()
      bp, db, dao = helpers.get_db_utils()
    end)

    after_each(function()
      if proxy_client then
        proxy_client:close()
      end

      dao:truncate_tables()
      assert(db:truncate())
      helpers.stop_kong()
    end)

    it("respects origins for overriding resolution", function()
      local service = bp.services:insert({
        protocol = helpers.mock_upstream_protocol,
        host     = helpers.mock_upstream_host,
        port     = 1, -- wrong port
      })
      bp.routes:insert({
        service = service,
        hosts = { "mock_upstream" }
      })

      -- Check that error occurs trying to talk to port 1
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
      }))

      proxy_client = helpers.proxy_client()
      local res = proxy_client:get("/request", {
        headers = { Host = "mock_upstream" }
      })
      assert.res_status(502, res)
      proxy_client:close()
      helpers.stop_kong(nil, nil, true)

      -- Now restart with origins option
      assert(helpers.start_kong({
        nginx_conf = "spec/fixtures/custom_nginx.template",
        origins = string.format("%s://%s:%d=%s://%s:%d",
          helpers.mock_upstream_protocol,
          helpers.mock_upstream_host,
          1,
          helpers.mock_upstream_protocol,
          helpers.mock_upstream_host,
          helpers.mock_upstream_port),
      }))

      proxy_client = helpers.proxy_client()
      local res = proxy_client:get("/request", {
        headers = { Host = "mock_upstream" }
      })
      assert.res_status(200, res)
    end)
  end)
end)
