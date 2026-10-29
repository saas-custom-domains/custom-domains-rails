# Behind SaaS Custom Domains, Host and X-Forwarded-Host carry your
# app's own hostname, which is what your hosting platform routes on.
# The customer's domain arrives separately, in X-Served-For.
#
# If your app needs the customer's domain in request.host (forms that
# pass Rails' CSRF origin check, redirects and _url helpers that stay
# on the customer's domain), this middleware hands it over, but only
# after the upstream's auth token proves the request came through the
# proxy.
class SaasDomainsProxy
  def initialize(app)
    @app = app
  end

  def call(env)
    served_for = env["HTTP_X_SERVED_FOR"]
    return @app.call(env) if served_for.nil?

    unless verify_proxy_token(env["HTTP_X_SAAS_DOMAINS_AUTH_TOKEN"])
      return [ 403, {}, [ "Forbidden" ] ]
    end

    # Rails reads X-Forwarded-Host before Host for request.host and
    # request.base_url. X-Forwarded-Proto is already "https".
    env["HTTP_X_FORWARDED_HOST"] = served_for
    @app.call(env)
  end

  private

  # Constant time, so a wrong guess doesn't reveal how much of it was
  # right. An unset or empty PROXY_AUTH_TOKEN rejects everything.
  def verify_proxy_token(token)
    expected = ENV["PROXY_AUTH_TOKEN"].to_s
    expected.present? &&
      ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected)
  end
end

# After HostAuthorization, which then only sees your own hostnames.
Rails.application.config.middleware.use SaasDomainsProxy
