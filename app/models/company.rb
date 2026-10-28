class Company < ApplicationRecord
  has_many :custom_domains, dependent: :destroy
  has_many :components, dependent: :destroy
  has_many :subscribers, dependent: :destroy

  # Everything the status page shows.
  def fetch_status_data
    {
      components: components.order(:id),
      all_operational: components.all?(&:operational?)
    }
  end
end
