# This example has no login. In your app, scope these to the signed-in
# user's company.
class CustomDomainsController < ApplicationController
  before_action :set_custom_domain, only: %i[destroy check]

  def create
    company = Company.find(params[:company_id])
    domain = company.custom_domains.new(params.expect(custom_domain: %i[host dns_contact_email]))

    if domain.save
      redirect_to root_path, notice: "Added #{domain.host}. Point its DNS at us next."
    else
      redirect_to root_path, alert: domain.errors.full_messages.to_sentence
    end
  end

  def check
    @custom_domain.check_dns!
    redirect_to root_path
  rescue SaasDomains::Error, Resolv::ResolvError => e
    Rails.logger.warn(e.message)
    redirect_to root_path, alert: "Could not check #{@custom_domain.host}. Try again."
  end

  def destroy
    RemoveCustomDomainJob.perform_later(@custom_domain)
    redirect_to root_path, notice: "Removing #{@custom_domain.host}."
  end

  private

  def set_custom_domain
    @custom_domain = CustomDomain.find(params[:id])
  end
end
