output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnets_ids" {
  description = "List of IDs of public subnets"
  value       = aws_subnet.public[*].id
}

output "vpc_endpoint_execute_api_id" {
  description = "ID of the API Gateway VPC Endpoint"
  value       = aws_vpc_endpoint.execute_api.id
}

output "vpc_endpoint_execute_api_dns" {
  description = "DNS entries for the API Gateway VPC Endpoint"
  value       = aws_vpc_endpoint.execute_api.dns_entry
}

output "vpc_endpoints_security_group_id" {
  description = "ID of the security group for VPC endpoints"
  value       = aws_security_group.vpc_endpoints.id
}

output "ssm_endpoints" {
  description = "Map of SSM VPC Endpoint IDs"
  value = {
    ssm         = aws_vpc_endpoint.ssm.id
    ssmmessages = aws_vpc_endpoint.ssmmessages.id
    ec2messages = aws_vpc_endpoint.ec2messages.id
  }
}

output "ssm_endpoint_dns_entries" {
  description = "Map of SSM VPC Endpoint DNS entries"
  value = {
    ssm         = aws_vpc_endpoint.ssm.dns_entry
    ssmmessages = aws_vpc_endpoint.ssmmessages.dns_entry
    ec2messages = aws_vpc_endpoint.ec2messages.dns_entry
  }
}