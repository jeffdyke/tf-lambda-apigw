locals {
  sqs_prefix     = "SendgridWebhooks"
  queue          = "${local.sqs_prefix}Queue"
  policy         = "${local.sqs_prefix}Policy"
  role           = "${local.sqs_prefix}Role"
  api            = "${local.sqs_prefix}Api"
  api_authorizer = "${local.api}Auth"
  api_aws_lambda = "${local.api_authorizer}Fn"
  api_method     = "${local.api}Method"
  api_deployment = "${local.api}Deployment"
  api_stage      = "${local.api}Stage"
}
module "sqs" {
  source   = "../modules/terraform-aws-sqs"
  queues   = ["${local.queue}${var.stack_suffix}"]
  template = "../templates/aws_sqs_default_policy.json"
  use_kms  = true
}
module "assume_role_lambda" {
  source             = "../modules/terraform-aws-assume-role"
  service_identifier = "lambda.amazonaws.com"
  service_version    = "2012-10-17"
}
data "archive_file" "sendgrid_dev_auth" {
  type        = "zip"
  source_file = "${path.module}/index.js"
  output_path = "index.zip"
}

data "aws_iam_policy_document" "dev_sendgrid_assume_policy" {
  version = "2012-10-17"
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com", "apigateway.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "dev_sendgrid_sqs_policy" {
  version = "2012-10-17"
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [module.sqs.sqs_queues["${local.queue}${var.stack_suffix}"]]
  }
  statement {
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = ["*"]
  }
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}
resource "aws_iam_policy" "sendgrid_dev_sqs" {
  name   = "${local.policy}${var.stack_suffix}"
  policy = data.aws_iam_policy_document.dev_sendgrid_sqs_policy.json

}
resource "aws_lambda_function" "sendgrid_dev_auth" {
  filename         = data.archive_file.sendgrid_dev_auth.output_path
  function_name    = "${local.api_aws_lambda}${var.stack_suffix}"
  role             = aws_iam_role.sendgrid.arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  source_code_hash = data.archive_file.sendgrid_dev_auth.output_base64sha256
}

resource "aws_iam_role" "sendgrid" {
  name               = "${local.role}${var.stack_suffix}"
  path               = "/"
  assume_role_policy = data.aws_iam_policy_document.dev_sendgrid_assume_policy.json
}
resource "aws_iam_role_policy_attachment" "sendgrid_dev_sqs" {
  role       = aws_iam_role.sendgrid.name
  policy_arn = aws_iam_policy.sendgrid_dev_sqs.arn
}
resource "aws_iam_role_policy_attachment" "lambda_basic" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  role       = aws_iam_role.sendgrid.name
}
