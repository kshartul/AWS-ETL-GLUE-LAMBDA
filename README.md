# AWS ETL Data Pipeline in Python on YouTube Data

<img width="1062" height="655" alt="image" src="https://github.com/user-attachments/assets/bf9030a0-78cd-415f-acde-62301eefef30" />

An end-to-end, serverless ETL pipeline built on AWS that ingests, cleanses, catalogs, transforms, and visualizes YouTube trending-video statistics — using **S3, Lambda, AWS Data Wrangler, Glue (Crawler + Spark Jobs + Studio), Athena, IAM, SNS, and QuickSight**, with infrastructure optionally automated via **Terraform**.


![Uploading Screenshot 2026-10-19 123208.png…]()

---

## 1. Business Overview

YouTube is one of the most visited platforms in the world, and companies frequently use it as a channel for data-driven ad campaigns. To plan an effective campaign, a business needs to understand:

- How videos can be categorized by comments and engagement statistics
- What factors drive a video's popularity

This project builds a pipeline to securely manage, streamline, and analyze structured (CSV) and semi-structured (JSON) YouTube video data by category and trending metrics — turning raw daily trending-video exports into query-ready, dashboard-ready analytics.

---

## 2. Dataset

- **Source:** Kaggle — Trending YouTube Video Statistics
- **Format:** One CSV file per region (e.g., US, GB, CA, DE, FR...) containing up to 200 daily trending videos, plus a companion **JSON file per region** holding `category_id` → category-name mappings.
- **Key fields:** video title, channel title, publish time, tags, views, likes, dislikes, description, comment count, category_id.

---

## 3. Architecture

```
                     ┌────────────────────────┐
                     │  Kaggle YouTube Dataset  │
                     │  (CSV per region +       │
                     │   JSON category files)   │
                     └────────────┬─────────────┘
                                  │ aws s3 cp
                                  ▼
                     ┌────────────────────────┐
                     │   S3 — Raw Bucket        │
                     │   raw_statistics/        │  (CSV + JSON landing zone)
                     └────────────┬─────────────┘
                                  │
                 ┌────────────────┴─────────────────┐
                 ▼                                   ▼
   ┌───────────────────────────┐        ┌─────────────────────────────┐
   │  AWS Glue Crawler          │        │  S3 Event → AWS Lambda       │
   │  (raw_statistics → Glue    │        │  (JSON → Parquet, using      │
   │   Data Catalog table)      │        │  AWS Data Wrangler + Pandas) │
   └──────────────┬─────────────┘        └───────────────┬──────────────┘
                  │                                       │
                  ▼                                       ▼
   ┌───────────────────────────┐        ┌─────────────────────────────┐
   │  Amazon Athena             │        │  S3 — Cleansed Bucket        │
   │  (SQL over raw CSV table)  │        │  (Parquet, partitioned)      │
   └─────────────────────────────┘        └───────────────┬──────────────┘
                                                            │ auto-cataloged
                                                            ▼
                                            ┌─────────────────────────────┐
                                            │  AWS Glue Data Catalog       │
                                            │  (cleansed database/table)   │
                                            └───────────────┬──────────────┘
                                                            │
                                                            ▼
                                            ┌─────────────────────────────┐
                                            │  AWS Glue Spark ETL Job       │
                                            │  (CSV → Parquet, schema       │
                                            │   updates, pushdown predicate)│
                                            └───────────────┬──────────────┘
                                                            │
                                                            ▼
                                            ┌─────────────────────────────┐
                                            │  AWS Glue Studio Job          │
                                            │  (join cleansed statistics    │
                                            │   with category reference,    │
                                            │   materialize view)           │
                                            └───────────────┬──────────────┘
                                                            │
                                                            ▼
                                            ┌─────────────────────────────┐
                                            │  S3 — Analytics/Reporting     │
                                            │  Bucket (materialized Parquet)│
                                            │  DB: db_youtube_analytics     │
                                            └───────────────┬──────────────┘
                                                            │
                                                            ▼
                                            ┌─────────────────────────────┐
                                            │  Amazon Athena (analytics DB) │
                                            └───────────────┬──────────────┘
                                                            │
                                                            ▼
                                            ┌─────────────────────────────┐
                                            │  Amazon QuickSight             │
                                            │  (BI dashboards)               │
                                            └─────────────────────────────┘

Cross-cutting: AWS IAM (users, roles, policies, MFA) · Amazon CloudWatch (Lambda/Glue metrics & logs)
             · Amazon SNS (pipeline alerts) · Terraform (automated AWS resource provisioning)
```

