require "resolv"

class CustomDomain < ApplicationRecord
  belongs_to :company

  enum :status, { pending: "pending", active: "active" }

  normalizes :host, with: ->(host) { host.strip.downcase.chomp(".") }
  normalizes :dns_contact_email, with: ->(email) { email.strip.presence }

  validates :host, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/ }
  validates :dns_contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validate :not_one_of_our_domains

  # Register new domains with SaaS Custom Domains in the background.
  after_create_commit -> { RegisterCustomDomainJob.perform_later(self) }, if: -> { self.class.managed? }

  # The one place that reads the hostname. Behind SaaS Custom Domains,
  # SaasDomainsProxy has already put the customer's domain (from
  # X-Served-For) into X-Forwarded-Host, so request.host is right here too.
  def self.host_from(request)
    request.host.downcase
  end

  # Hostnames your own app answers on: your domain, plus any internal
  # name your platform uses to reach the app (health checks, webhooks).
  def self.app_hosts
    ENV.fetch("APP_HOSTS", "localhost").split(",").map { it.strip.downcase }.compact_blank
  end

  def self.app_host?(host)
    app_hosts.include?(host)
  end

  # "saascustomdomains" (the default) or "caddy" if you run your own proxy.
  def self.managed?
    ENV.fetch("DOMAINS_PROVIDER", "saascustomdomains") == "saascustomdomains"
  end

  def live?
    active? && (https_ready? || !self.class.managed?)
  end

  # Ask the provider (or DNS, if you run the proxy yourself) whether the
  # domain points at us yet.
  def check_dns!
    if self.class.managed?
      return unless provider_uuid # RegisterCustomDomainJob hasn't run yet
      valid = SaasDomains.new.verify_dns(provider_uuid)["dns_status"] == "valid"
    else
      valid = dns_points_to_us?
    end
    update!(status: valid ? :active : :pending)
  end

  # Only needed when you run the proxy yourself: with SaaS Custom
  # Domains, the API checks DNS for you.
  def dns_points_to_us?
    # *.localhost always resolves to this machine.
    return true if host.end_with?(".localhost")

    cname_target = ENV.fetch("CNAME_TARGET", "in.statuspage.com")
    our_ips = ENV.fetch("SERVER_IPS", "").split(",").map(&:strip)

    Resolv::DNS.open do |dns|
      dns.timeouts = 3
      cnames = dns.getresources(host, Resolv::DNS::Resource::IN::CNAME)
      ips = dns.getaddresses(host).map(&:to_s)

      cnames.any? { |r| r.name.to_s.casecmp?(cname_target) } ||
        ips.intersect?(our_ips)
    end
  end

  private

  def not_one_of_our_domains
    ours = ENV.fetch("APP_DOMAIN") # "statuspage.com"
    if host == ours || host.to_s.end_with?(".#{ours}") || self.class.app_host?(host)
      errors.add(:host, "can't be one of our own domains")
    end
  end
end
