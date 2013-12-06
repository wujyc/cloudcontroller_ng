require "spec_helper"

module VCAP::CloudController
  describe VCAP::CloudController::InfoController, type: :controller do
    shared_examples "info response" do |expected_status, expect_user|
      it "should return #{expected_status}" do
        last_response.status.should == expected_status
      end

      if expected_status == 200
        it "should return an api_version" do
          hash = Yajl::Parser.parse(last_response.body)
          hash.should have_key("api_version")
        end
      end

      if expect_user
        it "should return a 'user' entry" do
          hash = Yajl::Parser.parse(last_response.body)
          hash.should have_key("user")
        end
      else
        it "should not return a 'user' entry" do
          hash = Yajl::Parser.parse(last_response.body)
          hash.should_not have_key("user")
        end
      end
    end

    describe "GET /v2/info" do
      ControllerHelpers::HTTPS_ENFORCEMENT_SCENARIOS.each do |scenario_vars|
        config_setting = scenario_vars[:config_setting]
        config_desc = config_setting ? "with #{config_setting} enabled" : ""
        protocol = scenario_vars[:protocol]
        expected_status = scenario_vars[:success] ? 200 : 403

        describe "#{config_desc} using #{protocol}" do
          let(:current_user) do
            case scenario_vars[:user]
            when "admin"
              make_user_with_default_space(:admin => true)
            when "user"
              make_user_with_default_space
            end
          end

          let(:headers) do
            headers_for(current_user,
                        :https => scenario_vars[:protocol] == "https",
                        :admin_scope => current_user.admin?)
          end

          before do
            config_override(config_setting => true)
          end

          context "with no authorization header for #{scenario_vars[:user]}" do
            before do
              headers.delete("HTTP_AUTHORIZATION")
              get "/v2/info", {}, headers
            end

            include_examples "info response", 200, false
          end

          context "with invalid authorization header for #{scenario_vars[:user]}" do
            before do
              if headers["HTTP_AUTHORIZATION"]
                headers["HTTP_AUTHORIZATION"] += "EXTRA STUFF"
              end
              get "/v2/info", {}, headers
            end

            include_examples "info response", 200, false
          end

          context "with a valid authorization header for #{scenario_vars[:user]}" do
            before do
              get "/v2/info", {}, headers
            end

            include_examples "info response", expected_status, scenario_vars[:success]
          end
        end
      end

      shared_examples "info endpoint verification" do
        it "should be correct" do
          get "/v2/info"

          hash = Yajl::Parser.parse(last_response.body)
          hash.should have_key(endpoint)
          hash[endpoint].should eq(endpoint_value)
        end
      end

      context "and verify endpoint" do
        describe "authorization" do
          context "with login url in config" do
            include_examples "info endpoint verification" do
              before { config_override(:login => {:url => "login_url"}) }
              let(:endpoint) { "authorization_endpoint" }
              let(:endpoint_value) { "login_url" }
            end
          end

          context "without login url in config" do
            include_examples "info endpoint verification" do
              let(:endpoint) { "authorization_endpoint" }
              let(:endpoint_value) { config[:uaa][:url] }
            end
          end
        end

        describe "logging" do
          context "with loggregator endpoint_url in config" do
            include_examples "info endpoint verification" do
              before { config_override(:loggregator => {:url => "loggregator_url"}) }
              let(:endpoint) { "logging_endpoint" }
              let(:endpoint_value) { "loggregator_url" }
            end
          end

          context "without loggregator endpoint url in config" do
            it "should not have the endpoint in the hash" do
              config[:loggregator].delete(:url)

              get "/v2/info"

              hash = Yajl::Parser.parse(last_response.body)
              hash.should_not have_key("logging_endpoint")
            end
          end
        end
      end
    end
  end
end
