variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "throttle_burst_limit" {
  type    = number
  default = 20
}

variable "throttle_rate_limit" {
  type    = number
  default = 10
}
