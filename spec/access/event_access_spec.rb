require 'spec_helper'

module VCAP::CloudController
  describe EventAccess, type: :access do
    subject(:access) { EventAccess.new(double(:context, user: user, roles: roles)) }
    let(:user) { VCAP::CloudController::User.make }
    let(:roles) { double(:roles, :admin? => false, :none? => false, :present? => true) }
    let(:org) { VCAP::CloudController::Organization.make }
    let(:space) { VCAP::CloudController::Space.make(:organization => org) }
    let!(:object) { VCAP::CloudController::Event.make(:space => space) }

    it_should_behave_like :admin_full_access

    context 'space developer' do
      before do
        org.add_user(user)
        space.add_developer(user)
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

    context 'organization manager (defensive)' do
      before { org.add_manager(user) }
      it_behaves_like :no_access
    end

    context 'organization auditor (defensive)' do
      before { org.add_auditor(user) }
      it_behaves_like :no_access
    end

    context 'space manager (defensive)' do
      before do
        org.add_user(user)
        space.add_manager(user)
      end

      it_behaves_like :no_access
    end

    context 'organization user (defensive)' do
      before { org.add_user(user) }
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

    describe "finding permissions when the related space is deleted" do
      context 'admin' do
        before do
          space.destroy
        end

        it_should_behave_like :admin_full_access
      end

      context 'space developer (before space was deleted)' do
        before do
          org.add_user(user)
          space.add_developer(user)
          space.destroy
        end

        it_behaves_like :no_access
      end

      context 'space auditor' do
        before do
          org.add_user(user)
          space.add_auditor(user)
          space.destroy
        end

        it_behaves_like :no_access
      end

      context 'organization manager (defensive)' do
        before do
          org.add_manager(user)
          space.destroy
        end

        it_behaves_like :no_access
      end

      context 'organization auditor (defensive)' do
        before do
          org.add_auditor(user)
          space.destroy
        end

        it_behaves_like :no_access
      end

      context 'space manager (defensive)' do
        before do
          org.add_user(user)
          space.add_manager(user)
          space.destroy
        end

        it_behaves_like :no_access
      end

      context 'organization user (defensive)' do
        before do
          org.add_user(user)
          space.destroy
        end
        it_behaves_like :no_access
      end

      context 'user in a different organization (defensive)' do
        before do
          different_organization = VCAP::CloudController::Organization.make
          different_organization.add_user(user)
          space.destroy
        end

        it_behaves_like :no_access
      end

      context 'manager in a different organization (defensive)' do
        before do
          different_organization = VCAP::CloudController::Organization.make
          different_organization.add_manager(user)
          space.destroy
        end

        it_behaves_like :no_access
      end

      context 'a user that isnt logged in (defensive)' do
        let(:user) { nil }
        let(:roles) { double(:roles, :admin? => false, :none? => true, :present? => false) }

        before do
          space.destroy
        end

        it_behaves_like :no_access
      end
    end
  end
end
