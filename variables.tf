
variable "aws_region" {
  type = string
  default = "us-east-2"
}

variable "aws_availability_zone" {
  type = string
  default = "us-east-2a"
}

variable "postgres_username" {
  type = string
  default= "mc_portfolio_user"
}

variable "postgres_password" {
  type = string
}