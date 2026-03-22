output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}
output "alb_public_url" {
  value = aws_lb.web_alb.dns_name

}
output "bastion_public_ip" {
  value = aws_instance.bastion.public_ip
}

