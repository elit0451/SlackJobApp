# Region
provider "aws" {
  region = "eu-west-1"
}


# Data resources (SQS, SSM)
data "aws_sqs_queue" "stg-processed-job-post-queue" {
  name = "stg_ProcessedJobPosts"
}


data "aws_ssm_parameter" "slackleads-table" {
  name = "TABLE_SLACK_LEADS" # our SSM parameter's name
}

data "aws_ssm_parameter" "slack-token" {
  name = "SLACK_TOKEN" # our SSM parameter's name
}

data "aws_ssm_parameter" "close-token" {
  name = "CLOSE_TOKEN" # our SSM parameter's name
}


# Lambda
resource "aws_lambda_function" "stg-SlackJobPoster-lambda" {
  function_name    = "stg-SlackJobPoster"
  handler          = "SlackJobPoster::SlackJobPoster.Function::FunctionHandler"
  runtime          = "dotnetcore2.1"
  role             = "arn:aws:iam::833191605868:role/SlackJobPosterRole"
  filename         = "../../SlackJobPoster/src/SlackJobPoster/bin/Debug/netcoreapp2.1/SlackJobPoster.zip"
  source_code_hash = filebase64sha256("../../SlackJobPoster/src/SlackJobPoster/bin/Debug/netcoreapp2.1/SlackJobPoster.zip")
  timeout          = 10
  memory_size      = 256

  tags = {
    Name        = "stg-SlackJobPoster"
    Environment = "staging"
  }
}

resource "aws_lambda_event_source_mapping" "stg-incoming-sqs" {
  event_source_arn = data.aws_sqs_queue.stg-processed-job-post-queue.arn
  function_name    = aws_lambda_function.stg-SlackJobPoster-lambda.arn
}

resource "aws_lambda_function" "stg-SlackJobPosterReceiver-lambda" {
  function_name    = "stg-SlackJobPosterReceiver"
  handler          = "SlackJobPosterReceiver::SlackJobPosterReceiver.Function::Get"
  runtime          = "dotnetcore2.1"
  role             = "arn:aws:iam::833191605868:role/DeleteThisRole"
  filename         = "../../SlackJobPosterReceiver/src/SlackJobPosterReceiver/bin/Debug/netcoreapp2.1/SlackJobPosterReceiver.zip"
  source_code_hash = filebase64sha256("../../SlackJobPosterReceiver/src/SlackJobPosterReceiver/bin/Debug/netcoreapp2.1/SlackJobPosterReceiver.zip")
  timeout          = 10
  memory_size      = 256

  tags = {
    Name        = "stg-SlackJobPosterReceiver"
    Environment = "staging"
  }

  environment {
    variables = {
      AWS_TABLE_SLACK_LEADS = data.aws_ssm_parameter.slackleads-table.value
      SLACK_TOKEN           = data.aws_ssm_parameter.slack-token.value
      CLOSE_TOKEN           = data.aws_ssm_parameter.close-token.value
    }
  }
}


# API Gateway
resource "aws_api_gateway_rest_api" "slack-app-api" {
  name = "slackAppApi"
}

resource "aws_api_gateway_resource" "slack-receiver-resource" {
  path_part   = "slackReceiver"
  parent_id   = aws_api_gateway_rest_api.slack-app-api.root_resource_id
  rest_api_id = aws_api_gateway_rest_api.slack-app-api.id
}

resource "aws_api_gateway_method" "slack-receiver-any" {
  rest_api_id   = aws_api_gateway_rest_api.slack-app-api.id
  resource_id   = aws_api_gateway_resource.slack-receiver-resource.id
  http_method   = "ANY"
  authorization = "NONE"
}

resource "aws_api_gateway_integration" "integration" {
  rest_api_id             = aws_api_gateway_rest_api.slack-app-api.id
  resource_id             = aws_api_gateway_resource.slack-receiver-resource.id
  http_method             = aws_api_gateway_method.slack-receiver-any.http_method
  integration_http_method = "ANY"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.stg-SlackJobPosterReceiver-lambda.invoke_arn
}

resource "aws_api_gateway_deployment" "slack-receiver-api-deployment" {
  depends_on = [aws_api_gateway_integration.integration]

  rest_api_id = aws_api_gateway_rest_api.slack-app-api.id
  stage_name  = "staging"
}

# Dynamo DB
resource "aws_dynamodb_table" "stg-slack-leads-table" {
  name           = "stg_SlackLeads"
  hash_key       = "message_ts"
  read_capacity  = 5
  write_capacity = 5

  attribute {
    name = "message_ts"
    type = "S"
  }

  tags = {
    Name        = "stg-slack-leads-table"
    Environment = "staging"
  }
}