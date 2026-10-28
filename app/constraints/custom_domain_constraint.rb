class CustomDomainConstraint
  def self.matches?(request)
    !CustomDomain.app_host?(CustomDomain.host_from(request))
  end
end
