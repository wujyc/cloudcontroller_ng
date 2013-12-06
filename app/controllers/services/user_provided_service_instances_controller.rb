require 'cloud_controller/rest_controller'

module VCAP::CloudController
  class UserProvidedServiceInstancesController < RestController::ModelController
    define_attributes do
      attribute :name, String
      attribute :credentials, Hash, :default => {}
      attribute :syslog_drain_url, String, :default => ""

      to_one :space
      to_many :service_bindings
    end

    def self.translate_validation_exception(e, attributes)
      space_and_name_errors = e.errors.on([:space_id, :name])
      if space_and_name_errors && space_and_name_errors.include?(:unique)
        Errors::ServiceInstanceNameTaken.new(attributes["name"])
      else
        Errors::ServiceInstanceInvalid.new(e.errors.full_messages)
      end
    end

    def delete(guid)
      do_delete(find_guid_and_validate_access(:delete, guid))
    end

    define_messages
    define_routes
  end
end
