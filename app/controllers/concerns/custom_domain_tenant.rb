module CustomDomainTenant
  extend ActiveSupport::Concern

  included do
    before_action :set_company_from_domain
  end

  private

  # Unknown and pending domains raise ActiveRecord::RecordNotFound,
  # which Rails turns into a 404.
  def set_company_from_domain
    host = CustomDomain.host_from(request)
    domain = CustomDomain.active.find_by!(host: host)
    Current.company = domain.company
  end
end
