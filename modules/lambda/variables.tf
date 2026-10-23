variable "prefix" {
  description = "Prefix for resource names"
  type        = string
}

variable "environment" {
  description = "Environment name (e.g., dev, prod)"
  type        = string
  default     = "dev"
}

variable "lambda_functions" {
  description = "Map of Lambda function names to their deployment package paths"
  type        = map(string)
}

variable "audio_bucket_name" {
  description = "Name of the S3 bucket for audio storage"
  type        = string
}

variable "event_bus_name" {
  description = "Name of the EventBridge event bus"
  type        = string
}

variable "event_source" {
  description = "Source for EventBridge events"
  type        = string
}

variable "lambda_role_arn" {
  description = "ARN of the IAM role for Lambda functions"
  type        = string
}

variable "api_gateway_id" {
  description = "ID of the API Gateway"
  type        = string
}

variable "api_gateway_execution_arn" {
  description = "Execution ARN of the API Gateway"
  type        = string
}

variable "project_name" {
  description = "Name of the project"
  type        = string
}

# Lambda Function Configuration (Right-sized for cost efficiency on Graviton2 ARM64)
variable "process_audio_timeout" {
  description = "Timeout for the process audio Lambda function in seconds"
  type        = number
  default     = 15
}

variable "process_audio_memory" {
  description = "Memory allocation for the process audio Lambda function in MB"
  type        = number
  default     = 256
}

variable "validate_audio_timeout" {
  description = "Timeout for the validate audio Lambda function in seconds"
  type        = number
  default     = 15
}

variable "validate_audio_memory" {
  description = "Memory allocation for the validate audio Lambda function in MB"
  type        = number
  default     = 256
}

variable "websocket_timeout" {
  description = "Timeout for WebSocket Lambda functions in seconds"
  type        = number
  default     = 15
}

variable "websocket_memory" {
  description = "Memory allocation for WebSocket Lambda functions in MB"
  type        = number
  default     = 256
}

variable "audio_processing_rule_arn" {
  description = "ARN of the audio processing EventBridge rule"
  type        = string
}

variable "audio_validation_rule_arn" {
  description = "ARN of the audio validation EventBridge rule"
  type        = string
}

variable "stage" {
  description = "Deployment stage (e.g., dev, staging, prod)"
  type        = string
}

variable "lambda_runtime" {
  description = "Python runtime version for Lambda functions"
  type        = string
  default     = "python3.12"
}

variable "lambda_architecture" {
  description = "Instruction set architecture for Lambda functions (arm64 saves 20% cost on Graviton2)"
  type        = string
  default     = "arm64"
}

variable "enable_echo_mode" {
  description = "Enable echo mode for audio broadcasting"
  type        = bool
  default     = true
}

variable "enable_direct_broadcast" {
  description = "Enable low-latency direct broadcast in message Lambda before EventBridge archival"
  type        = bool
  default     = true
}

variable "enable_audio_archival" {
  description = "Publish audio packets to EventBridge/S3 for archival (disable to save 100% S3 PUT & EventBridge costs)"
  type        = bool
  default     = false
}

variable "max_voice_distance" {
  description = "Maximum 3D block distance for proximity voice filtering (0 = global)"
  type        = number
  default     = 64
}

variable "log_retention_days" {
  description = "Number of days to retain Lambda CloudWatch logs"
  type        = number
  default     = 30
}
