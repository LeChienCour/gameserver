output "user_pool_id" {
  value = aws_cognito_user_pool.pool.id
}

output "user_pool_client_id" {
  value = aws_cognito_user_pool_client.client.id
}

output "cognito_admin_role_arn" {
    value = aws_iam_role.admin_role.arn
}