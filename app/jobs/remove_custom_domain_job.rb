class RemoveCustomDomainJob < ApplicationJob
  retry_on(*RegisterCustomDomainJob::TRANSIENT_ERRORS,
    wait: :polynomially_longer, attempts: 10)
  discard_on ActiveJob::DeserializationError # already removed

  # Proxy first, database second: if the API call fails, the row is
  # still here and the job is retried.
  def perform(domain)
    if domain.provider_uuid
      SaasDomains.new.delete_domain(domain.provider_uuid)
    end
    domain.destroy!
  end
end
