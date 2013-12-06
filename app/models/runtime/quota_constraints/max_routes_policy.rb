class MaxRoutesPolicy
  def initialize(organization)
    @organization = organization
  end

  def allow_more_routes?(number_of_new_routes)
    return true if @organization.quota_definition.total_routes == -1

    existing_total_routes = OrganizationRoutes.new(@organization).count
    @organization.quota_definition.total_routes >= (existing_total_routes + number_of_new_routes)
  end
end
