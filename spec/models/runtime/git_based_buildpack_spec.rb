require "spec_helper"

module VCAP::CloudController
  describe GitBasedBuildpack do
    subject { GitBasedBuildpack.new(url) }

    let(:url) { "http://foo_bar/baz" }

    its(:url) { should == url }
    its(:to_json) { should == '"http://foo_bar/baz"' }

    it "has the correct staging message" do
      expect(subject.staging_message).to include(buildpack_git_url: url)
    end

    it "has the deprecated staging message" do
      expect(subject.staging_message).to include(buildpack: url)
    end

    describe "validations" do
      context "with bogus characters at the start of the URI" do
        let(:url) { "\r\nhttp://foo_bar/baz" }

        its(:to_json) { should == '"\r\nhttp://foo_bar/baz"' }

        it "should not be valid" do
          expect(subject).not_to be_valid
          expect(subject.errors).to include "#{url} is not valid public git url or a known buildpack name"
        end
      end

      context "with bogus characters at the end of the URI" do
        let(:url) { "http://foo_bar/baz\r\n\0" }

        its(:to_json) { should == '"http://foo_bar/baz\r\n\u0000"' }

        it "should not be valid" do
          expect(subject).not_to be_valid
          expect(subject.errors).to include "#{url} is not valid public git url or a known buildpack name"
        end
      end
    end
  end
end
