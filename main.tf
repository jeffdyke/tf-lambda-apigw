locals {
  sqs_name = "SendgridWebhooksQueueDev"
}
module "sqs" {
  source   = "../modules/terraform-aws-sqs"
  queues   = [local.sqs_name]
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

resource "aws_iam_policy" "sendgrid" {
  policy = templatefile("${path.module}/../templates/sqs_to_lambda.json", {
    queue_resource = "SendgridWebhooksQueueDev",
    lambda_func    = "SendgridWebhooksApiAuthFnDev"
  })
  name = "SendgridWebhooksPolicyDev"
}

data "aws_iam_policy_document" "dev_sendgrid_sqs_policy" {
  version = "2012-10-17"
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [module.sqs.sqs_queues["SendgridWebhooksQueueDev"]]
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
  name   = "sendgrid_dev_sqs"
  policy = data.aws_iam_policy_document.dev_sendgrid_sqs_policy.json

}
resource "aws_lambda_function" "sendgrid_dev_auth" {
  filename         = data.archive_file.sendgrid_dev_auth.output_path
  function_name    = "SendgridWebhooksApiAuthFnDev"
  role             = aws_iam_role.sendgrid.arn
  runtime          = "nodejs22.x"
  handler          = "index.handler"
  source_code_hash = data.archive_file.sendgrid_dev_auth.output_base64sha256
}
# resource "aws_iam_role_policy" "sendgrid" {
#   policy = jsonencode(
#     {
#       "Version" : "2012-10-17",
#       "Id" : "arn:aws:sqs:us-east-1:668874212870:${name}/SQSDefaultPolicy",
#       "Statement" : [
#         {
#           "Sid" : "Sid1477675970718",
#           "Effect" : "Allow",
#           "Principal" : "*",
#           "Action" : "SQS:*",
#           "Resource" : "arn:aws:sqs:us-east-1:668874212870:${name}"
#         }
#       ]
#     }
#   )
#   role = aws_iam_role.sendgrid
# }
resource "aws_iam_role" "sendgrid" {
  name               = "dev_sendgrid_apigateway"
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

# resource "aws_lambda_permission" "apigw_lambda" {
#   statement_id  = "AllowExecutionFromAPIGateway"
#   action        = "lambda:InvokeFunction"
#   function_name = aws_lambda_function.sendgrid_dev_auth.function_name
#   principal     = "apigateway.amazonaws.com"

#   source_arn = "${aws_api_gateway_rest_api.rest_api.execution_arn}/*"
# }

# output "permission" {
#   value = aws_lambda_permission.apigw_lambda
# }
