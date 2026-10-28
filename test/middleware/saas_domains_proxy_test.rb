require "test_helper"

class SaasDomainsProxyTest < ActiveSupport::TestCase
  setup do
    @seen = nil
    inner = ->(env) { @seen = env; [ 200, {}, [ "ok" ] ] }
    @proxy = Rack::MockRequest.new(SaasDomainsProxy.new(inner))
  end

  def get(headers)
    @proxy.get("/", headers.transform_keys { "HTTP_#{it.upcase.tr("-", "_")}" })
  end

  test "requests without X-Served-For pass through untouched" do
    assert_equal 200, get("Host" => "app.statuspage.com").status
    assert_nil @seen["HTTP_X_FORWARDED_HOST"]
  end

  test "a valid token hands the customer's domain to Rails" do
    res = get("X-Served-For" => "status.acme.com", "X-SaaS-Domains-Auth-Token" => "proxy_token",
      "X-Forwarded-Host" => "app.statuspage.com")
    assert_equal 200, res.status
    assert_equal "status.acme.com", @seen["HTTP_X_FORWARDED_HOST"]
    assert_equal "status.acme.com", ActionDispatch::Request.new(@seen).host
  end

  test "a missing or wrong token is rejected" do
    assert_equal 403, get("X-Served-For" => "status.acme.com").status
    assert_equal 403, get("X-Served-For" => "status.acme.com", "X-SaaS-Domains-Auth-Token" => "guess").status
    assert_nil @seen
  end

  test "an unset or empty PROXY_AUTH_TOKEN rejects everything" do
    ENV["PROXY_AUTH_TOKEN"] = ""
    assert_equal 403, get("X-Served-For" => "status.acme.com", "X-SaaS-Domains-Auth-Token" => "").status
    ENV.delete("PROXY_AUTH_TOKEN")
    assert_equal 403, get("X-Served-For" => "status.acme.com", "X-SaaS-Domains-Auth-Token" => "").status
  end

  test "is in the middleware stack" do
    assert_includes Rails.application.middleware.map(&:klass), SaasDomainsProxy
  end
end
