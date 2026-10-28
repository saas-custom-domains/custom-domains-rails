class Component < ApplicationRecord
  belongs_to :company

  enum :status, { operational: "operational", degraded: "degraded", outage: "outage" }
end
