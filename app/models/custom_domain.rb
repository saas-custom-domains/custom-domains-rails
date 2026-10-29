class CustomDomain < ApplicationRecord
  belongs_to :company

  enum :status, { pending: "pending", active: "active" }

  normalizes :host, with: ->(host) { host.strip.downcase.chomp(".") }
  normalizes :dns_contact_email, with: ->(e) { e.strip.presence }

  validates :host, presence: true, uniqueness: true,
    format: { with: /\A[a-z0-9-]+(\.[a-z0-9-]+)+\z/ }
  validates :dns_contact_email, allow_nil: true,
    format: { with: URI::MailTo::EMAIL_REGEXP }
  validate :not_one_of_our_domains

  # Register new domains with SaaS Custom Domains in the background.
  after_create_commit :register

  # The one place that reads the hostname. Behind SaaS Custom
  # Domains, SaasDomainsProxy has already put the customer's domain
  # (from X-Served-For) into X-Forwarded-Host, so this stays as is.
  def self.host_from(request)
    request.host.downcase
  end

  # Hostnames your own app answers on: your domain, plus any internal
  # name your platform uses to reach the app (health checks, webhooks).
  def self.app_hosts
    ENV.fetch("APP_HOSTS", "localhost").split(",")
      .map { it.strip.downcase }.compact_blank
  end

  def self.app_host?(host)
    app_hosts.include?(host)
  end

  # DNS pointed at the proxy, and the certificate is issued.
  def live?
    active? && https_ready?
  end

  # The "Check DNS" button: ask SaaS Custom Domains to look now.
  def check_dns!
    return unless provider_uuid # not registered yet

    res = SaasDomains.new.verify_dns(provider_uuid)
    update!(status: res["dns_status"] == "valid" ? :active : :pending)
    res["dns_status"] # "valid", "pending" or "invalid"
  end

  private

  def register
    RegisterCustomDomainJob.perform_later(self)
  end

  def not_one_of_our_domains
    ours = ENV.fetch("APP_DOMAIN") # "statuspage.com"
    if host == ours || host.to_s.end_with?(".#{ours}") ||
        self.class.app_host?(host)
      errors.add(:host, "can't be one of our own domains")
    end
  end
end
