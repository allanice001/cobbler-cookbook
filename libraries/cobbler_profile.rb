#
# Cookbook Name:: cobblerd
# Library:: profile
#
# Copyright (C) 2014 Bloomberg Finance L.P.
#
class Chef
  class Resource::CobblerProfile < Resource
    include Poise

    actions(:import)
    actions(:delete)

    attribute(:name, kind_of: String)
    attribute(:distro, kind_of: String, required: true)
    attribute(:kickstart, kind_of: String, default: lazy { source_default })
    attribute(:kickstart_meta, kind_of: Hash)
    attribute(:kernel_options, kind_of: Hash, default: { 'interface' => 'auto' }
    attribute(:kernel_options_postinstall, kind_of: Hash)

    private
    def source_default
      return "#{name}.preseed" if ["ubuntu", "debian"].include?(breed)
      return "#{name}.ks" if breed == "redhat"
      Chef::Application.fatal!("Unsupported breed (#{breed})!")
    end

    private
    def breed
      @breed ||= determine_distro_breed
    end

    private
    def determine_distro_breed
        # return breed (e.g. "redhat", "debian", "ubuntu" or "suse")

        # Acquire Cobbler output like:
        # Name                           : centos-6-x86_64
        # Architecture                   : x86_64
        # Breed                          : redhat
        # [...]
        raw_distro_info = `cobbler distro report --name='#{new_resource.distro}'`
        raw_breed_line = raw_distro_info.each_line.select { |l| l if l.chomp.start_with?("Breed") }
        return raw_breed_line.first.split(" : ")[1].chomp
    end
  end

  class Provider::CobblerProfile < Provider
    include Poise

    # Import the specified profile into cobbler
    def action_delete
      converge_by("deleting #{new_resource.name} into cobbler") do
        notifying_block do
          cobbler_profile_delete
        end
      end
    end

    # Import the specified profile into cobbler
    def action_import
      converge_by("importing #{new_resource.name} into cobbler") do
        notifying_block do
          cobbler_profile_add
        end
      end
    end

    private

    def cobbler_profile_add
      template "/var/lib/cobbler/kickstart/#{new_resource.kickstart}" do
        source "#{new_resource.kickstart}.erb"
        action :create_if_missing
      end

      bash 'cobbler-profile-add' do
        code (<<-CODE)
          cobbler profile add --name='#{new_resource.name}' \
          --distro='#{new_resource.distro}' \
          --kickstart='/var/lib/cobbler/kickstart/#{new_resource.kickstart}' \
          #{"--kopts='#{new_resource.kernel_options.map{ |k,v| "#{k}=#{v}" }.join(" ")}'" if new_resource.kernel_options} \
          #{"--kopts-post='#{new_resource.kernel_options_postinstall.map{ |k,v| "#{k}=#{v}" }.join(" ")}'" if new_resource.kernel_options_postinstall} \
          #{"--ksmeta='#{new_resource.kernel_options_postinstall.map{ |k,v| "#{k}=#{v}" }.join(" ")}'" } \
          && \
          cobbler sync
        CODE
        not_if "cobbler profile report --name '#{new_resource.profile}'"
      end
    end

    def cobbler_profile_delete
      bash 'cobbler-profile-add' do
        code "cobbler profile remove --name='#{new_resource.name}' && cobbler sync"
        only_if "cobbler profile report --name '#{new_resource.name}'"
      end

      file "/var/lib/cobbler/kickstart/#{new_resource.kickstart}" do
        action :delete
        only_if { ::File.exist? "/var/lib/cobbler/kickstart/#{new_resource.kickstart}" }
      end
    end

  end
end
