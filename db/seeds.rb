# Two tenants with a status page each. Idempotent, so `db:prepare` can
# run it on every boot.
{
  "acme" => [ "Acme Cloud", { "API" => "operational", "Dashboard" => "operational", "Webhooks" => "degraded" } ],
  "globex" => [ "Globex Payments", { "Checkout" => "operational", "Payouts" => "operational" } ]
}.each do |slug, (name, components)|
  company = Company.find_or_create_by!(slug: slug) { |c| c.name = name }
  components.each do |component, status|
    company.components.find_or_create_by!(name: component) { |c| c.status = status }
  end
end
