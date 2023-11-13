output "portfolio_dns" {
  description = "The DNS name of the portfolio load balancer"
  value       = aws_lb.portfolio_nlb.dns_name
}
