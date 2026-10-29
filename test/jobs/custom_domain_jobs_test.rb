require "test_helper"
require "webmock/minitest"

class CustomDomainJobsTest < ActiveJob::TestCase
  DOMAINS = "http://scd.test/api/v1/accounts/acc_1/upstreams/up_1/custom_domains"

  test "registers the domain and keeps the provider's uuid" do
    domain = companies(:acme).custom_domains.create!(host: "status.example.com", dns_contact_email: "dns@example.com")
    stub = stub_request(:post, DOMAINS)
      .with(body: { host: "status.example.com", instructions_recipient: "dns@example.com" }.to_json,
        headers: { "Authorization" => "Bearer api_token" })
      .to_return(status: 201, body: { uuid: "dom_new", host: "status.example.com" }.to_json)

    RegisterCustomDomainJob.perform_now(domain)

    assert_requested stub
    assert_equal "dom_new", domain.reload.provider_uuid
  end

  test "leaves out an empty DNS contact" do
    domain = companies(:acme).custom_domains.create!(host: "status.example.com")
    stub_request(:post, DOMAINS).with(body: { host: "status.example.com" }.to_json)
      .to_return(status: 201, body: { uuid: "dom_new" }.to_json)
    RegisterCustomDomainJob.perform_now(domain)
    assert_equal "dom_new", domain.reload.provider_uuid
  end

  test "a domain the API rejects is removed locally too" do
    domain = companies(:acme).custom_domains.create!(host: "taken.example.com")
    stub_request(:post, DOMAINS).to_return(status: 400,
      body: { error: "Host has already been taken", error_code: "host_taken" }.to_json)

    RegisterCustomDomainJob.perform_now(domain)

    assert_not CustomDomain.exists?(domain.id)
  end

  test "server errors are retried" do
    domain = companies(:acme).custom_domains.create!(host: "status.example.com")
    stub_request(:post, DOMAINS).to_return(status: 503)

    assert_enqueued_with(job: RegisterCustomDomainJob) do
      RegisterCustomDomainJob.perform_now(domain)
    end
    assert CustomDomain.exists?(domain.id)
  end

  test "removes the domain from the proxy, then the database" do
    domain = custom_domains(:acme)
    stub = stub_request(:delete, "#{DOMAINS}/dom_acme").to_return(status: 200, body: "{}")
    RemoveCustomDomainJob.perform_now(domain)
    assert_requested stub
    assert_not CustomDomain.exists?(domain.id)
  end

  test "a domain already gone from the proxy is still removed" do
    domain = custom_domains(:acme)
    stub_request(:delete, "#{DOMAINS}/dom_acme").to_return(status: 404,
      body: { error: "Custom domain dom_acme not found.", error_code: "not_found" }.to_json)
    RemoveCustomDomainJob.perform_now(domain)
    assert_not CustomDomain.exists?(domain.id)
  end

  test "if the API is down, the row stays and the job retries" do
    domain = custom_domains(:acme)
    stub_request(:delete, "#{DOMAINS}/dom_acme").to_return(status: 500)
    assert_enqueued_with(job: RemoveCustomDomainJob) { RemoveCustomDomainJob.perform_now(domain) }
    assert CustomDomain.exists?(domain.id)
  end

  test "Check DNS asks the API" do
    domain = custom_domains(:globex)
    stub_request(:post, "#{DOMAINS}/dom_globex/verify_dns_records")
      .to_return(status: 200, body: { dns_status: "valid" }.to_json)
    domain.check_dns!
    assert domain.reload.active?

    stub_request(:post, "#{DOMAINS}/dom_globex/verify_dns_records")
      .to_return(status: 200, body: { dns_status: "invalid" }.to_json)
    domain.check_dns!
    assert domain.reload.pending?
  end
end
