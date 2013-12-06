require 'spec_helper'
require 'presenters/message_bus/service_instance_presenter'

describe ServiceInstancePresenter do

  describe "#to_hash" do
    subject { ServiceInstancePresenter.new(service_instance).to_hash }

    context "for a managed service instance" do
      let(:service_instance) do
        VCAP::CloudController::ManagedServiceInstance.make(service_plan: service_plan)
      end

      let(:service_plan) do
        VCAP::CloudController::ServicePlan.make(service: service)
      end

      let(:service) { VCAP::CloudController::Service.make(tags: ["relational", "mysql"]) }

      specify do
        subject.keys.should include(:label)
        subject.keys.should include(:provider)
        subject.keys.should include(:version)
        subject.keys.should include(:vendor)
        subject.keys.should include(:plan)
        subject.keys.should include(:name)
        subject.should have_key(:tags)
      end

      specify do
        subject.fetch(:label).should == [service_instance.service.label, service_instance.service.version].join('-')
        subject.fetch(:provider).should == service_instance.service.provider
        subject.fetch(:version).should == service_instance.service.version
        subject.fetch(:vendor).should == service_instance.service.label
        subject.fetch(:plan).should == service_instance.service_plan.name
        subject.fetch(:name).should == service_instance.name
        subject.fetch(:tags).should == ["relational", "mysql"]
      end


      context 'when the service does not have a version' do
        let(:service) { VCAP::CloudController::Service.make(version: nil) }

        specify { subject.should_not have_key(:version) }

        its([:label]) { should == service.label }
      end
    end

    context "for a provided service instance" do
      let(:service_instance) { VCAP::CloudController::UserProvidedServiceInstance.make }

      specify do
        subject.keys.should == [:label, :name, :tags]
      end

      specify do
        subject.fetch(:label).should == "user-provided"
        subject.fetch(:name).should == service_instance.name
        subject.fetch(:tags).should == []
      end
    end
  end
end
