# Game Server with Voice Chat Infrastructure

This repository contains Terraform configurations for deploying a game server with real-time voice chat capabilities using AWS services.

## Architecture Overview

The infrastructure consists of the following components:

### Core Components
- **EC2 Game Server**: Central hub for game and voice chat functionality
  - Handles WebSocket connections for real-time communication
  - Manages voice chat channels and audio routing
  - Runs the game server application

### Authentication & Security
- **Amazon Cognito**: User authentication and management
  - User pools for player accounts
  - Secure token-based authentication
  - Integration with the game server

### Real-time Communication
- **WebSocket API Gateway**: Manages real-time connections
  - Handles WebSocket connections (`$connect`)
  - Processes messages (`$default`)
  - Manages disconnections (`$disconnect`)
  - Routes traffic to the EC2 instance

### Network & Security
- **VPC**: Isolated network environment
  - Public subnets for internet-facing resources
  - Security groups for access control
  - Network ACLs for additional security

### Configuration Management
- **Systems Manager Parameter Store**: Secure configuration storage
  - Cognito configuration
  - WebSocket endpoints
  - Environment variables

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform v1.0.0 or later
- Node.js and npm (for local development)

## Infrastructure Components

### VPC Module
- Custom VPC with public subnets
- Internet Gateway for public access
- Route tables for network routing

### Security Groups
- Game server port (default: 25565)
- WebSocket port (default: 8080)
- SSH access (port 22)
- Outbound internet access

### EC2 Instance
- Amazon Linux 2 or Ubuntu AMI
- Python runtime
- IAM role with necessary permissions
- User data script for application setup

### Cognito
- User pool for player accounts
- App client for application integration
- Admin role for management

### WebSocket API
- Custom domain (optional)
- Stage for deployment
- Integration with EC2 instance
- CloudWatch logging

## Deployment

1. **Initialize Terraform**:
   ```bash
   terraform init
   ```

2. **Configure Variables**:
   - Copy `terraform.tfvars.example` to `terraform.tfvars`
   - Update the variables with your values

3. **Plan Deployment**:
   ```bash
   terraform plan
   ```

4. **Apply Configuration**:
   ```bash
   terraform apply
   ```

## Configuration

### Required Variables
- `ami_id`: AMI ID for the EC2 instance
- `instance_type`: EC2 instance type
- `vpc_cidr`: CIDR block for VPC
- `public_subnets_cidr`: CIDR blocks for public subnets
- `availability_zones`: AWS availability zones

### Optional Variables
- `game_port`: Game server port (default: 25565)
- `websocket_port`: WebSocket server port (default: 8080)
- `ssh_cidr`: SSH access CIDR (default: 0.0.0.0/0)
- `environment`: Environment name (default: dev)
- `project_name`: Project name (default: game-server)

## Security Considerations

1. **Network Security**
   - Security groups restrict access to necessary ports
   - VPC provides network isolation
   - SSH access should be restricted to specific IPs

2. **Authentication**
   - Cognito provides secure user authentication
   - IAM roles follow principle of least privilege
   - WebSocket connections require valid tokens

3. **Data Protection**
   - All sensitive data stored in SSM Parameter Store
   - WebSocket connections use WSS (secure WebSocket)
   - Cognito tokens for secure communication

## Monitoring and Logging

- CloudWatch Logs for WebSocket API
- CloudWatch Metrics for EC2 instance
- CloudWatch Alarms for critical metrics
- Log retention period: 30 days (configurable)

## Maintenance

### Updating the Infrastructure
1. Modify the Terraform configuration
2. Run `terraform plan` to review changes
3. Apply changes with `terraform apply`

### Scaling
- EC2 instance type can be modified
- WebSocket API can be configured for auto-scaling
- Security groups can be updated for new requirements

## Troubleshooting

### Common Issues
1. **WebSocket Connection Failures**
   - Check security group rules
   - Verify WebSocket API configuration
   - Check EC2 instance status

2. **Authentication Issues**
   - Verify Cognito configuration
   - Check IAM role permissions
   - Validate token handling

3. **Performance Issues**
   - Monitor EC2 instance metrics
   - Check WebSocket API metrics
   - Review CloudWatch logs

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.
