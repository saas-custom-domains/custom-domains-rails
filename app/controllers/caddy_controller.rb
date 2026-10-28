# Caddy calls this before it issues a certificate on demand
# (DOMAINS_PROVIDER=caddy). 200 = go ahead, anything else = refuse.
class CaddyController < ActionController::API
  def ask
    # Caddy sends ?domain=, kamal-proxy sends ?host=
    host = (params[:domain] || params[:host]).to_s.downcase

    if CustomDomain.active.exists?(host: host)
      head :ok
    else
      head :not_found
    end
  end
end
