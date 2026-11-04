# Test registry for the Graviton playground images (see graviton_runner.tf).
# ECR costs nothing per-repository; only storage ($0.10/GB-month). Same-region
# push from the runner is free.
resource "aws_ecr_repository" "graviton_playground" {
  name                 = "graviton-playground"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true # basic scanning is free; flags CVEs in the pushed image
  }

  tags = { Project = "graviton-playground" }
}
