class CreateCompanies < ActiveRecord::Migration[8.1]
  def change
    create_table :companies do |t|
      t.string :name, null: false
      t.string :slug, null: false, index: { unique: true }
      t.timestamps
    end

    create_table :components do |t|
      t.references :company, null: false, foreign_key: true
      t.string :name, null: false
      t.string :status, null: false, default: "operational"
      t.timestamps
    end

    create_table :subscribers do |t|
      t.references :company, null: false, foreign_key: true
      t.string :email, null: false
      t.timestamps
    end
    add_index :subscribers, [ :company_id, :email ], unique: true
  end
end
