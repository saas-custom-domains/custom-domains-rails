class RegisterCustomDomainJob < ApplicationJob
  # Network errors and 5xx: try again later. If it never works, don't
  # keep a domain the proxy doesn't know about.
  retry_on SaasDomains::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED,
    wait: :polynomially_longer, attempts: 5 do |job, _error|
    job.arguments.first.destroy!
  end
  discard_on ActiveJob::DeserializationError # removed in the meantime

  def perform(domain)
    res = SaasDomains.new.create_domain(
      domain.host,
      # Whoever manages their DNS gets step-by-step instructions
      instructions_recipient: domain.dns_contact_email
    )
    domain.update!(provider_uuid: res["uuid"])
  rescue SaasDomains::Error => e
    raise unless e.rejected?

    # The API said no (e.g. host_taken): remove our row too.
    Rails.logger.warn("Removing #{domain.host}: #{e.message}")
    domain.destroy!
  end
end
