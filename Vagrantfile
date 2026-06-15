# -*- mode: ruby -*-
# vi: set ft=ruby :

# Dream Games DevOps Case Study
# K8s Cluster: 1 Master + 2 Worker Nodes
# Requirements: Vagrant, VirtualBox

KUBERNETES_VERSION = "1.28.0"
POD_CIDR           = "10.244.0.0/16"
SERVICE_CIDR       = "10.96.0.0/12"

NODES = [
  { name: "master",  ip: "192.168.56.10", memory: 2048, cpus: 2, role: "master"  },
  { name: "worker1", ip: "192.168.56.11", memory: 2048, cpus: 2, role: "worker"  },
  { name: "worker2", ip: "192.168.56.12", memory: 2048, cpus: 2, role: "worker"  },
]

Vagrant.configure("2") do |config|
  config.vm.box = "bento/ubuntu-22.04"
  config.vm.box_check_update = false

  # Shared SSH key for Ansible
  config.ssh.insert_key = false
  config.ssh.private_key_path = ["~/.vagrant.d/insecure_private_key", "~/.ssh/id_rsa"]
  config.vm.provision "file", source: "~/.ssh/id_rsa.pub", destination: "~/.ssh/authorized_keys"

  NODES.each do |node|
    config.vm.define node[:name] do |vm_config|
      vm_config.vm.hostname = node[:name]
      vm_config.vm.network "private_network", ip: node[:ip]

      vm_config.vm.provider "virtualbox" do |vb|
        vb.name   = "dreamgames-#{node[:name]}"
        vb.memory = node[:memory]
        vb.cpus   = node[:cpus]
        vb.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
        vb.customize ["modifyvm", :id, "--ioapic", "on"]
      end

      # Write /etc/hosts for all nodes
      vm_config.vm.provision "shell", inline: <<-SHELL
        set -e
        cat >> /etc/hosts <<EOF
192.168.56.10 master
192.168.56.11 worker1
192.168.56.12 worker2
EOF
        # Set hostname
        hostnamectl set-hostname #{node[:name]}
      SHELL

      # Run Ansible only after last node is up
      if node[:name] == "worker2"
        vm_config.vm.provision "ansible" do |ansible|
          ansible.playbook       = "ansible/site.yml"
          ansible.inventory_path = "ansible/inventory/hosts.ini"
          ansible.limit          = "all"
          ansible.verbose        = "v"
          ansible.extra_vars = {
            kubernetes_version: KUBERNETES_VERSION,
            pod_cidr:           POD_CIDR,
            service_cidr:       SERVICE_CIDR,
          }
        end
      end
    end
  end
end
