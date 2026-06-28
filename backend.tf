terraform {
  backend "s3" {
    bucket       = "sctp-ce12-tfstate-bucket"
    key          = "kuankm/Iot/terraform.tfstate"
    region       = "ap-southeast-1"
    use_lockfile = false
  }
}


