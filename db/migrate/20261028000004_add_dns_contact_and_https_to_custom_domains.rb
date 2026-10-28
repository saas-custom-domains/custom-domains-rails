class AddDnsContactAndHttpsToCustomDomains < ActiveRecord::Migration[8.1]
  def change
    # Who gets the DNS instructions email for this domain (optional).
    add_column :custom_domains, :dns_contact_email, :string
    # Set by the tls_certificate_issued webhook.
    add_column :custom_domains, :https_ready, :boolean, null: false, default: false
  end
end
