#########################
# Data Sources
#########################

# Default VPC
data "aws_vpc" "default" {
  default = true
}

# Default subnets of that VPC
data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Current region
data "aws_region" "current" {}

############################################
# S3 BUCKET CREATION FOR RAW DATA
############################################

resource "aws_s3_bucket" "my_bucket" {
  bucket        = "s3-bucket-youtube-data"   # change if needed (must be globally unique)
  force_destroy = true

  tags = {
    Project = "Youtube-data"
    Env     = "dev"
  }
}

############################################
# Create S3 Prefix: youtube/raw_statistics_reference_data
############################################

resource "aws_s3_object" "youtube_prefix_reference" {
  bucket       = aws_s3_bucket.my_bucket.bucket
  key          = "youtube/raw_statistics_reference_data/"          # folder prefix
  content      = ""                     # required
  content_type = "application/x-directory"
}

############################################
# Create S3 Prefix: youtube/raw_statistics
############################################

resource "aws_s3_object" "youtube_prefix_raw" {
  bucket       = aws_s3_bucket.my_bucket.bucket
  key          = "youtube/raw_statistics/"          # folder prefix (added trailing slash)
  content      = ""                     # required
  content_type = "application/x-directory"
}

############################################
# Create S3 Prefix: aws-services/aws-glue/etl-jobs/
############################################

resource "aws_s3_object" "youtube_prefix_etl" {
  bucket       = aws_s3_bucket.my_bucket.bucket
  key          = "aws-services/aws-glue/etl-jobs/"          # folder prefix
  content      = ""                     # required
  content_type = "application/x-directory"
}

############################################
# Upload Lambda ZIP (or Python file) to S3
############################################

resource "aws_s3_object" "lambda_zip" {
  bucket = aws_s3_bucket.my_bucket.bucket
  key    = "lambda/Lambda_Function_Code.zip"   # put lambda code under a folder
  source = "${path.module}/Lambda_Function_Code.zip"
  etag   = filemd5("${path.module}/Lambda_Function_Code.zip")
}

############################################
# Upload Glue Job Code to S3
############################################

resource "aws_s3_object" "Glue_Job" {
  bucket = aws_s3_bucket.my_bucket.bucket
  key    = "aws-services/aws-glue/etl-jobs/Glue_job_Code.py"  
  source = "${path.module}/Glue_job_Code.py"
  etag   = filemd5("${path.module}/Glue_job_Code.py")
}

############################################
# S3 BUCKET CREATION FOR CLEAN DATA
############################################

resource "aws_s3_bucket" "clean_yt_data_bucket" {
  bucket        = "s3-bucket-youtube-clean-data"   # change if needed (must be globally unique)
  force_destroy = true

  tags = {
    Project = "Youtube-data"
    Env     = "dev"
  }
}

############################################
# Create S3 Prefix: youtube/cleansed_statistics_reference_data
############################################

resource "aws_s3_object" "youtube_prefix_cleansed" {
  bucket       = aws_s3_bucket.clean_yt_data_bucket.bucket
  key          = "youtube/cleansed_statistics_reference_data/"          # folder prefix
  content      = ""                     # required
  content_type = "application/x-directory"
}

############################################
# AWS GLUE DATABASES
############################################
resource "aws_glue_catalog_database" "raw_youtube_db" {
  name = "db_youtube_raw"
}

resource "aws_glue_catalog_database" "clean_youtube_db" {
  name = "db_youtube_cleansed"
}

############################################
# IAM ROLE FOR AWS GLUE CRAWLER
############################################
resource "aws_iam_role" "glue_crawler_role" {
  name = "glue-crawler-service-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = "glue.amazonaws.com"
      },
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "glue_service_role_attach" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_s3_full_access_attach" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_policy" "glue_custom_s3_access" {
  name = "glue-s3-folder-access"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket"
        ],
        Resource = [
          aws_s3_bucket.my_bucket.arn,
          "${aws_s3_bucket.my_bucket.arn}/*",
          "${aws_s3_bucket.clean_yt_data_bucket.arn}/*"
        ]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_custom_s3_attach" {
  role       = aws_iam_role.glue_crawler_role.name
  policy_arn = aws_iam_policy.glue_custom_s3_access.arn
}

############################################
# AWS GLUE CRAWLER FOR RAW DATA
############################################
resource "aws_glue_crawler" "youtube_raw_crawler" {
  name          = "raw-data-youtube-crawler"
  role          = aws_iam_role.glue_crawler_role.arn
  database_name = aws_glue_catalog_database.raw_youtube_db.name

  s3_target {
    path = "s3://${aws_s3_bucket.my_bucket.bucket}/youtube/raw_statistics_reference_data/"
  }

  tags = {
    Project = "GraphDatabase"
    Env     = "Dev"
  }
}

