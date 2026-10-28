class AddProviderUuidToCustomDomains < ActiveRecord::Migration[8.1]
  def change
    add_column :custom_domains, :provider_uuid, :string
    add_index :custom_domains, :provider_uuid, unique: true
  end
end
