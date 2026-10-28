class StatusPagesController < ApplicationController
  include CustomDomainTenant

  layout "status_page"

  def show
    @status_data = Current.company.fetch_status_data
    @subscriber = Current.company.subscribers.new
  end

  def not_found
    head :not_found
  end
end
