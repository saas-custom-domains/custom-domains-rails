require "test_helper"

class CustomDomainsTest < ActionDispatch::IntegrationTest
  # What SaaS Custom Domains sends: Host and X-Forwarded-Host are your
  # own hostname, the customer's domain is in X-Served-For.
  def through_proxy(domain, token: "proxy_token")
    {
      "X-Forwarded-Host" => "app.statuspage.com",
      "X-Forwarded-Proto" => "https",
      "X-Served-For" => domain,
      "X-SaaS-Domains-Auth-Token" => token
    }
  end

  setup { host! "app.statuspage.com" }

  test "a customer's domain shows their status page" do
    host! "status.acme.com"
    get "/"
    assert_response :success
    assert_select "h1", "Acme Cloud status"
  end

  test "pending and unknown domains get a 404" do
    host! "status.globex.com"
    get "/"
    assert_response :not_found

    host! "unknown.example.com"
    get "/"
    assert_response :not_found
  end

  test "the app host shows the dashboard, not a status page" do
    get "/"
    assert_response :success
    assert_select "h1", "Statuspage dashboard"

    post "/subscriptions", params: { subscriber: { email: "a@example.com" } }
    assert_response :not_found
  end

  test "the dashboard isn't reachable on a customer's domain" do
    host! "status.acme.com"
    post "/custom_domains", params: { company_id: companies(:acme).id, custom_domain: { host: "x.example.com" } }
    assert_response :not_found
    assert_not CustomDomain.exists?(host: "x.example.com")
  end

  test "through the proxy, X-Served-For picks the status page" do
    get "/", headers: through_proxy("status.acme.com")
    assert_response :success
    assert_select "h1", "Acme Cloud status"
    assert_select "footer", "Served on status.acme.com"
  end

  test "X-Served-For without the right token is rejected" do
    get "/", headers: through_proxy("status.acme.com").except("X-SaaS-Domains-Auth-Token")
    assert_response :forbidden
    get "/", headers: through_proxy("status.acme.com", token: "guess")
    assert_response :forbidden
  end

  test "the subscribe form passes the CSRF check and redirects on the customer's domain" do
    with_forgery_protection do
      https!
      get "/", headers: through_proxy("status.acme.com")
      token = css_select("form[action='/subscriptions'] input[name=authenticity_token]").first["value"]

      # A browser on https://status.acme.com sends this Origin. Rails
      # compares it with request.base_url.
      post "/subscriptions",
        params: { authenticity_token: token, subscriber: { email: "Reader@Example.com" } },
        headers: through_proxy("status.acme.com").merge("Origin" => "https://status.acme.com")

      assert_redirected_to "https://status.acme.com/"
      assert_equal [ "reader@example.com" ], companies(:acme).subscribers.pluck(:email)
      # Host-only session cookie: no Domain attribute.
      assert_no_match(/domain=/i, response.headers["Set-Cookie"].to_s)
    end
  end

  test "a form posted from another origin is still rejected" do
    with_forgery_protection do
      https!
      get "/", headers: through_proxy("status.acme.com")
      token = css_select("input[name=authenticity_token]").first["value"]
      post "/subscriptions",
        params: { authenticity_token: token, subscriber: { email: "a@example.com" } },
        headers: through_proxy("status.acme.com").merge("Origin" => "https://evil.example")
      assert_response :unprocessable_content
    end
  end

  test "the health check and webhooks answer on any host" do
    host! "10.0.0.5"
    get "/up"
    assert_response :success

    post "/webhooks/saas_domains?token=webhook_token", as: :json,
      params: { event: "domain_created", domain: { uuid: "dom_acme" } }
    assert_response :ok
  end

  test "webhooks need the right token" do
    post "/webhooks/saas_domains?token=guess", as: :json,
      params: { event: "domain_dns_proxy_record_valid", domain: { uuid: "dom_globex" } }
    assert_response :unauthorized

    ENV["SCD_WEBHOOK_TOKEN"] = ""
    post "/webhooks/saas_domains?token=", as: :json,
      params: { event: "domain_dns_proxy_record_valid", domain: { uuid: "dom_globex" } }
    assert_response :unauthorized
    assert custom_domains(:globex).reload.pending?
  end

  test "webhooks update the domain's status" do
    hook = ->(event, uuid = "dom_globex") {
      post "/webhooks/saas_domains?token=webhook_token", as: :json,
        params: { event: event, domain: { uuid: uuid, host: "status.globex.com" } }
      assert_response :ok
    }
    domain = custom_domains(:globex)

    hook.("domain_dns_proxy_record_valid")
    assert domain.reload.active?
    assert_not domain.live?
    hook.("tls_certificate_issued")
    assert domain.reload.live?
    hook.("domain_dns_proxy_record_invalid")
    assert domain.reload.pending?
    hook.("domain_dns_proxy_record_valid", "not_ours")
  end

  test "adding a domain registers it in the background" do
    assert_enqueued_with(job: RegisterCustomDomainJob) do
      post "/custom_domains", params: {
        company_id: companies(:acme).id,
        custom_domain: { host: "Status.Example.com", dns_contact_email: "" }
      }
    end
    assert_redirected_to "http://app.statuspage.com/"
    assert CustomDomain.find_by!(host: "status.example.com").pending?
  end

  test "our own domains are rejected" do
    assert_no_enqueued_jobs do
      post "/custom_domains", params: { company_id: companies(:acme).id, custom_domain: { host: "admin.statuspage.com" } }
    end
    follow_redirect!
    assert_select "[role=alert]", "Host can't be one of our own domains"
  end

  private

  def with_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    yield
  ensure
    ActionController::Base.allow_forgery_protection = false
  end
end
