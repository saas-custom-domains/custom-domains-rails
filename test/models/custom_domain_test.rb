require "test_helper"

class CustomDomainTest < ActiveSupport::TestCase
  def build(host)
    companies(:acme).custom_domains.new(host: host)
  end

  test "normalizes the host" do
    assert_equal "status.example.com", build(" Status.Example.COM. ").host
  end

  test "accepts real hostnames" do
    %w[status.example.com example.co.uk xn--bcher-kva.example].each do |host|
      assert build(host).valid?, host
    end
  end

  test "rejects anything that isn't a hostname" do
    [ "example", "exa mple.com", "https://example.com", "example..com", "" ].each do |host|
      assert_not build(host).valid?, host
    end
  end

  test "rejects our own domains" do
    %w[statuspage.com admin.statuspage.com app.statuspage.com].each do |host|
      domain = build(host)
      assert_not domain.valid?, host
      assert_includes domain.errors[:host], "can't be one of our own domains"
    end
    assert build("notstatuspage.com").valid?
  end

  test "a domain belongs to one company only" do
    domain = companies(:globex).custom_domains.new(host: "STATUS.acme.com")
    assert_not domain.valid?
    assert_includes domain.errors[:host], "has already been taken"
  end

  test "*.localhost always points at us" do
    assert build("acme.localhost").dns_points_to_us?
  end

  test "app hosts come from APP_HOSTS" do
    assert CustomDomain.app_host?("app.statuspage.com")
    assert CustomDomain.app_host?("localhost")
    assert_not CustomDomain.app_host?("status.acme.com")
  end

  test "Live only once DNS is valid and the certificate is issued" do
    domain = custom_domains(:acme)
    assert domain.live?
    domain.https_ready = false
    assert_not domain.live?
  end
end
