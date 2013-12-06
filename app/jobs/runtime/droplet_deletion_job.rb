
class DropletDeletionJob < Struct.new(:new_droplet_key, :old_droplet_key)
  def perform
    blobstore = CloudController::DependencyLocator.instance.droplet_blobstore
    blobstore.delete(new_droplet_key)
    begin
      blobstore.delete(old_droplet_key)
    rescue Errno::EISDIR
      # The new droplets are with a path which is under the old droplet path
      # This means that sometimes, if there are multiple versions of a droplet,
      # the directory will still exist after we delete the droplet.
      # We don't care for now, but we don't want the errors.
    end
  end

  def max_attempts
    3
  end
end