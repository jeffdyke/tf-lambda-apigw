// API Gateway
resource "aws_api_gateway_rest_api" "rest_api" {
  name        = "${local.api_aws_lambda}${var.stack_suffix}"
  description = "SendGridAPI"

  endpoint_configuration {
    types = ["EDGE"]
  }
}

resource "aws_api_gateway_authorizer" "sendgrid_dev_auth" {
  name                   = "${local.api_authorizer}${var.stack_suffix}"
  authorizer_credentials = aws_iam_role.sendgrid.arn
  rest_api_id            = aws_api_gateway_rest_api.rest_api.id
  type                   = "REQUEST"
  authorizer_uri         = aws_lambda_function.sendgrid_dev_auth.invoke_arn
  identity_source        = "method.request.querystring.authToken"
}

resource "aws_api_gateway_resource" "root" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  parent_id   = aws_api_gateway_rest_api.rest_api.root_resource_id
  path_part   = "auth"
}

resource "aws_api_gateway_method" "proxy_post" {
  rest_api_id   = aws_api_gateway_rest_api.rest_api.id
  resource_id   = aws_api_gateway_resource.root.id
  http_method   = "POST"
  authorization = "CUSTOM"
  authorizer_id = aws_api_gateway_authorizer.sendgrid_dev_auth.id

}
resource "aws_api_gateway_method_response" "proxy_post" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  resource_id = aws_api_gateway_resource.root.id
  http_method = aws_api_gateway_method.proxy_post.http_method
  status_code = "200"
  # response_models = {
  #   "application/json" = "SendgridAuthDevModel"
  # }
  response_parameters = {
    "method.response.header.Content-Type" = false
  }
  depends_on = [aws_api_gateway_method.proxy_post]
}

resource "aws_api_gateway_integration" "sendgrid_dev" {
  rest_api_id             = aws_api_gateway_rest_api.rest_api.id
  resource_id             = aws_api_gateway_resource.root.id
  http_method             = aws_api_gateway_method.proxy_post.http_method
  credentials             = aws_iam_role.sendgrid.arn
  connection_type         = "INTERNET"
  integration_http_method = "POST"
  type                    = "AWS"

  uri = "arn:aws:apigateway:us-east-1:sqs:path/668874212870/SendgridWebhooksQueueDev"
  request_parameters = {
    "integration.request.header.Content-Type" = "'application/x-www-form-urlencoded'"
  }

  request_templates = {
    "application/json"                  = "Action=SendMessage\u0026MessageBody=$util.urlEncode($input.body)"
    "application/x-www-form-urlencoded" = "Action=SendMessage\u0026MessageBody=$util.urlEncode($input.body)"
  }
  passthrough_behavior = "WHEN_NO_MATCH"
}
resource "aws_api_gateway_integration_response" "sendgrid_dev" {

  rest_api_id       = aws_api_gateway_rest_api.rest_api.id
  resource_id       = aws_api_gateway_resource.root.id
  http_method       = aws_api_gateway_method.proxy_post.http_method
  status_code       = aws_api_gateway_method_response.proxy_post.status_code
  selection_pattern = "2\\d+"
  depends_on = [
    aws_api_gateway_method.proxy_post,
    aws_api_gateway_integration.sendgrid_dev
  ]
}

resource "aws_api_gateway_deployment" "deployment" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  triggers = {
    redeployment = sha1(jsonencode([
      aws_api_gateway_resource.root.id,
      aws_api_gateway_method.proxy_post.id,
      aws_api_gateway_integration.sendgrid_dev.id,
    ]))
  }

  lifecycle {
    create_before_destroy = true
  }

}

resource "aws_api_gateway_stage" "sendgrid_dev" {
  deployment_id = aws_api_gateway_deployment.deployment.id
  rest_api_id   = aws_api_gateway_rest_api.rest_api.id
  stage_name    = "${local.api_stage}${var.stack_suffix}"
}
resource "aws_iam_role_policy_attachment" "main" {
  role       = aws_iam_role.sendgrid.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonAPIGatewayPushToCloudWatchLogs"
}
resource "aws_api_gateway_method_settings" "sendgrid_dev" {
  rest_api_id = aws_api_gateway_rest_api.rest_api.id
  stage_name  = aws_api_gateway_stage.sendgrid_dev.stage_name
  method_path = "auth/POST"

  settings {
    cache_ttl_in_seconds   = 600
    logging_level          = "INFO"
    caching_enabled        = true
    throttling_burst_limit = null
  }
}

output "rest_api" {
  value = aws_api_gateway_rest_api.rest_api
}
locals {
  #path_part is not allowed to be empty in terraform, so if we see that is populated, the test is Stage
  function_portion = length(aws_api_gateway_resource.root.path_part) > 1 ? local.api_stage : local.queue
  api_domain       = "execute-api.us-east-1.amazonaws.com"
}
output "test_endpoint" {
  value = "https://${aws_api_gateway_rest_api.rest_api.id}.${local.api_domain}${local.function_portion}${var.stack_suffix}"
}
