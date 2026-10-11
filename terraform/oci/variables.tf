variable "tenancy_ocid" { type = string }
variable "user_ocid" { type = string }
variable "fingerprint" { type = string }
variable "private_key_path" { type = string }
variable "region" {
  type    = string
  default = "eu-frankfurt-1" # changer si ton tenancy est ailleurs
}
variable "compartment_ocid" { type = string }
variable "ssh_public_key" { type = string }
variable "availability_domain" {
  type    = string
  default = "" # vide = auto (1er AD dispo)
}
variable "ocpus" {
  type    = number
  default = 2 # Always Free Ampere : 4 OCPU max au total
}
variable "memory_gb" {
  type    = number
  default = 12 # Always Free Ampere : 24 Go max au total
}
variable "ssh_cidr" {
  type    = string
  default = "0.0.0.0/0" # restreins à ton IP en prod : "x.x.x.x/32"
}
