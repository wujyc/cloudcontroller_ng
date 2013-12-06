require "spec_helper"

module VCAP::CloudController
  describe VCAP::CloudController::Route, type: :model do
    it_behaves_like "a CloudController model", {
        required_attributes: [:domain, :space, :host],
        db_required_attributes: [:domain_id, :space_id],
        unique_attributes: [[:host, :domain]],
        custom_attributes_for_uniqueness_tests: -> do
          space = Space.make
          domain = PrivateDomain.make(owning_organization: space.organization)
          {space: space, domain: domain}
        end,
        create_attribute: ->(name, route) {
          case name.to_sym
            when :space
              route.space
            when :domain
              PrivateDomain.make(owning_organization: route.space.organization)
            when :host
              Sham.host
          end
        },
        create_attribute_reset: -> { @space = nil },
        many_to_one: {
            domain: {
                delete_ok: true,
                create_for: ->(route) {
                  PrivateDomain.make(
                      owning_organization: route.domain.owning_organization,
                  )
                }
            }
        },
        many_to_zero_or_more: {
            apps: ->(route) { AppFactory.make(:space => route.space) }
        }
    }

    describe "validations" do
      let(:route) { Route.make }

      describe "host" do
        let(:space) { Space.make }
        let(:domain) { PrivateDomain.make(owning_organization: space.organization) }

        it "should not allow . in the host name" do
          route.host = "a.b"
          route.should_not be_valid
        end

        it "should not allow / in the host name" do
          route.host = "a/b"
          route.should_not be_valid
        end

        it "should not allow a nil host" do
          expect {
            Route.make(space: space, domain: domain, host: nil)
          }.to raise_error(Sequel::ValidationFailed)
        end

        it "should allow an empty host" do
          Route.make(:space => space,
                             :domain => domain,
                             :host => "")
        end

        it "should not allow a blank host" do
          expect {
            Route.make(:space => space,
                               :domain => domain,
                               :host => " ")
          }.to raise_error(Sequel::ValidationFailed)
        end
      end

      describe "total allowed routes" do
        let(:space) { Space.make }
        let(:quota_definition) { space.organization.quota_definition }

        subject(:route) { Route.new(space: space) }

        context "on create" do
          context "when there is less than the total allowed routes" do
            before do
              quota_definition.total_routes = 10
              quota_definition.save
            end

            it "has the error on organization" do
              subject.valid?
              expect(subject.errors.on(:organization)).to be_nil
            end
          end

          context "when there is more than the total allowed routes" do
            before do
              quota_definition.total_routes = 0
              quota_definition.save
            end

            it "has the error on organization" do
              subject.valid?
              expect(subject.errors.on(:organization)).to include :total_routes_exceeded
            end
          end
        end

        context "on update" do
          it "should not validate the total routes limit if already existing" do
            expect {
              quota_definition.total_routes = 0
              quota_definition.save
            }.not_to change {
              subject.valid?
            }
          end
        end
      end
    end

    describe "instance methods" do
      let(:space) { Space.make }

      let(:domain) do
        PrivateDomain.make(
          :owning_organization => space.organization
        )
      end

      describe "#fqdn" do
        context "for a non-nil host" do
          it "should return the fqdn for the route" do
            r = Route.make(
              :host => "www",
              :domain => domain,
              :space => space,
            )
            r.fqdn.should == "www.#{domain.name}"
          end
        end

        context "for a nil host" do
          it "should return the fqdn for the route" do
            r = Route.make(
              :host => "",
              :domain => domain,
              :space => space,
            )
            r.fqdn.should == domain.name
          end
        end
      end

      describe "#as_summary_json" do
        it "returns a hash containing the route id, host, and domain details" do
          r = Route.make(
            :host => "www",
            :domain => domain,
            :space => space,
          )
          r.as_summary_json.should == {
            :guid => r.guid,
            :host => r.host,
            :domain => {
              :guid => r.domain.guid,
              :name => r.domain.name
            }
          }
        end
      end
    end

    describe "relations" do
      let(:org) { Organization.make }
      let(:space_a) { Space.make(:organization => org) }
      let(:domain_a) { PrivateDomain.make(:owning_organization => org) }

      let(:space_b) { Space.make(:organization => org) }
      let(:domain_b) { PrivateDomain.make(:owning_organization => org) }

      it "should not associate with apps from a different space" do
        route = Route.make(space: space_b, domain: domain_a)
        app = AppFactory.make(space: space_a)
        expect {
          route.add_app(app)
        }.to raise_error Route::InvalidAppRelation
      end

      it "should not allow creation of a empty host on a shared domain" do
        shared_domain = SharedDomain.make

        expect {
          Route.make(
            host: "",
            space: space_a,
            domain: shared_domain
          )
        }.to raise_error Sequel::ValidationFailed
      end
    end

    describe "#remove" do
      let!(:route) { Route.make }
      let!(:app_1) do
        AppFactory.make({
          :space => route.space,
          :route_guids => [route.guid],
        }.merge(app_attributes))
      end

      context "when app is running and staged" do
        let(:app_attributes) { {:state => "STARTED", :package_hash => "abc", :package_state => "STAGED"} }

        it "notifies DEAs of route change for running apps" do
          VCAP::CloudController::DeaClient.should_receive(:update_uris).with(app_1)
          Route[:guid => route.guid].destroy(savepoint: true)
        end
      end

      context "when app is not staged and running" do
        let(:app_attributes) { {:state => "STARTED", :package_hash => "abc", :package_state => "FAILED", :droplet_hash => nil} }

        it "does not notify DEAs of route change for apps that are not started" do
          AppFactory.make(
              :space => route.space, :state => "STOPPED",
              :route_guids => [route.guid], :droplet_hash => nil, :package_state => "PENDING")

          VCAP::CloudController::DeaClient.should_not_receive(:update_uris)

          route.destroy(savepoint: true)
        end
      end

      context "when app is staged but not running" do
        let(:app_attributes) { {:state => "STOPPED", :package_state => "STAGED"} }

        it "does not notify DEAs of route change for apps that are not staged" do
          AppFactory.make(:space => route.space, :package_state => "FAILED", :route_guids => [route.guid])
          VCAP::CloudController::DeaClient.should_not_receive(:update_uris)
          Route[:guid => route.guid].destroy(savepoint: true)
        end
      end
    end
  end
end
