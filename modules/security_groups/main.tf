resource "aws_security_group" "game_server" {
  name        = "${var.security_group_name}-${var.stage}"
  description = "Security group for game server - ${var.stage}"
  vpc_id      = var.vpc_id

  # Minecraft server port
  ingress {
    from_port   = var.game_port
    to_port     = var.game_port
    protocol    = var.game_protocol
    cidr_blocks = var.allowed_game_ips
  }

  # WebSocket port
  ingress {
    from_port   = var.websocket_port
    to_port     = var.websocket_port
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.ssh_cidr]
  }

  # Allow HTTPS outbound for SSM
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow HTTPS for SSM and updates"
  }

  # Allow all outbound traffic to VPC endpoints
  egress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.selected.cidr_block]
    description = "Allow HTTPS to VPC endpoints"
  }

  # Allow inbound traffic from VPC endpoints
  ingress {
    from_port       = 443
    to_port         = 443
    protocol        = "tcp"
    security_groups = [var.vpc_endpoints_security_group_id]
    description     = "Allow HTTPS from VPC endpoints"
  }

  # Allow outbound internet access for updates and downloads
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow internet access for updates"
  }

  tags = {
    Name        = "${var.security_group_name}-${var.stage}"
    Stage       = var.stage
    Environment = var.environment
  }
}

# Get VPC data
data "aws_vpc" "selected" {
  id = var.vpc_id
}