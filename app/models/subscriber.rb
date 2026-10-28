class Subscriber < ApplicationRecord
  belongs_to :company

  normalizes :email, with: ->(email) { email.strip.downcase }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP },
    uniqueness: { scope: :company_id }
end
