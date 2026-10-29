# Custom domains in Ruby on Rails

An example Rails 8.1 app where each customer connects their own domain. It's a small status page product: every company gets a status page, and it can serve that page on `status.theircompany.com` instead of a URL on your domain.

It goes with the guide [How to Add Custom Domains to a Ruby on Rails App](https://saascustomdomains.com/blog/posts/best-guide-custom-domains-ruby-on-rails).

What's in it:

- A `CustomDomain` model with a normalized, unique `host`, and a route constraint plus a controller concern that find the company from the request's hostname. Unknown and pending domains get a 404.
- Requests from the [SaaS Custom Domains](https://saascustomdomains.com) proxy are accepted only with the upstream's auth token, so nobody can claim a customer's domain by sending `X-Served-For` themselves.
- A subscribe form on each status page that passes Rails' CSRF check behind the proxy (see [Forms, redirects and links behind the proxy](#forms-redirects-and-links-behind-the-proxy)).
- `config.hosts` allows your own hostnames and every domain in the database, so `HostAuthorization` stays on.
- A dashboard to add a domain, check its DNS and remove it. Background jobs (Solid Queue) talk to the API, and webhooks update the status.
- HTTPS for every customer domain through SaaS Custom Domains, with a local mock of its API and proxy for development and tests.

## Run it in 2 minutes

You need Docker.

```bash
git clone https://github.com/saas-custom-domains/custom-domains-rails
cd custom-domains-rails
docker compose up --build
```

1. Open http://localhost:3000 and add `acme.localhost` to Acme Cloud.
2. Within a few seconds the status changes to **Live**: a background job registered the domain with the mock API, the mock "found" the DNS records and sent webhooks.
3. Open http://acme.localhost. The request goes through the mock proxy on port 80, exactly like a real customer domain goes through SaaS Custom Domains, and you see Acme's status page.

`*.localhost` always resolves to your own machine in Chrome, Firefox, Safari and curl, so there's nothing to add to `/etc/hosts`.

The mock is [scd-mock](https://github.com/saas-custom-domains/scd-mock): a local copy of the SaaS Custom Domains API and proxy, so you can try everything without an account.

Try the subscribe form on that page too. In production the proxy sends `X-Forwarded-Proto: https`; the mock has no TLS, so `compose.yaml` sets `SCD_MOCK_FORWARDED_PROTO=http` to match the `http://` your browser uses, or Rails' CSRF origin check would reject the form.

### Run Rails outside Docker

Run the mock in Docker and Rails on your machine:

```bash
docker run --rm -p 4010:4010 -p 80:4080 \
  -e SCD_MOCK_UPSTREAM_HOST=host.docker.internal \
  -e SCD_MOCK_UPSTREAM_PORT=3000 \
  -e SCD_MOCK_WEBHOOK_URL=http://host.docker.internal:3000/webhooks/saas_domains \
  -e SCD_MOCK_FORWARDED_PROTO=http \
  ghcr.io/saas-custom-domains/scd-mock:latest

bundle install
cp .env.example .env
bin/rails db:prepare
bin/rails server
```

The mock reaches your machine as `host.docker.internal`, which is why `.env.example` lists it in `APP_HOSTS`; without it, Rails answers with "Blocked hosts: host.docker.internal:3000". Keep the proxy on port 80: `X-Served-For` carries no port, so a form on `http://acme.localhost:4080` would fail the CSRF origin check.

## How it works

```
Browser ── acme.com ──▶ SaaS Custom Domains ──▶ your Rails app
                        (TLS certificate,       Host: app.statuspage.com
                         proxy)                 X-Served-For: acme.com
                                                X-SaaS-Domains-Auth-Token: …
```

| File | What it does |
| --- | --- |
| `config/initializers/saas_domains_proxy.rb` | Checks the proxy token, then gives Rails the customer's domain |
| `app/models/custom_domain.rb` | Host normalization, reserved domains, `host_from`, DNS check |
| `app/constraints/custom_domain_constraint.rb` | Sends customer domains to the status page routes |
| `app/controllers/concerns/custom_domain_tenant.rb` | Finds the company for the domain, or 404 |
| `app/controllers/status_pages_controller.rb`, `subscriptions_controller.rb` | The customer's status page and its form |
| `app/services/saas_domains.rb` | API client for SaaS Custom Domains (`Net::HTTP`) |
| `app/jobs/register_custom_domain_job.rb`, `remove_custom_domain_job.rb` | Add and remove domains on the proxy |
| `app/controllers/saas_domains_webhooks_controller.rb` | Webhook endpoint |
| `config/environments/production.rb` | `config.hosts` and `host_authorization` |

## Rails errors you'll see, and the fixes

### "Blocked hosts: status.example.com"

`ActionDispatch::HostAuthorization` answers 403 for any host that isn't in `config.hosts`. In development the page says:

```
Blocked hosts: status.example.com:3000

To allow requests to these hosts, make sure they are valid hostnames (containing only numbers, letters, dashes and dots), then add the following to your environment configuration:

  config.hosts << "status.example.com:3000"
```

In production the response is an empty 403, with `[ActionDispatch::HostAuthorization::DefaultResponseApp] Blocked hosts: status.example.com` in the log. Development allows `localhost`, `*.localhost`, `*.test` and IP addresses (plus anything in `RAILS_DEVELOPMENT_HOSTS`). Production checks nothing until you set `config.hosts`, which the generated `production.rb` suggests.

The middleware checks both `Host` and the last value of `X-Forwarded-Host`, and its lambdas get the value as sent, port included. This app allows its own hostnames and every domain in the database:

```ruby
config.hosts = [
  *ENV.fetch("APP_HOSTS", "").split(",").map(&:strip),
  ->(host) { CustomDomain.exists?(host: host.split(":").first.downcase) }
]
config.host_authorization = {
  exclude: ->(request) { request.path == "/up" }
}
```

`/up` is excluded because load balancers call it by IP address. Behind SaaS Custom Domains, `Host` and `X-Forwarded-Host` are your own hostname, so `APP_HOSTS` covers proxied requests; the lambda is for local testing on `*.localhost` and for the case where support sends the customer's domain in `X-Forwarded-Host`. List every internal hostname your platform uses to reach the app in `APP_HOSTS` too: webhooks from the mock arrive as `Host: app:3000`.

### Forms, redirects and links behind the proxy

SaaS Custom Domains forwards requests with your app's own hostname in `Host` and `X-Forwarded-Host`, so your hosting platform routes them like any other request, and sends the customer's domain in `X-Served-For`. If your app needs the customer's domain in `request.host`, give it that. Rails uses `request.host` for three things here:

- The CSRF check compares the browser's `Origin` with `request.base_url`. Without the customer's domain, a form on `status.acme.com` fails with `ActionController::InvalidAuthenticityToken (HTTP Origin header (https://status.acme.com) didn't match request.base_url (https://app.statuspage.com))`.
- `redirect_to` and `_url` helpers build absolute URLs from it, so the redirect after a form post would send the visitor to `https://app.statuspage.com/`.
- A session store with `domain: :all` computes the cookie domain from it.

`SaasDomainsProxy`, a small Rack middleware, checks the auth token and then sets `X-Forwarded-Host` to the value of `X-Served-For`. Rails reads `X-Forwarded-Host` first, so `request.host` is the customer's domain from there on. It runs after `HostAuthorization`, which therefore only sees your own hostnames on proxied requests. (Support can also put the customer's domain in `X-Forwarded-Host` for your account; the middleware works either way.)

Leave the session cookie's `domain` unset. The default is a host-only cookie, which is what you want on a domain you don't own: with `domain: :all`, Rails would set it for the customer's whole domain (`domain=acme.com`).

## Use it with your SaaS Custom Domains account

1. [Create an API token](https://app.saascustomdomains.com/api_tokens) and an upstream pointing at your deployed app (`SaasDomains.new.create_upstream("app.statuspage.com")` from the console does it).
2. Set the environment variables from `.env.example`: `SCD_API_TOKEN`, `SCD_ACCOUNT_UUID`, `SCD_UPSTREAM_UUID`, `PROXY_AUTH_TOKEN` (the upstream's auth token), `SCD_WEBHOOK_TOKEN` (from the webhook you create in the dashboard, pointing at `/webhooks/saas_domains`), `APP_HOSTS` and `APP_DOMAIN`.
3. Remove `SCD_API_URL` so the client talks to the real API.
4. Run the jobs: `SOLID_QUEUE_IN_PUMA=true` on a single server, or `bin/jobs` next to Puma.

Your customers point a CNAME at `in.saascustomdomains.com` (or A records at our two static IPs for a root domain). See the [docs](https://docs.saascustomdomains.com).

## Tests

```bash
bin/rails test                 # unit and integration tests
docker compose up -d --build --wait
npm install
npx playwright install chromium
npm run test:e2e               # end to end, through the mock proxy
```

The end-to-end tests use `*.test` domains and send the browser's requests for them to the mock proxy, so nothing depends on DNS or on port 80. To run a second stack side by side, set `APP_PORT`, `SCD_MOCK_API_PORT` and `SCD_MOCK_PROXY_PORT` for both `docker compose` and `npm run test:e2e`.

CI runs both on every push and once a week, so a new Rails release that breaks something shows up here first.

## Tested with

| | Version |
| --- | --- |
| Rails | 8.1.4 |
| Ruby | 4.0.9 (Docker, CI), 3.4.1 |
| Puma | 8.0.2 |
| Solid Queue | 1.7.0 |
| SQLite (`sqlite3` gem) | 2.10.2 |

Last checked: 2026-10-28.

## Not production-ready on purpose

There's no login. In your app, scope the dashboard and every domain action to the signed-in user's company. SQLite keeps the example small; use your own database. Domains are registered in a background job, so a domain the API rejects (for example `host_taken`) disappears from the dashboard without a message; show that to your users.

## License

MIT