### Data flow, step by step

1. **Ingest** — Raw CSV (video statistics) and JSON (category reference) files are uploaded from the Kaggle dataset into an S3 **raw** bucket via the AWS CLI.
2. **Catalog raw data** — An **AWS Glue Crawler** scans the `raw_statistics` prefix in S3 and creates/updates a table in the **Glue Data Catalog**, making the raw CSV data immediately queryable via **Athena**.
3. **JSON → Parquet (Lambda path)** — An S3 `ObjectCreated` event (test event: `s3-json-youtube-put`) triggers an **AWS Lambda** function that:
   - Reads the incoming JSON category file using **Pandas**.
   - Flattens/normalizes it into a DataFrame.
   - Writes it out as **Parquet** to the cleansed S3 bucket using the **AWS Data Wrangler** Lambda layer.
   - Simultaneously updates the **Glue Data Catalog** with the new Parquet table/partition.
4. **CSV → Parquet (Glue Spark path)** — A second **S3 Crawler** catalogs the raw CSV `raw_statistics` data; an **AWS Glue Spark ETL job** then reads it, applies schema updates and a **pushdown predicate** (for partition pruning), and writes cleansed Parquet output to S3.
5. **Automation trigger** — An **S3 trigger** is attached to the Lambda function so any new incoming JSON file (e.g., new category data) is automatically processed end-to-end without manual intervention.
6. **Materialize / Join (Glue Studio)** — A **Glue Studio job** (`bigdata-on-youtube-spark-materialize-categories`) joins the cleansed video-statistics Parquet data with the cleansed category-reference Parquet data and writes a materialized view to an **analytics** S3 bucket, cataloged under the `db_youtube_analytics` database.
7. **Query** — **Amazon Athena** is used throughout to run SQL against both the raw and cleansed/analytics Glue Catalog tables.
8. **Visualize** — **Amazon QuickSight** connects to the Athena analytics database as its data source; dashboards are built on top to answer questions like "which categories trend most" or "what drives video popularity."
9. **Monitor & alert** — **CloudWatch** metrics track Lambda/Glue job health; **Amazon SNS** is used to generate alerts on pipeline issues.
10. **Provision (optional)** — **Terraform** scripts automate the creation of all AWS resources above in a single execution, avoiding manual UI configuration and reducing setup errors (see `terraform/instructions.md`).

---

## 4. Tech Stack

| Category    | Technologies                                                        |
|-------------|----------------------------------------------------------------------|
| Languages   | Python 3, SQL                                                        |
| Compute     | AWS Lambda (with AWS Data Wrangler layer), AWS Glue Spark ETL Jobs, AWS Glue Studio |
| Storage     | Amazon S3 (raw → cleansed → analytics/reporting layers)              |
| Cataloging  | AWS Glue Data Catalog, AWS Glue Crawler                               |
| Query / BI  | Amazon Athena, Amazon QuickSight                                      |
| Security    | AWS IAM (users, roles, policies, MFA)                                 |
| Monitoring  | Amazon CloudWatch, Amazon SNS                                         |
| IaC         | Terraform                                                             |

---

## 5. Project Structure

```
aws-etl-data-pipeline-python-youtube/
├── README.md
├── data/
│   └── Data.zip                       # Kaggle YouTube dataset (CSV + JSON per region)
├── lambda/
│   ├── json_to_parquet_lambda.py      # Extracts JSON, writes Parquet via AWS Data Wrangler
│   ├── layers/
│   │   └── awswrangler-layer.zip      # AWS Data Wrangler Lambda layer
│   └── test_events/
│       └── s3-json-youtube-put.json   # Sample S3 event for local/test invocation
├── glue/
│   ├── crawlers/
│   │   ├── raw_statistics_crawler.json
│   │   └── cleansed_crawler.json
│   ├── jobs/
│   │   ├── csv_to_parquet_spark_job.py         # Glue Spark ETL job (schema update + pushdown predicate)
│   │   └── bigdata-on-youtube-spark-materialize-categories.py  # Glue Studio join/materialize job
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── instructions.md                # Step-by-step Terraform execution guide
├── iam/
│   ├── lambda-execution-policy.json
│   └── glue-service-role-policy.json
└── quicksight/
    └── dashboard-notes.md
```

---

## 6. Prerequisites

