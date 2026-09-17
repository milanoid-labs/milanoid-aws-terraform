resource "aws_iam_user" "prometheus" {
  name = "prometheus-ec2-scraper"
}

resource "aws_iam_user_policy_attachment" "prometheus_ec2_readonly" {
  user       = aws_iam_user.prometheus.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ReadOnlyAccess"
}
