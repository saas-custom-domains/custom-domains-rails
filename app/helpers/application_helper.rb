module ApplicationHelper
  def domain_status_label(domain)
    if domain.live? then "Live"
    elsif domain.active? then "DNS OK, waiting for HTTPS"
    else "Waiting for DNS"
    end
  end
end
