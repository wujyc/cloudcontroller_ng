require 'spec_helper'

module VCAP::CloudController
  describe AppAccess, type: :access do
    subject(:access) { AppAccess.new(double(:context, user: user, roles: roles)) }
    let(:user) { VCAP::CloudController::User.make }
    let(:roles) { double(:roles, :admin? => false, :none? => false, :present? => true) }
    let(:org) { VCAP::CloudController::Organization.make }
    let(:space) { VCAP::CloudController::Space.make(:organization => org) }
    let(:object) { VCAP::CloudController::AppFactory.make(:space => space) }

    it_should_behave_like :admin_full_access

    context 'space developer' do
      before do
        org.add_user(user)
        space.add_developer(user)
      end
      it_behaves_like :full_access
    end

    context 'organization manager' do
      before { org.add_manager(user) }
      it_behaves_like :read_only
    end

    context 'organization user' do
      before { org.add_user(user) }
      it_behaves_like :no_access
    end

    context 'organization auditor' do
      before { org.add_auditor(user) }
      it_behaves_like :no_access
    end

    context 'billing manager' do
      before { org.add_billing_manager(user) }
      it_behaves_like :no_access
    end

    context 'space manager' do
      before do
        org.add_user(user)
        space.add_manager(user)
      end
      it_behaves_like :read_only
    end

    context 'space auditor' do
      before do
        org.add_user(user)
        space.add_auditor(user)
      end
      it_behaves_like :read_only
    end
  end
end
