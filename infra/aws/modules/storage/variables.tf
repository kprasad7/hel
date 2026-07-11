variable "project" {
  type = string
}

variable "env" {
  type = string
}

variable "artifacts_expiration_days" {
  type    = number
  default = 7
}
