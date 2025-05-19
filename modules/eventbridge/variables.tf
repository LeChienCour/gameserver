variable "appsync_api_id" {
  description = "The ID of the AppSync GraphQL API"
  type        = string
}

variable "prefix" {
  description = "Prefix to be used for resource names"
  type        = string
  default     = "voice-chat"
}

variable "event_bus_name" {
  description = "Name of the custom event bus"
  type        = string
  default     = "voice-chat-event-bus"
}

variable "event_source" {
  description = "Source identifier for the events"
  type        = string
  default     = "appsync.voicechat"
}

variable "event_detail_type" {
  description = "Detail type for the events"
  type        = string
  default     = "SendAudioEvent"
}

variable "log_retention_days" {
  description = "Number of days to retain CloudWatch logs"
  type        = number
  default     = 30
} 