# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_10_28_000004) do
  create_table "companies", force: :cascade do |t|
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["slug"], name: "index_companies_on_slug", unique: true
  end

  create_table "components", force: :cascade do |t|
    t.integer "company_id", null: false
    t.string "name", null: false
    t.string "status", default: "operational", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_components_on_company_id"
  end

  create_table "custom_domains", force: :cascade do |t|
    t.integer "company_id", null: false
    t.string "host", null: false
    t.string "status", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider_uuid"
    t.string "dns_contact_email"
    t.boolean "https_ready", default: false, null: false
    t.index ["company_id"], name: "index_custom_domains_on_company_id"
    t.index ["host"], name: "index_custom_domains_on_host", unique: true
    t.index ["provider_uuid"], name: "index_custom_domains_on_provider_uuid", unique: true
  end

  create_table "subscribers", force: :cascade do |t|
    t.integer "company_id", null: false
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id", "email"], name: "index_subscribers_on_company_id_and_email", unique: true
    t.index ["company_id"], name: "index_subscribers_on_company_id"
  end

  add_foreign_key "components", "companies"
  add_foreign_key "custom_domains", "companies"
  add_foreign_key "subscribers", "companies"
end
