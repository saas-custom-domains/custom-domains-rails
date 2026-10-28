class CreateCustomDomains < ActiveRecord::Migration[8.1]
  def change
    create_table :custom_domains do |t|
      t.references :company, null: false, foreign_key: true
      t.string :host, null: false
      t.string :status, null: false, default: "pending"
      t.timestamps
    end

    add_index :custom_domains, :host, unique: true
  end
end
