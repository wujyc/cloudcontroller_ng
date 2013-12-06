require 'spec_helper'

module VCAP::CloudController
  describe DomainAccess, type: :access do
    let(:user) { VCAP::CloudController::User.make }
    let(:roles) { double(:roles, :admin? => false, :none? => false, :present? => true) }
    let(:org) { VCAP::CloudController::Organization.make }
    let(:space) { VCAP::CloudController::Space.make(:organization => org) }

    subject(:access) { DomainAccess.new(double(:context, user: user, roles: roles)) }

    context 'when the domain is a private domain' do
      let(:object) { VCAP::CloudController::PrivateDomain.make(owning_organization: org) }

      it_behaves_like :admin_full_access

      context 'organization manager' do
        before { org.add_manager(user) }
        it_behaves_like :full_access
      end

      context 'organization auditor' do
        before { org.add_auditor(user) }
        it_behaves_like :read_only
      end

      context 'organization user (defensive)' do
        before { org.add_user(user) }
        it_behaves_like :no_access
      end

      context 'organization billing manager (defensive)' do
        before { org.add_billing_manager(user) }
        it_behaves_like :no_access
      end

      context 'user in a different organization (defensive)' do
        before do
          different_organization = VCAP::CloudController::Organization.make
          different_organization.add_user(user)
        end

        it_behaves_like :no_access
      end

      context 'manager in a different organization (defensive)' do
        before do
          different_organization = VCAP::CloudController::Organization.make
          different_organization.add_manager(user)
        end

        it_behaves_like :no_access
      end

      context 'a user that isnt logged in (defensive)' do
        let(:user) { nil }
        let(:roles) { double(:roles, :admin? => false, :none? => true, :present? => false) }
        it_behaves_like :no_access
      end
    end

    context 'when the domain is a shared domain' do
      let(:object) { VCAP::CloudController::SharedDomain.make }

      it_behaves_like :admin_full_access
      it_behaves_like :read_only

      context 'a user that isnt logged in (defensive)' do
        let(:user) { nil }
        let(:roles) { double(:roles, :admin? => false, :none? => true, :present? => false) }
        it_behaves_like :no_access
      end
    end
  end
end
