variable "name" {
  description = "Base name for the deployment."
  type        = string
}

variable "namespace" {
  description = "Namespace for the deployment."
  type        = string
}

variable "replicas" {
  description = "Number of replicas."
  type        = number
  default     = 1
}

variable "node_group" {
  description = "Node group selector."
  type = object({
    key   = string
    value = string
  })
}

variable "conda_store_image" {
  description = "Conda store image."
  type        = string
}

variable "conda_store_image_tag" {
  description = "Conda store image tag."
  type        = string
}

variable "conda_store_worker_resources" {
  description = "Resource requests and limits for conda store worker."
  type = object({
    requests = map(string)
  })
}

variable "keda-scaling-query" {
  description = "Keda scaling query."
  type        = string
}

variable "keda-target-query-value" {
  description = "Keda scaling query."
  type        = number
}


# "SELECT GREATEST(COUNT(*)-1, 0) FROM build WHERE status IN ('QUEUED', 'BUILDING');"
