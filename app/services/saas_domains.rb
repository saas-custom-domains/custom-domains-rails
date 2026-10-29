require "net/http"

# A small client for the SaaS Custom Domains API, with nothing but the
# standard library. Docs: https://docs.saascustomdomains.com
class SaasDomains
  class Error < StandardError
    attr_reader :status

    def initialize(status, body)
      @status = status
      super("SaaS Custom Domains API #{status}: #{body}")
    end

    # 4xx means the API said no (e.g. host_taken); retrying won't help.
    def rejected?
      status.between?(400, 499)
    end
  end

  def initialize
    # SCD_API_URL is only for the local mock. Leave it unset in
    # production.
    @base = ENV["SCD_API_URL"] || "https://app.saascustomdomains.com"
    @account = ENV.fetch("SCD_ACCOUNT_UUID")
    @token = ENV.fetch("SCD_API_TOKEN")
  end

  def create_upstream(host)
    request(:post, "upstreams", host: host)
  end

  def create_domain(host, **options)
    request(:post, domains_path, { host: host, **options }.compact)
  end

  def verify_dns(uuid)
    request(:post, "#{domains_path}/#{uuid}/verify_dns_records")
  end

  def delete_domain(uuid)
    request(:delete, "#{domains_path}/#{uuid}")
  rescue Error => e
    # Already gone is fine: the goal is that it doesn't exist.
    raise unless e.status == 404
  end

  private

  def domains_path
    "upstreams/#{ENV.fetch("SCD_UPSTREAM_UUID")}/custom_domains"
  end

  def request(verb, path, body = nil)
    uri = URI("#{@base}/api/v1/accounts/#{@account}/#{path}")
    req = Net::HTTP.const_get(verb.capitalize).new(uri)
    req["Authorization"] = "Bearer #{@token}"
    req["Content-Type"] = "application/json"
    req.body = body.to_json if body

    res = Net::HTTP.start(uri.host, uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: 5, read_timeout: 10) { |http| http.request(req) }
    unless res.is_a?(Net::HTTPSuccess)
      raise Error.new(res.code.to_i, res.body)
    end

    res.body.present? ? JSON.parse(res.body) : {}
  end
end
