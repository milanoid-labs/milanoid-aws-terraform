# Custom ASG termination policy: filters scale-in candidates to instances
# with no running ECS tasks.
data "aws_caller_identity" "current" {}

data "archive_file" "custom_ec2_termination" {
  type        = "zip"
  source_file = "${path.module}/custom_ec2_termination/lambda_function.py"
  output_path = "${path.module}/custom_ec2_termination/lambda.zip"
}

data "aws_iam_policy_document" "custom_ec2_termination_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "custom_ec2_termination" {
  name               = "milanoid-custom-ec2-termination"
  assume_role_policy = data.aws_iam_policy_document.custom_ec2_termination_assume_role.json
}

data "aws_iam_policy_document" "custom_ec2_termination" {
  statement {
    sid    = "AllowECSActions"
    effect = "Allow"
    actions = [
      "ecs:ListContainerInstances",
      "ecs:DescribeContainerInstances",
      "ecs:ListTasks",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.custom_ec2_termination.arn}:*"]
  }
}

resource "aws_iam_role_policy" "custom_ec2_termination" {
  name   = "custom-ec2-termination"
  role   = aws_iam_role.custom_ec2_termination.name
  policy = data.aws_iam_policy_document.custom_ec2_termination.json
}

resource "aws_cloudwatch_log_group" "custom_ec2_termination" {
  name              = "/aws/lambda/milanoid-custom-ec2-termination"
  retention_in_days = 7
}

resource "aws_lambda_function" "custom_ec2_termination" {
  function_name    = "milanoid-custom-ec2-termination"
  role             = aws_iam_role.custom_ec2_termination.arn
  handler          = "lambda_function.lambda_handler"
  runtime          = "python3.12"
  timeout          = 10
  filename         = data.archive_file.custom_ec2_termination.output_path
  source_code_hash = data.archive_file.custom_ec2_termination.output_base64sha256
}

resource "aws_lambda_permission" "custom_ec2_termination" {
  statement_id  = "AllowInvokeByAutoScaling"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.custom_ec2_termination.arn
  principal     = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling"
}
