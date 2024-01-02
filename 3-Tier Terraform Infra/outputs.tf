# Gets the DNS of load balancer
output "lb_dns_name" {
  description = "DNS name of the load balancer"
  value       = "${aws_lb.external-alb.dns_name}"
}