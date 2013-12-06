module VCAP::CloudController
  class BillingEventsController < RestController::ModelController
    serialization RestController::EntityOnlyObjectSerialization

    # override base enumeration functionality.  This is mainly becase we need
    # better controll over the dataset returned, and we don't have generic
    # functionality for the controller to configure its dataset.
    def enumerate
      raise NotAuthenticated unless user

      unless start_time && end_time
        raise Errors::BillingEventQueryInvalid
      end

      ds = model.user_visible(SecurityContext.current_user, SecurityContext.admin?).filter(timestamp: start_time..end_time)
      RestController::Paginator.render_json(self.class, ds, self.class.path,
      @opts.merge(serialization: serialization))
    end

    def delete(guid)
      do_delete(find_guid_and_validate_access(:delete, guid))
    end

    private

    def start_time
      @start_time ||= parse_date_param("start_date")
    end

    def end_time
      @end_time ||= parse_date_param("end_date")
    end

    def parse_date_param(param)
      str = @params[param]
      Time.parse(str).localtime if str
    rescue
      raise Errors::BillingEventQueryInvalid
    end

    define_messages
    define_routes
  end
end
