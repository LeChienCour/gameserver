# GameServer Infrastructure

This project provides Infrastructure as Code (IaC) using Terraform to deploy a game server infrastructure in AWS. The infrastructure includes a GraphQL API (AppSync), authentication (Cognito), and necessary networking components.

## Architecture Overview

The infrastructure consists of the following main components:

- **VPC and Networking**: Custom VPC with public subnets and internet gateway
- **EC2 Game Server**: Instance running the game server application
- **AppSync API**: GraphQL API for game data management
- **Cognito**: User authentication and authorization
- **SSM Parameters**: Secure storage for API credentials and endpoints
- **Security Groups**: Network access control

## Prerequisites

Before deploying this infrastructure, ensure you have:

1. [AWS CLI](https://aws.amazon.com/cli/) installed and configured
2. [Terraform](https://www.terraform.io/downloads.html) (version >= 1.0.0)
3. An AWS account with appropriate permissions
4. A S3 bucket for Terraform state (see below)
5. A DynamoDB table for state locking (see below)

## Initial Setup

### 1. Create State Backend Resources

Before deploying the infrastructure, create the following resources for Terraform state management:

```bash
# Create S3 bucket for state
aws s3 mb s3://devops-t2-gameserver-tfstate --region us-east-1

# Create DynamoDB table for state locking
aws dynamodb create-table \
    --table-name terraform-state-locks \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=1,WriteCapacityUnits=1 \
    --region us-east-1
```

### 2. Configure Variables

Create a `terraform.tfvars` file with your specific values:

```hcl
region              = "us-east-1"
vpc_cidr            = "10.0.0.0/16"
public_subnets_cidr = ["10.0.1.0/24", "10.0.2.0/24"]
availability_zones  = ["us-east-1a", "us-east-1b"]
vpc_name           = "gameserver-vpc"
game_port          = 7777
audio_port         = 7000
ssh_cidr           = "0.0.0.0/0"  # Restrict this to your IP in production
game_protocol      = "udp"
instance_type      = "t3.medium"
security_group_name = "game-server-sg"
user_pool_name     = "gameserver-users"
app_client_name    = "gameserver-client"
admin_role_name    = "gameserver-admin"
```

## Deployment

Follow these steps to deploy the infrastructure:

1. Initialize Terraform:
   ```bash
   terraform init
   ```

2. Review the deployment plan:
   ```bash
   terraform plan
   ```

3. Apply the configuration:
   ```bash
   terraform apply
   ```

4. After successful deployment, you can retrieve the important information:
   ```bash
   # Get the GraphQL API endpoint
   aws ssm get-parameter --name "/gameserver/appsync/graphql_api_uri"

   # Get the Game Server IP
   terraform output game_server_public_ip
   ```

## Infrastructure Components

### VPC Module
- Creates a custom VPC with public subnets
- Sets up internet gateway and routing
- Enables DNS support and hostnames

### Security Groups Module
- Configures network access for the game server
- Allows game traffic on specified port
- Allows SSH access (configurable)
- Enables audio chat communication

### EC2 Game Server Module
- Deploys the game server instance
- Associates an Elastic IP
- Configurable instance type and AMI

### Cognito Module
- Sets up user authentication
- Creates user pool and app client
- Configures password policies and verification

### AppSync Module
- Creates GraphQL API
- Sets up API authentication
- Configures API key for testing

### SSM Module
- Stores sensitive configuration securely
- Manages API endpoints and credentials
- Enables easy access to infrastructure information

## Security Considerations

1. Restrict SSH access (`ssh_cidr`) to specific IP ranges
2. Use appropriate instance types based on load
3. Regularly rotate API keys
4. Monitor AWS CloudWatch logs
5. Keep Terraform and provider versions updated

## Cost Considerations

This infrastructure includes several AWS services that incur costs:

- EC2 instance (hourly charges)
- AppSync API (request-based pricing)
- Cognito (MAU-based pricing)
- EIP (charged when not associated with running instance)
- Data transfer charges

## Maintenance

### Updating Infrastructure
```bash
# Get latest changes
git pull

# Plan changes
terraform plan

# Apply changes
terraform apply
```

### Destroying Infrastructure
```bash
terraform destroy
```

## Troubleshooting

1. **State Lock Issues**:
   ```bash
   # Force unlock if needed
   terraform force-unlock [LOCK_ID]
   ```

2. **Connection Issues**:
   - Verify security group rules
   - Check instance status
   - Validate network configuration

3. **API Issues**:
   - Verify Cognito configuration
   - Check AppSync schema
   - Validate API key permissions

## Contributing

1. Fork the repository
2. Create a feature branch
3. Commit your changes
4. Push to the branch
5. Create a Pull Request

## License

This project is released under the Unlicense. See the [LICENSE](LICENSE) file for details.
