Pre-Requisites
- Three pre-provisioned RHEL 8 nodes with connectivity to the Internet to download packages and images from repositories and registries.
- A user account (auto.svc in my playbook) with sudo (root) privileges provisioned on the ansible control node and all RHEL 8 nodes. Also ensure that the userâ€™s SSH keys are set up to allow execution of the ansible playbook.

Implementation
- Set the POD and SERVICE network CIDR blocks in vars/main.yaml
- Add details for the pre-provisioned RHEL 8 nodes to the files/inventory
- Execute the following command:

      ansible-playbook -i files/inventory control-plane-playbook.yaml
