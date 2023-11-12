
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
  sensitive = true
}

variable "postgres_database_name" {
  type = string
  default = "mc_portfolio_db"
}
 
variable "mux_token_id" {
  type = string
}

variable "mux_token_secret" {
  type = string
  sensitive = true
}

