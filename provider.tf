terraform {
  required_version = "~>1.15.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.0"
    }
  }
}


# Configure the AWS CC Provider to use your region
provider "awscc" {
  region = "ap-southeast-1"

}

provider "aws" {
  region = "ap-southeast-1"

}