- An AWS account with permissions to create S3, IAM, Lambda, Glue, Athena, and QuickSight resources.
- AWS CLI installed and configured (`aws configure`), with an IAM user that has MFA enabled and the necessary permissions.
- Python 3.9+ and `pip`.
- Terraform (optional, for automated provisioning).
- The Kaggle YouTube trending-video dataset downloaded locally (`Data.zip`).

---

## 7. Setup & Execution

### 7.1 Create the IAM user and configure the CLI

1. Create an IAM user/admin in the AWS Console, attach the required permissions, and enable an MFA device.
2. Install and configure the AWS CLI with that user's access key/secret:
   ```bash
   aws configure
   ```

### 7.2 Create the S3 buckets

```bash
aws s3 mb s3://bigdata-on-youtube-raw-useast1-<account-id>-dev
aws s3 mb s3://bigdata-on-youtube-cleansed-useast1-<account-id>-dev
aws s3 mb s3://bigdata-on-youtube-analytics-useast1-<account-id>-dev
```

### 7.3 Load the raw dataset into S3

```bash
unzip data/Data.zip -d ./data/extracted
aws s3 cp ./data/extracted/ s3://bigdata-on-youtube-raw-useast1-<account-id>-dev/raw_statistics/ --recursive
```

### 7.4 Create the Glue Data Catalog and raw crawler

1. In AWS Glue, create a database (e.g., `db_youtube_raw`).
2. Create and run a **Glue Crawler** pointed at `s3://.../raw_statistics/` to populate the raw table.
3. Set up an Athena query result location (an S3 bucket/prefix) so you can start querying the raw table immediately.

### 7.5 Build and deploy the Lambda function (JSON → Parquet)

1. Package `lambda/json_to_parquet_lambda.py` with the **AWS Data Wrangler** Lambda layer attached.
2. Create the function in AWS Lambda; use `lambda/test_events/s3-json-youtube-put.json` to configure and run a test event.
3. Add an **S3 trigger** on the raw bucket (JSON prefix) so new category files are processed automatically.
4. Verify the function writes Parquet to the cleansed bucket and updates the Glue Data Catalog (e.g., database `db_youtube_cleansed`, table `cleansed_statistics_reference_data`).

### 7.6 Build the Glue Spark ETL job (CSV → Parquet)

1. In AWS Glue Studio, create a new Spark job (`csv_to_parquet_spark_job.py`) reading from the raw CSV table.
2. Configure a **pushdown predicate** to prune partitions and reduce scan cost.
3. Update the target schema/data types as needed and run the job to produce cleansed Parquet output.
4. Run a second crawler over the cleansed output to keep the Glue Catalog current.

### 7.7 Materialize the analytics layer (Glue Studio join)

1. Create a new database, e.g. `db_youtube_analytics`.
2. Create the Glue Studio job `bigdata-on-youtube-spark-materialize-categories` to join cleansed video statistics with cleansed category reference data.
3. Write the joined output to the analytics S3 bucket; confirm it's queryable via Athena.
4. Automate this workflow so it runs whenever new cleansed data lands (Glue workflow/trigger).

### 7.8 Visualize in QuickSight

1. In Amazon QuickSight, create a new dataset using the `db_youtube_analytics` Athena database as the source.
2. Build dashboards/visuals on top (e.g., trending categories over time, views vs. engagement).

### 7.9 (Optional) Automate provisioning with Terraform

```bash
cd terraform
terraform init
terraform plan
terraform apply
```
Follow `terraform/instructions.md` for account-specific variables (region, bucket names, account ID) before applying.

---

## 8. Monitoring & Alerting

- **CloudWatch** — track Lambda invocation errors/duration and Glue job run status/metrics.
- **Amazon SNS** — configure topics/subscriptions to alert on pipeline failures (e.g., Lambda errors, failed Glue job runs).

---

## 9. Key Concepts Covered

- Data lake / lakehouse architecture on S3
- IAM users, roles, and least-privilege policies
- Event-driven ETL with Lambda + S3 triggers
- AWS Data Wrangler for Pandas ↔ S3/Glue integration
- Glue Crawlers, Glue Data Catalog, Glue Spark ETL jobs, and Glue Studio visual ETL
- Pushdown predicates and schema evolution in Glue
- Serverless SQL analytics with Athena
- BI dashboarding with QuickSight
- Infrastructure as Code with Terraform

---

## 10. Notes

- Adjust all bucket names, database names, account IDs, and regions to match your own AWS environment before running.
- Clean up S3 buckets, Lambda functions, Glue jobs/crawlers, and QuickSight resources when done to avoid ongoing AWS charges.
