# encoding: utf-8
require "spec_helper"

module VCAP::CloudController
  describe Organization, type: :model do
    it_behaves_like "a CloudController model", {
      required_attributes: :name,
      unique_attributes: :name,
      custom_attributes_for_uniqueness_tests: -> { {quota_definition: QuotaDefinition.make} },
      stripped_string_attributes: :name,
      many_to_zero_or_more: {
        users: ->(_) { User.make },
        managers: ->(_) { User.make },
        billing_managers: ->(_) { User.make },
        auditors: ->(_) { User.make },
      },
      one_to_zero_or_more: {
        spaces: ->(_) { Space.make },
        domains: ->(org) { PrivateDomain.make(owning_organization: org) },
        private_domains: ->(org) { PrivateDomain.make(owning_organization: org) }
      }
    }

    describe "validations" do
      context "name" do
        let(:org) { Organization.make }

        it "shoud allow standard ascii characters" do
          org.name = "A -_- word 2!?()\'\"&+."
          expect{
            org.save
          }.to_not raise_error
        end

        it "should allow backslash characters" do
          org.name = "a\\word"
          expect{
            org.save
          }.to_not raise_error
        end

        it "should allow unicode characters" do
          org.name = "防御力¡"
          expect{
            org.save
          }.to_not raise_error
        end

        it "should not allow newline characters" do
          org.name = "one\ntwo"
          expect{
            org.save
          }.to raise_error(Sequel::ValidationFailed)
        end

        it "should not allow escape characters" do
          org.name = "a\e word"
          expect{
            org.save
          }.to raise_error(Sequel::ValidationFailed)
        end
      end
    end

    describe "billing" do
      it "should not be enabled for billing when first created" do
        Organization.make.billing_enabled.should == false
      end

      context "enabling billing" do
        let (:org) do
          o = Organization.make
          2.times do
            space = Space.make(
              :organization => o,
            )
            2.times do
              app = AppFactory.make(
                :space => space,
                :state => "STARTED",
                :package_hash => "abc",
                :package_state => "STAGED",
              )
              AppFactory.make(
                :space => space,
                :state => "STOPPED",
              )
              service_instance = ManagedServiceInstance.make(
                :space => space,
              )
            end
          end
          o
        end

        it "should call OrganizationStartEvent.create_from_org" do
          OrganizationStartEvent.should_receive(:create_from_org)
          org.billing_enabled = true
          org.save(:validate => false)
        end

        it "should emit start events for running apps" do
          ds = AppStartEvent.filter(
            :organization_guid => org.guid,
          )
          org.billing_enabled = true
          org.save(:validate => false)
          ds.count.should == 4
        end

        it "should emit create events for provisioned services" do
          ds = ServiceCreateEvent.filter(
            :organization_guid => org.guid,
          )
          org.billing_enabled = true
          org.save(:validate => false)
          ds.count.should == 4
        end
      end
    end

    context "memory quota" do
      let(:quota) do
        QuotaDefinition.make(:memory_limit => 500)
      end

      it "should return the memory available when no apps are running" do
        org = Organization.make(:quota_definition => quota)

        org.memory_remaining.should == 500
      end

      it "should return the memory remaining when apps are consuming memory" do
        org = Organization.make(:quota_definition => quota)
        space = Space.make(:organization => org)
        AppFactory.make(:space => space,
                         :memory => 200,
                         :instances => 2)
        AppFactory.make(:space => space,
                         :memory => 50,
                         :instances => 1)

        org.memory_remaining.should == 50
      end
    end

    describe "#destroy" do
      let(:org) { Organization.make }
      let(:space) { Space.make(:organization => org) }

      before { org.reload }

      it "destroys all apps" do
        app = AppFactory.make(:space => space)
        expect { org.destroy(savepoint: true) }.to change { App[:id => app.id] }.from(app).to(nil)
      end

      it "destroys all spaces" do
        expect { org.destroy(savepoint: true) }.to change { Space[:id => space.id] }.from(space).to(nil)
      end

      it "destroys all service instances" do
        service_instance = ManagedServiceInstance.make(:space => space)
        expect { org.destroy(savepoint: true) }.to change { ManagedServiceInstance[:id => service_instance.id] }.from(service_instance).to(nil)
      end

      it "destroys all service plan visibilities" do
        service_plan_visibility = ServicePlanVisibility.make(:organization => org)
        expect {
          org.destroy(savepoint: true)
        }.to change {
          ServicePlanVisibility.where(:id => service_plan_visibility.id).any?
        }.to(false)
      end

      it "destroys private domains" do
        domain = PrivateDomain.make(:owning_organization => org)

        expect {
          org.destroy(savepoint: true)
        }.to change {
          Domain[:id => domain.id]
        }.from(domain).to(nil)
      end
    end

    describe "filter deleted apps" do
      let(:org) { Organization.make }
      let(:space) { Space.make(:organization => org) }

      context "when deleted apps exist in the organization" do
        it "should not return the deleted apps" do
          deleted_app = AppFactory.make(:space => space)
          deleted_app.soft_delete

          non_deleted_app = AppFactory.make(:space => space)

          org.apps.should == [non_deleted_app]
        end
      end
    end
  end
end
