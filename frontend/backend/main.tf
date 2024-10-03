provider "aws" {
  region = "ap-south-1"
}

# Create the DynamoDB table
resource "aws_dynamodb_table" "visitor_count" {
  name         = "visitor_count"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "counterid"

  attribute {
    name = "counterid"
    type = "S"
  }
}

# Create a new IAM Role for Lambda
resource "aws_iam_role" "lambda_exec" {
  name = "lambda_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Principal = {
          Service = "lambda.amazonaws.com"
        },
        Effect = "Allow",
        Sid    = ""
      }
    ]
  })
}

# Attach policies to the Lambda role to allow access to CloudWatch and DynamoDB
resource "aws_iam_policy_attachment" "lambda_policy_cloudwatch" {
  name       = "lambda_policy_cloudwatch_attachment"
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
  roles      = [aws_iam_role.lambda_exec.name]
}

resource "aws_iam_policy" "lambda_dynamodb_policy" {
  name = "LambdaDynamoDBPolicy"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:UpdateItem"
        ],
        Effect   = "Allow",
        Resource = aws_dynamodb_table.visitor_count.arn
      }
    ]
  })
}

resource "aws_iam_policy_attachment" "lambda_policy_dynamodb" {
  name       = "lambda_policy_dynamodb_attachment"
  policy_arn = aws_iam_policy.lambda_dynamodb_policy.arn
  roles      = [aws_iam_role.lambda_exec.name]
}

# Create the Lambda function
resource "aws_lambda_function" "visitor_counter" {
  function_name = "VisitorCounter"
  handler       = "lambda_function.lambda_handler"
  runtime       = "python3.8"
  role          = aws_iam_role.lambda_exec.arn
  filename      = "lambda/lambda_function.zip"

  environment {
    variables = {
      DYNAMODB_TABLE = "visitor_count"
    }
  }
}

# Allow API Gateway to invoke the Lambda function
resource "aws_lambda_permission" "api_gateway_invoke_lambda" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.visitor_counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_api_gateway_rest_api.my_api.execution_arn}/*/*"
}

# Create the API Gateway
resource "aws_api_gateway_rest_api" "my_api" {
  name        = "VisitorCounterAPI"
  description = "API for counting visitors"
}

# Create a resource under the API
resource "aws_api_gateway_resource" "my_resource" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part   = "visitor"
}

# Create a GET method for the resource
resource "aws_api_gateway_method" "my_method" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.my_resource.id
  http_method   = "GET"
  authorization = "NONE"
}

# Create an OPTIONS method for CORS preflight requests
resource "aws_api_gateway_method" "options_method" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.my_resource.id
  http_method   = "OPTIONS"
  authorization = "NONE"
}

# Create the API Gateway integration for the GET method
resource "aws_api_gateway_integration" "my_integration" {
  rest_api_id             = aws_api_gateway_rest_api.my_api.id
  resource_id             = aws_api_gateway_resource.my_resource.id
  http_method             = aws_api_gateway_method.my_method.http_method
  integration_http_method = "POST"
  type                    = "AWS_PROXY"
  uri                     = aws_lambda_function.visitor_counter.invoke_arn
}

# Create a method response for the GET method
resource "aws_api_gateway_method_response" "my_method_response" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.my_resource.id
  http_method = aws_api_gateway_method.my_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
    "method.response.header.Content-Type"                 = true
  }
}

# Create a method response for the OPTIONS method
resource "aws_api_gateway_method_response" "options_method_response" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.my_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = "200"

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = true
    "method.response.header.Access-Control-Allow-Headers" = true
    "method.response.header.Access-Control-Allow-Methods" = true
  }
}

# Create mock integration for the OPTIONS method
resource "aws_api_gateway_integration" "options_integration" {
  rest_api_id             = aws_api_gateway_rest_api.my_api.id
  resource_id             = aws_api_gateway_resource.my_resource.id
  http_method             = aws_api_gateway_method.options_method.http_method
  integration_http_method = "POST"
  type                    = "MOCK"
}

# Create integration response for the OPTIONS method
resource "aws_api_gateway_integration_response" "options_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.my_resource.id
  http_method = aws_api_gateway_method.options_method.http_method
  status_code = aws_api_gateway_method_response.options_method_response.status_code

  response_parameters = {
    "method.response.header.Access-Control-Allow-Origin"  = "'*'"
    "method.response.header.Access-Control-Allow-Headers" = "'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token'"
    "method.response.header.Access-Control-Allow-Methods" = "'OPTIONS,GET'"
  }

  depends_on = [
    aws_api_gateway_integration.options_integration
  ]
}

# Create deployment for API Gateway
resource "aws_api_gateway_deployment" "api_deployment" {
  depends_on = [
    aws_api_gateway_method.my_method,
    aws_api_gateway_integration.my_integration,
    aws_api_gateway_method_response.my_method_response,
    aws_api_gateway_method.options_method,
    aws_api_gateway_method_response.options_method_response,
    aws_api_gateway_integration_response.options_integration_response
  ]

  rest_api_id = aws_api_gateway_rest_api.my_api.id
  stage_name  = "prod"
}

# Redirect API Gateway requests to CloudFront (optional)
variable "cloudfront_domain" {
  default = "https://d1e95w77i9u0gr.cloudfront.net"
}

# Create a new resource for redirecting to CloudFront
resource "aws_api_gateway_resource" "redirect" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  parent_id   = aws_api_gateway_rest_api.my_api.root_resource_id
  path_part   = "redirect"
}

# Create a GET method for the redirect
resource "aws_api_gateway_method" "redirect_method" {
  rest_api_id   = aws_api_gateway_rest_api.my_api.id
  resource_id   = aws_api_gateway_resource.redirect.id
  http_method   = "GET"
  authorization = "NONE"
}

# Create the integration for the redirect to CloudFront
resource "aws_api_gateway_integration" "redirect_integration" {
  rest_api_id             = aws_api_gateway_rest_api.my_api.id
  resource_id             = aws_api_gateway_resource.redirect.id
  http_method             = aws_api_gateway_method.redirect_method.http_method
  integration_http_method = "GET"
  type                    = "HTTP"
  uri                     = var.cloudfront_domain
}

# Create a method response for the redirect method
resource "aws_api_gateway_method_response" "redirect_method_response" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.redirect.id
  http_method = aws_api_gateway_method.redirect_method.http_method
  status_code = "302"

  response_parameters = {
    "method.response.header.Location" = true
  }
}

# Create integration response for the redirect method
resource "aws_api_gateway_integration_response" "redirect_integration_response" {
  rest_api_id = aws_api_gateway_rest_api.my_api.id
  resource_id = aws_api_gateway_resource.redirect.id
  http_method = aws_api_gateway_method.redirect_method.http_method
  status_code = aws_api_gateway_method_response.redirect_method_response.status_code

  response_parameters = {
    "method.response.header.Location" = "'https://d1e95w77i9u0gr.cloudfront.net'"
  }

  depends_on = [
    aws_api_gateway_integration.redirect_integration
  ]
}
