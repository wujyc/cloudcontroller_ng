module VCAP::CloudController
  class ServicePlanVisibilitiesController < RestController::ModelController
    define_attributes do
      to_one :service_plan
      to_one :organization
    end

    def self.translate_validation_exception(e, attributes)
      associations_errors = e.errors.on([:organization_id, :service_plan_id])
      if associations_errors && associations_errors.include?(:unique)
        Errors::ServicePlanVisibilityAlreadyExists.new(e.errors.full_messages)
      else
        Errors::ServicePlanVisibilityInvalid.new(e.errors.full_messages)
      end
    end

    def delete(guid)
      do_delete(find_guid_and_validate_access(:delete, guid))
    end

    define_messages
    define_routes
  end
end
