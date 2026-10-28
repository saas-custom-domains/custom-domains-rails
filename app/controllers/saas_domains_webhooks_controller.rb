# Events: https://docs.saascustomdomains.com/webhooks
class SaasDomainsWebhooksController < ActionController::API
  before_action :verify_webhook_token

  def create
    uuid = params.dig(:domain, :uuid)
    domain = CustomDomain.find_by(provider_uuid: uuid)
    # Not ours, or already removed: acknowledge so it isn't retried.
    return head :ok unless domain

    case params[:event]
    when "domain_dns_proxy_record_valid" then domain.active!
    when "domain_dns_proxy_record_invalid" then domain.pending!
    when "tls_certificate_issued" then domain.update!(https_ready: true)
    end

    head :ok
  end

  private

  def verify_webhook_token
    expected = ENV["SCD_WEBHOOK_TOKEN"].to_s
    token = params[:token].to_s
    valid = expected.present? && ActiveSupport::SecurityUtils.secure_compare(token, expected)
    head :unauthorized unless valid
  end
end
