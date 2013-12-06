require 'spec_helper'
require 'rspec_api_documentation/dsl'

resource "Private Domains", :type => :api do
  let(:admin_auth_header) { headers_for(admin_user, :admin_scope => true)["HTTP_AUTHORIZATION"] }
  let(:guid) { VCAP::CloudController::PrivateDomain.first.guid }
  let!(:domains) { 3.times { VCAP::CloudController::PrivateDomain.make } }

  authenticated_request

  field :guid, "The guid of the domain.", required: false
  field :name, "The name of the domain.", required: true, example_values: ["example.com", "foo.example.com"]
  field :owning_organization_guid, "The organization that owns the domain. If not specified, the domain is shared.", required: false

  standard_model_list :private_domain, VCAP::CloudController::PrivateDomainsController
  standard_model_get :private_domain
  standard_model_delete :private_domain

  post "/v2/private_domains" do
    example "Create a domain owned by the given organization" do
      org_guid = VCAP::CloudController::Organization.make.guid
      payload = Yajl::Encoder.encode(
        name: "exmaple.com",
        owning_organization_guid: org_guid
      )

      client.post "/v2/private_domains", payload, headers

      expect(status).to eq 201
      standard_entity_response parsed_response, :domain,
                               name: "exmaple.com",
                               owning_organization_guid: org_guid
    end
  end
end
