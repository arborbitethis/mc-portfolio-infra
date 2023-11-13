######################################################
#  Lambda 
######################################################
# Lambda Layer for dependencies
resource "aws_lambda_layer_version" "lambda_layer" {
  layer_name  = "image-time-analysis-layer"
  description = "Layer for Image Time Analysis dependencies"

  compatible_runtimes = ["python3.9"]

  s3_bucket = aws_s3_bucket.lambda_s3.id
  s3_key    = "img_processing/dependency_layer.zip"
}

# Lambda Function
resource "aws_lambda_function" "s3_new_object_trigger" {
  function_name = "ImageExifExtraction"
  handler       = "image_time_analysis.lambda_handler" # make sure this matches your file and function name
  runtime       = "python3.9"  # or whichever Python version you are using

  s3_bucket = aws_s3_bucket.lambda_s3.id
  s3_key    = "img_processing/image_time_analysis.zip"

  role = aws_iam_role.lambda_exec.arn

  timeout = 30

  # Attach the layer to the Lambda Function
  layers = [aws_lambda_layer_version.lambda_layer.arn]
}


resource "aws_iam_role" "lambda_exec" {
  name = "lambda_s3_exec_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = "sts:AssumeRole",
        Effect = "Allow",
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "lambda_s3_perms" {
  policy_arn = aws_iam_policy.s3_trigger_policy.arn
  role       = aws_iam_role.lambda_exec.name
}

resource "aws_iam_policy" "s3_trigger_policy" {
  name        = "S3TriggerLambdaPolicy"
  description = "Policy to allow Lambda to be triggered by S3 and log to CloudWatch"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ],
        Effect   = "Allow",
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Action = "s3:GetObject",
        Effect = "Allow",
        Resource = "${aws_s3_bucket.portfolio_s3.arn}/*"
      }
    ]
  })
}

resource "aws_s3_bucket_notification" "bucket_notification" {
  bucket = aws_s3_bucket.portfolio_s3.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.s3_new_object_trigger.arn
    events              = ["s3:ObjectCreated:*"]
  }
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.s3_new_object_trigger.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "${aws_s3_bucket.portfolio_s3.arn}"
}