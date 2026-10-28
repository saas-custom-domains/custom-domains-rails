class RemoveCustomDomainJob < ApplicationJob
  retry_on SaasDomains::Error, Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNREFUSED,
    wait: :polynomially_longer, attempts: 10
  discard_on ActiveJob::DeserializationError # already removed

  # Proxy first, database second: if the API call fails, the row is
  # still here and the job is retried.
  def perform(domain)
    SaasDomains.new.delete_domain(domain.provider_uuid) if domain.provider_uuid
    domain.destroy!
  end
end
