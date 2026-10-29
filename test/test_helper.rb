ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    fixtures :all

    TEST_ENV = {
      "APP_HOSTS" => "app.statuspage.com,localhost",
      "APP_DOMAIN" => "statuspage.com",
      "SCD_API_URL" => "http://scd.test",
      "SCD_API_TOKEN" => "api_token",
      "SCD_ACCOUNT_UUID" => "acc_1",
      "SCD_UPSTREAM_UUID" => "up_1",
      "PROXY_AUTH_TOKEN" => "proxy_token",
      "SCD_WEBHOOK_TOKEN" => "webhook_token"
    }.freeze

    setup do
      @original_env = ENV.to_h
      ENV.update(TEST_ENV)
    end

    teardown { ENV.replace(@original_env) }
  end
end
