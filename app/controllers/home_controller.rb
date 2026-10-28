# The owner dashboard, on your own domain. This example has no login:
# in your app, only show a company's domains to its own users.
class HomeController < ApplicationController
  def index
    @companies = Company.includes(:custom_domains).order(:id)
  end
end
