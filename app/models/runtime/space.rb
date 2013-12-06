module VCAP::CloudController
  class Space < Sequel::Model
    class InvalidDeveloperRelation < InvalidRelation; end
    class InvalidAuditorRelation < InvalidRelation; end
    class InvalidManagerRelation < InvalidRelation; end

    SPACE_NAME_REGEX = /\A[[:alnum:][:punct:][:print:]]+\Z/.freeze

    define_user_group :developers, reciprocal: :spaces, before_add: :validate_developer
    define_user_group :managers, reciprocal: :managed_spaces, before_add: :validate_manager
    define_user_group :auditors, reciprocal: :audited_spaces, before_add: :validate_auditor

    many_to_one :organization
    one_to_many :apps
    one_to_many :events
    one_to_many :all_apps, dataset: -> { App.with_deleted.filter(space: self) }
    one_to_many :service_instances
    one_to_many :managed_service_instances
    one_to_many :routes
    one_to_many :app_events, dataset: -> { AppEvent.filter(app: apps) }
    one_to_many :default_users, class: "VCAP::CloudController::User", key: :default_space_id
    one_to_many :domains, dataset: -> { organization.domains_dataset },
                remover: ->(_) {}, clearer: -> {}, adder: ->(_) {} # noop for bc reasons

    add_association_dependencies default_users: :nullify, all_apps: :destroy, service_instances: :destroy, routes: :destroy, events: :nullify

    default_order_by  :name

    export_attributes :name, :organization_guid

    import_attributes :name, :organization_guid, :developer_guids,
                      :manager_guids, :auditor_guids

    strip_attributes  :name

    def in_organization?(user)
      organization && organization.users.include?(user)
    end

    def validate
      validates_presence :name
      validates_presence :organization
      validates_unique   [:organization_id, :name]
      validates_format SPACE_NAME_REGEX, :name
    end

    def validate_developer(user)
      raise InvalidDeveloperRelation.new(user.guid) unless in_organization?(user)
    end

    def validate_manager(user)
      raise InvalidManagerRelation.new(user.guid) unless in_organization?(user)
    end

    def validate_auditor(user)
      raise InvalidAuditorRelation.new(user.guid) unless in_organization?(user)
    end

    def self.user_visibility_filter(user)
      Sequel.or(
        organization: user.managed_organizations_dataset,
        developers: [user],
        managers: [user],
        auditors: [user]
      )
    end
  end
end
