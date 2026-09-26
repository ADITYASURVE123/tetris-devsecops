terraform {
  required_version = ">= 1.6"
  required_providers {
    aws  = { source = "hashicorp/aws", version = "~> 5.0" }
    http = { source = "hashicorp/http", version = "~> 3.0" }
  }

  backend "s3" {
    bucket  = "tetris-devsecops-tfstate"
    key     = "eks/terraform.tfstate"
    region  = "ap-south-1"
    encrypt = true
    # dynamodb_table = "tetris-tfstate-lock"
  }
}

provider "aws" {
  region = var.aws_region
}

# Fetch official AWS Load Balancer Controller IAM Policy JSON
data "http" "alb_controller_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"
}

# Create IAM Policy resource for AWS Load Balancer Controller
resource "aws_iam_policy" "aws_load_balancer_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  description = "IAM policy for AWS Load Balancer Controller in EKS"
  policy      = data.http.alb_controller_iam_policy.response_body
}

resource "aws_iam_policy" "acm_access" {
  name        = "ACMAccessForLoadBalancerController"
  description = "Allow ACM List and Describe for AWS Load Balancer Controller"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "acm:ListCertificates",
          "acm:DescribeCertificate"
        ]
        Effect   = "Allow"
        Resource = "*"
      }
    ]
  })
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.aws_region}a", "${var.aws_region}b", "${var.aws_region}c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway   = true
  single_nat_gateway   = true # set false for HA NAT in prod
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  eks_managed_node_groups = {
    default = {
      min_size       = 2
      max_size       = 5
      desired_size   = 3
      instance_types = ["c7i-flex.large"]
      capacity_type  = "ON_DEMAND"
      
      # Additional IAM Policies attached directly to worker nodes
      iam_additional_policies = {
        ACMAccess                = aws_iam_policy.acm_access.arn
        AWSLoadBalancerController = aws_iam_policy.aws_load_balancer_controller.arn
      }
    }
  }

  create_kms_key                           = true
  enable_cluster_creator_admin_permissions = true

  tags = {
    Project = "tetris-devsecops"
  }
}