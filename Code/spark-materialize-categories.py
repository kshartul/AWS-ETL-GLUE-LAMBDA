import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from awsgluedq.transforms import EvaluateDataQuality

args = getResolvedOptions(sys.argv, ['JOB_NAME'])
sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

# Default ruleset used by all target nodes with data quality enabled
DEFAULT_DATA_QUALITY_RULESET = """
    Rules = [
        ColumnCount > 0
    ]
"""

# Script generated for node AWS Glue Data Catalog
AWSGlueDataCatalog_node1788327538698 = glueContext.create_dynamic_frame.from_catalog(database="db_youtube_cleansed", table_name="cleansed_statistics_reference_data", transformation_ctx="AWSGlueDataCatalog_node1788327538698")

# Script generated for node AWS Glue Data Catalog
AWSGlueDataCatalog_node1788327557353 = glueContext.create_dynamic_frame.from_catalog(database="db_youtube_cleansed", table_name="raw_statistics", transformation_ctx="AWSGlueDataCatalog_node1788327557353")

# Script generated for node Join
Join_node1788327627460 = Join.apply(frame1=AWSGlueDataCatalog_node1788327538698, frame2=AWSGlueDataCatalog_node1788327557353, keys1=["id"], keys2=["category_id"], transformation_ctx="Join_node1788327627460")

# Script generated for node Amazon S3
EvaluateDataQuality().process_rows(frame=Join_node1788327627460, ruleset=DEFAULT_DATA_QUALITY_RULESET, publishing_options={"dataQualityEvaluationContext": "EvaluateDataQuality_node1788327417267", "enableDataQualityResultsPublishing": True}, additional_options={"dataQualityResultsPublishing.strategy": "BEST_EFFORT", "observations.scope": "ALL"})
AmazonS3_node1788327938580 = glueContext.getSink(path="s3://bigdata-on-youtube-analytics-useast1-784184871882-dev/youtube/rpt_youtube_statistics_categories/", connection_type="s3", updateBehavior="UPDATE_IN_DATABASE", partitionKeys=["region", "id"], enableUpdateCatalog=True, transformation_ctx="AmazonS3_node1788327938580")
AmazonS3_node1788327938580.setCatalogInfo(catalogDatabase="db_youtube_analytics",catalogTableName="rpt_youtube_statistics_categories")
AmazonS3_node1788327938580.setFormat("glueparquet", compression="snappy")
AmazonS3_node1788327938580.writeFrame(Join_node1788327627460)
job.commit()