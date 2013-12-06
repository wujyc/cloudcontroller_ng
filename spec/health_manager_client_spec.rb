require "spec_helper"

module VCAP::CloudController
  describe VCAP::CloudController::HealthManagerClient do
    let(:app) { AppFactory.make }
    let(:apps) { [AppFactory.make, AppFactory.make, AppFactory.make] }
    let(:message_bus) { CfMessageBus::MockMessageBus.new }

    subject(:health_manager_client) { VCAP::CloudController::HealthManagerClient.new(message_bus) }

    describe "find_flapping_indices" do
      it "should use specified message options" do
        resp = {
          "indices" => [
            { "index" => 1, "since" => 1 },
            { "index" => 2, "since" => 1 },
          ]
        }

        message_bus.respond_to_synchronous_request("healthmanager.status", [resp])
        health_manager_client.find_flapping_indices(app).should == resp["indices"]
      end
    end

    describe "find_crashes" do
      it "should return crashed instances" do
        resp = {
          "instances" => [
            {"instance" => "instance_1", "since" => 1},
            {"instance" => "instance_2", "since" => 1},
          ]
        }

        message_bus.respond_to_synchronous_request("healthmanager.status", [resp])
        health_manager_client.find_crashes(app).should == resp["instances"]
      end
    end

    describe "healthy_instances" do
      before { message_bus.respond_to_synchronous_request("healthmanager.health", resp) }

      context "single app" do
        let(:resp) do
          [{
             "droplet" => app.guid,
             "version" => app.version,
             "healthy" => 3
           }]
        end

        it "requests the health correctly" do
          health_manager_client.healthy_instances(app)
          expect(message_bus).to have_requested_synchronous_messages("healthmanager.health", {droplets: [droplet: app.guid, version: app.version]}, {:result_count => 1, :timeout => 1})
        end

        it "should return num healthy instances" do
          expect(health_manager_client.healthy_instances(app)).to eq 3
        end

        it "should return the app guid correctly" do
          expect(health_manager_client.healthy_instances([app])).to eq(app.guid => 3)
        end
      end

      context "multiple apps" do
        let(:resp) do
          apps.map do |app|
            {
              "droplet" => app.guid,
              "version" => app.version,
              "healthy" => 3,
            }
          end
        end

        it "should return num healthy instances for each app" do
          expected = apps.inject({}) do |expected, app|
            expected[app.guid] = 3
            expected
          end
          expect(health_manager_client.healthy_instances(apps)).to eq expected
        end
      end
    end
  end
end
