# The form on a customer's status page. A POST on their domain, so it
# goes through Rails' CSRF check, including the Origin check.
class SubscriptionsController < ApplicationController
  include CustomDomainTenant

  layout "status_page"

  def create
    # The company comes from the domain, never from the form.
    @subscriber = Current.company.subscribers.find_or_initialize_by(
      email: params.expect(subscriber: [ :email ])[:email]
    )

    if @subscriber.save
      redirect_to custom_domain_root_path,
        notice: "Subscribed to #{Current.company.name} updates."
    else
      @status_data = Current.company.fetch_status_data
      render "status_pages/show", status: :unprocessable_content
    end
  end
end
