output "k3s_public_ip" {
  value = oci_core_instance.k3s.public_ip
}

output "ssh_cmd" {
  value = "ssh opc@${oci_core_instance.k3s.public_ip}"
}

output "kubeconfig_cmd" {
  value = "scp opc@${oci_core_instance.k3s.public_ip}:/etc/rancher/k3s/k3s.yaml ~/.kube/nestora-oci.yaml"
}