############################################
# AWS GLUE CRAWLER FOR CLEAN DATA
############################################
resource "aws_glue_crawler" "youtube_clean_crawler" {
  name          = "clean-data-youtube-crawler"
  role          = aws_iam_role.glue_crawler_role.arn
  database_name = aws_glue_catalog_database.clean_youtube_db.name

  s3_target {
    path = "s3://${aws_s3_bucket.clean_yt_data_bucket.bucket}/youtube/cleansed_statistics_reference_data/"
  }

  tags = {
    Project = "GraphDatabase"
    Env     = "Dev"
  }
}

############################################
# AWS GLUE CRAWLER FOR HISTORICAL DATA
############################################
resource "aws_glue_crawler" "youtube_historical_data_crawler" {
  name          = "historical-data-youtube-crawler"
  role          = aws_iam_role.glue_crawler_role.arn
  database_name = aws_glue_catalog_database.raw_youtube_db.name

  s3_target {
    path = "s3://${aws_s3_bucket.my_bucket.bucket}/youtube/raw_statistics/"
  }

  tags = {
    Project = "GraphDatabase"
    Env     = "Dev"
  }
}

###############################################
# Lambda IAM Role
###############################################
resource "aws_iam_role" "lambda_role" {
  name = "lambda_kinesis_firehose_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# Attach required AWS-managed policies
resource "aws_iam_role_policy_attachment" "lambda_basic_execution" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "lambda_s3_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

resource "aws_iam_role_policy_attachment" "Cloudwatch_full_access" {
  role       = aws_iam_role.lambda_role.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchFullAccess"
}

###############################################
# Lambda Function Code
###############################################
resource "aws_lambda_function" "lambda_ingest" {
  function_name = "yt-lambda-function"
  runtime       = "python3.8"
  role          = aws_iam_role.lambda_role.arn
  handler       = "lambda_function.lambda_handler"
  memory_size   = 512
  timeout       = 600

  # Pull code from S3 (we uploaded earlier)
  s3_bucket     = aws_s3_bucket.my_bucket.bucket
  s3_key        = aws_s3_object.lambda_zip.key

  # PASS PARAMETERS TO LAMBDA (use .name for Glue DB)
  environment {
    variables = {
      S3_CLEANSED_LAYER        = "s3://${aws_s3_bucket.clean_yt_data_bucket.bucket}/youtube/cleansed_statistics_reference_data/"
      GLUE_CATALOG_DB_NAME     = aws_glue_catalog_database.clean_youtube_db.name
      GLUE_CATALOG_TABLE_NAME  = "cleansed_statistics_reference_data"
      WRITE_DATA_OPERATION     = "append"
    }
  }

  depends_on = [
    aws_s3_object.lambda_zip,
    aws_iam_role_policy_attachment.lambda_basic_execution
  ]
}

###############################################
# Allow S3 to Call Lambda
###############################################
resource "aws_lambda_permission" "allow_s3" {
  statement_id  = "AllowExecutionFromS3"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_ingest.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.my_bucket.arn
}

###############################################
# S3 Trigger → Invoke Lambda when new object in youtube/raw_statistics_reference_data/
###############################################
resource "aws_s3_bucket_notification" "raw_notify" {
  bucket = aws_s3_bucket.my_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda_ingest.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "youtube/raw_statistics_reference_data/"        # only trigger inside folder (trailing slash)
  }

  depends_on = [aws_lambda_permission.allow_s3]
}

############################################
# IAM ROLE FOR GLUE JOB
############################################
resource "aws_iam_role" "glue_job_role" {
  name = "glue-job-processing-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = {
          Service = "glue.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

############################################
# IAM POLICIES FOR GLUE JOB
############################################

# Glue service + S3 access
resource "aws_iam_role_policy" "glue_job_policy" {
  name = "glue-job-policy"
  role = aws_iam_role.glue_job_role.id

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [

      # Glue built-in operations
      {
        Effect = "Allow"
        Action = [
          "glue:*",
          "s3:*"
        ]
        Resource = "*"
      },

      # CloudWatch Logs
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "glue_job_role_attach" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy_attachment" "glue_job_s3_access_attach" {
  role       = aws_iam_role.glue_job_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}

############################################
# AWS GLUE JOB (WITH PARAMETERS)
############################################
resource "aws_glue_job" "flight_processing_job" {
  name     = "flight-performance-processing-job"
  role_arn = aws_iam_role.glue_job_role.arn

  command {
    name            = "glueetl"
    python_version  = "3"

    # Script dynamically referenced from S3
    script_location = "s3://${aws_s3_bucket.my_bucket.bucket}/${aws_s3_object.Glue_Job.key}"
  }

  glue_version      = "5.0"
  worker_type       = "G.1X"
  number_of_workers = 3

  default_arguments = {
    "--job-language" = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-continuous-log-filter"      = "true"
  }

  tags = {
    Project = "GraphDatabase"
    Env     = "Dev"
  }

  depends_on = [
    aws_s3_object.Glue_Job
  ]
}
