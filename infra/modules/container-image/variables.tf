variable "name_prefix" {
  description = "Project and environment prefix for the private application repository"
  type        = string
}

variable "build_context" {
  description = "Absolute path to the dedicated application build"
  type        = string
}
