rule "terraform_deprecated_interpolation" {
  enabled = true
}

rule "terraform_deprecated_index" {
  enabled = true
}

rule "terraform_unused_declarations" {
  enabled = true
}

rule "terraform_comment_syntax" {
  enabled = true
}

rule "terraform_documented_variables" {
  enabled = true
}

rule "terraform_typed_variables" {
  enabled = true
}

rule "terraform_naming_convention" {
  enabled = true
}

## Disabled: this repo deliberately splits config into topic-named files
## (network.tf, iam.tf, ecs.tf, ...) rather than a main.tf/outputs.tf
## module layout.
# rule "terraform_standard_module_structure" {
#   enabled = false
# }
