module VCAP::CloudController
  class ServiceBindingAccess < BaseAccess
    def create?(service_binding)
      super ||
        service_binding.app.space.developers.include?(context.user)
    end
    alias :delete? :create?
  end
end
