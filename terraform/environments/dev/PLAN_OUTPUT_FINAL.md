# Plan de despliegue del entorno `dev` -- Proyecto Final

Salida literal de `terraform plan` sobre el entorno completo, partiendo de
cero. Cierra con **`Plan: 45 to add, 0 to change, 0 to destroy`**, que es el
recuento de recursos citado en la seccion 5 del DAAT
(`docs/Andres_Capo_Capstone_RealTime.pdf`).

El resultado del `apply` correspondiente, y la convergencia a `0 added,
0 changed` en la ejecucion siguiente, estan transcritos en esa misma seccion.

```text
Warning: Deprecated Parameter

The parameter "dynamodb_table" is deprecated. Use parameter "use_lockfile" instead.
Acquiring state lock. This may take a few moments...
module.redshift.data.aws_kms_alias.kinesis: Reading...
module.kinesis.data.aws_caller_identity.current: Reading...
module.redshift.data.aws_caller_identity.current: Reading...
module.glue.data.aws_caller_identity.current: Reading...
module.kinesis.data.aws_region.current: Reading...
module.kinesis.data.aws_region.current: Read complete after 0s [id=us-east-1]
module.identity.data.aws_region.current: Reading...
data.aws_caller_identity.current: Reading...
module.identity.data.aws_region.current: Read complete after 0s [id=us-east-1]
module.identity.data.aws_caller_identity.current: Reading...
module.redshift.data.aws_caller_identity.current: Read complete after 0s [id=010798385513]
module.glue.data.aws_caller_identity.current: Read complete after 0s [id=010798385513]
module.kinesis.data.aws_caller_identity.current: Read complete after 0s [id=010798385513]
data.aws_caller_identity.current: Read complete after 0s [id=010798385513]
module.identity.data.aws_caller_identity.current: Read complete after 0s [id=010798385513]
module.redshift.data.aws_kms_alias.kinesis: Read complete after 0s [id=arn:aws:kms:us-east-1:010798385513:alias/aws/kinesis]

Terraform used the selected providers to generate the following execution
plan. Resource actions are indicated with the following symbols:
  + create

Terraform will perform the following actions:

  # aws_s3_bucket.raw_bucket will be created
  + resource "aws_s3_bucket" "raw_bucket" {
      + acceleration_status         = (known after apply)
      + acl                         = (known after apply)
      + arn                         = (known after apply)
      + bucket                      = "datalake-raw-dev-010798385513"
      + bucket_domain_name          = (known after apply)
      + bucket_prefix               = (known after apply)
      + bucket_regional_domain_name = (known after apply)
      + force_destroy               = true
      + hosted_zone_id              = (known after apply)
      + id                          = (known after apply)
      + object_lock_enabled         = (known after apply)
      + policy                      = (known after apply)
      + region                      = (known after apply)
      + request_payer               = (known after apply)
      + tags                        = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "Data Lake Raw Bucket"
        }
      + tags_all                    = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "Data Lake Raw Bucket"
        }
      + website_domain              = (known after apply)
      + website_endpoint            = (known after apply)

      + cors_rule (known after apply)

      + grant (known after apply)

      + lifecycle_rule (known after apply)

      + logging (known after apply)

      + object_lock_configuration (known after apply)

      + replication_configuration (known after apply)

      + server_side_encryption_configuration (known after apply)

      + versioning (known after apply)

      + website (known after apply)
    }

  # aws_s3_bucket_versioning.raw_bucket_versioning will be created
  + resource "aws_s3_bucket_versioning" "raw_bucket_versioning" {
      + bucket = (known after apply)
      + id     = (known after apply)

      + versioning_configuration {
          + mfa_delete = (known after apply)
          + status     = "Enabled"
        }
    }

  # module.flink.aws_cloudwatch_log_group.flink_log_group will be created
  + resource "aws_cloudwatch_log_group" "flink_log_group" {
      + arn               = (known after apply)
      + id                = (known after apply)
      + log_group_class   = (known after apply)
      + name              = "/aws/kinesisanalytics/clicks-processor-dev"
      + name_prefix       = (known after apply)
      + retention_in_days = 7
      + skip_destroy      = false
      + tags              = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
        }
      + tags_all          = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
        }
    }

  # module.flink.aws_cloudwatch_log_stream.flink_log_stream will be created
  + resource "aws_cloudwatch_log_stream" "flink_log_stream" {
      + arn            = (known after apply)
      + id             = (known after apply)
      + log_group_name = "/aws/kinesisanalytics/clicks-processor-dev"
      + name           = "flink-log-stream"
    }

  # module.flink.aws_iam_role.flink_execution_role will be created
  + resource "aws_iam_role" "flink_execution_role" {
      + arn                   = (known after apply)
      + assume_role_policy    = jsonencode(
            {
              + Statement = [
                  + {
                      + Action    = "sts:AssumeRole"
                      + Effect    = "Allow"
                      + Principal = {
                          + Service = "kinesisanalytics.amazonaws.com"
                        }
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + create_date           = (known after apply)
      + force_detach_policies = false
      + id                    = (known after apply)
      + managed_policy_arns   = (known after apply)
      + max_session_duration  = 3600
      + name                  = "flink-execution-dev"
      + name_prefix           = (known after apply)
      + path                  = "/"
      + tags                  = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "flink-execution-dev"
        }
      + tags_all              = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "flink-execution-dev"
        }
      + unique_id             = (known after apply)

      + inline_policy (known after apply)
    }

  # module.flink.aws_iam_role_policy.flink_cloudwatch_logs will be created
  + resource "aws_iam_role_policy" "flink_cloudwatch_logs" {
      + id          = (known after apply)
      + name        = "flink-cloudwatch-logs-policy"
      + name_prefix = (known after apply)
      + policy      = (known after apply)
      + role        = (known after apply)
    }

  # module.flink.aws_iam_role_policy.flink_kinesis_read will be created
  + resource "aws_iam_role_policy" "flink_kinesis_read" {
      + id          = (known after apply)
      + name        = "flink-kinesis-read-policy"
      + name_prefix = (known after apply)
      + policy      = (known after apply)
      + role        = (known after apply)
    }

  # module.flink.aws_iam_role_policy.flink_s3_checkpoints will be created
  + resource "aws_iam_role_policy" "flink_s3_checkpoints" {
      + id          = (known after apply)
      + name        = "flink-s3-checkpoints-policy"
      + name_prefix = (known after apply)
      + policy      = (known after apply)
      + role        = (known after apply)
    }

  # module.flink.aws_iam_role_policy.flink_s3_code_read will be created
  + resource "aws_iam_role_policy" "flink_s3_code_read" {
      + id          = (known after apply)
      + name        = "flink-s3-code-read-policy"
      + name_prefix = (known after apply)
      + policy      = (known after apply)
      + role        = (known after apply)
    }

  # module.flink.aws_kinesisanalyticsv2_application.clicks_processor[0] will be created
  + resource "aws_kinesisanalyticsv2_application" "clicks_processor" {
      + application_mode       = (known after apply)
      + arn                    = (known after apply)
      + create_timestamp       = (known after apply)
      + id                     = (known after apply)
      + last_update_timestamp  = (known after apply)
      + name                   = "clicks-processor-dev"
      + runtime_environment    = "FLINK-1_15"
      + service_execution_role = (known after apply)
      + status                 = (known after apply)
      + tags                   = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "clicks-processor-dev"
        }
      + tags_all               = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "clicks-processor-dev"
        }
      + version_id             = (known after apply)

      + application_configuration {
          + application_code_configuration {
              + code_content_type = "ZIPFILE"

              + code_content {
                  + s3_content_location {
                      + bucket_arn = (known after apply)
                      + file_key   = "flink/clicks_processor.zip"
                    }
                }
            }
          + application_snapshot_configuration (known after apply)
          + environment_properties {
              + property_group {
                  + property_group_id = "consumer.config"
                  + property_map      = {
                      + "aws.region"           = "us-east-1"
                      + "flink.stream.initpos" = "LATEST"
                      + "input.stream.name"    = "clicks-ecommerce"
                    }
                }
              + property_group {
                  + property_group_id = "kinesis.analytics.flink.run.options"
                  + property_map      = {
                      + "python" = "clicks_processor.py"
                    }
                }
            }
          + flink_application_configuration {
              + checkpoint_configuration {
                  + checkpoint_interval           = 60000
                  + checkpointing_enabled         = true
                  + configuration_type            = "CUSTOM"
                  + min_pause_between_checkpoints = 5000
                }
              + monitoring_configuration {
                  + configuration_type = "CUSTOM"
                  + log_level          = "INFO"
                  + metrics_level      = "APPLICATION"
                }
              + parallelism_configuration {
                  + auto_scaling_enabled = false
                  + configuration_type   = "CUSTOM"
                  + parallelism          = 1
                  + parallelism_per_kpu  = 1
                }
            }
          + run_configuration (known after apply)
        }

      + cloudwatch_logging_options {
          + cloudwatch_logging_option_id = (known after apply)
          + log_stream_arn               = (known after apply)
        }
    }

  # module.flink.aws_s3_object.app_artifact[0] will be created
  + resource "aws_s3_object" "app_artifact" {
      + acl                    = (known after apply)
      + arn                    = (known after apply)
      + bucket                 = "datalake-raw-dev-010798385513"
      + bucket_key_enabled     = (known after apply)
      + checksum_crc32         = (known after apply)
      + checksum_crc32c        = (known after apply)
      + checksum_crc64nvme     = (known after apply)
      + checksum_sha1          = (known after apply)
      + checksum_sha256        = (known after apply)
      + content_type           = (known after apply)
      + etag                   = "7e224f4f5b66025630e4c1deaa526556"
      + force_destroy          = false
      + id                     = (known after apply)
      + key                    = "flink/clicks_processor.zip"
      + kms_key_id             = (known after apply)
      + server_side_encryption = (known after apply)
      + source                 = "./../../../flink-app/clicks_processor.zip"
      + storage_class          = (known after apply)
      + tags                   = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
        }
      + tags_all               = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
        }
      + version_id             = (known after apply)
    }

  # module.glue.aws_dynamodb_table.iceberg_glue_lock will be created
  + resource "aws_dynamodb_table" "iceberg_glue_lock" {
      + arn              = (known after apply)
      + billing_mode     = "PAY_PER_REQUEST"
      + hash_key         = "entityId"
      + id               = (known after apply)
      + name             = "iceberg_glue_lock"
      + read_capacity    = (known after apply)
      + stream_arn       = (known after apply)
      + stream_label     = (known after apply)
      + stream_view_type = (known after apply)
      + tags             = {
          + "ManagedBy" = "Terraform"
          + "Name"      = "iceberg-glue-lock"
        }
      + tags_all         = {
          + "ManagedBy" = "Terraform"
          + "Name"      = "iceberg-glue-lock"
        }
      + write_capacity   = (known after apply)

      + attribute {
          + name = "entityId"
          + type = "S"
        }

      + point_in_time_recovery (known after apply)

      + server_side_encryption (known after apply)

      + ttl (known after apply)
    }

  # module.glue.aws_glue_catalog_database.lakehouse_db will be created
  + resource "aws_glue_catalog_database" "lakehouse_db" {
      + arn          = (known after apply)
      + catalog_id   = (known after apply)
      + description  = "Cat├ílogo de tablas Iceberg para el pipeline de clicks de e-commerce"
      + id           = (known after apply)
      + location_uri = (known after apply)
      + name         = "lakehouse_db"
      + tags_all     = (known after apply)

      + create_table_default_permission (known after apply)
    }

  # module.glue.aws_iam_role_policy.flink_glue_access will be created
  + resource "aws_iam_role_policy" "flink_glue_access" {
      + id          = (known after apply)
      + name        = "flink-glue-access-policy"
      + name_prefix = (known after apply)
      + policy      = jsonencode(
            {
              + Statement = [
                  + {
                      + Action   = [
                          + "glue:GetDatabase",
                          + "glue:GetTable",
                          + "glue:GetTables",
                          + "glue:CreateTable",
                          + "glue:UpdateTable",
                          + "glue:DeleteTable",
                          + "glue:GetPartitions",
                          + "glue:BatchCreatePartition",
                        ]
                      + Effect   = "Allow"
                      + Resource = [
                          + "arn:aws:glue:us-east-1:010798385513:catalog",
                          + "arn:aws:glue:us-east-1:010798385513:database/lakehouse_db",
                          + "arn:aws:glue:us-east-1:010798385513:table/lakehouse_db/*",
                        ]
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + role        = "flink-execution-dev"
    }

  # module.glue.aws_iam_role_policy.flink_iceberg_lock_access will be created
  + resource "aws_iam_role_policy" "flink_iceberg_lock_access" {
      + id          = (known after apply)
      + name        = "flink-iceberg-lock-policy"
      + name_prefix = (known after apply)
      + policy      = (known after apply)
      + role        = "flink-execution-dev"
    }

  # module.glue.aws_iam_role_policy.flink_lakehouse_s3_access will be created
  + resource "aws_iam_role_policy" "flink_lakehouse_s3_access" {
      + id          = (known after apply)
      + name        = "flink-lakehouse-s3-access-policy"
      + name_prefix = (known after apply)
      + policy      = (known after apply)
      + role        = "flink-execution-dev"
    }

  # module.identity.aws_iam_policy.control_plane_audit_policy will be created
  + resource "aws_iam_policy" "control_plane_audit_policy" {
      + arn              = (known after apply)
      + attachment_count = (known after apply)
      + description      = "Permisos de solo lectura para auditor├¡a del plano de control"
      + id               = (known after apply)
      + name             = "policy-control-plane-audit-dev"
      + name_prefix      = (known after apply)
      + path             = "/"
      + policy           = (known after apply)
      + policy_id        = (known after apply)
      + tags_all         = (known after apply)
    }

  # module.identity.aws_iam_policy.strict_s3_policy will be created
  + resource "aws_iam_policy" "strict_s3_policy" {
      + arn              = (known after apply)
      + attachment_count = (known after apply)
      + description      = "Permisos S3 acotados por prefijo sin comodines globales"
      + id               = (known after apply)
      + name             = "policy-s3-restricted-dev"
      + name_prefix      = (known after apply)
      + path             = "/"
      + policy           = (known after apply)
      + policy_id        = (known after apply)
      + tags_all         = (known after apply)
    }

  # module.identity.aws_iam_role.control_plane_audit_role will be created
  + resource "aws_iam_role" "control_plane_audit_role" {
      + arn                   = (known after apply)
      + assume_role_policy    = jsonencode(
            {
              + Statement = [
                  + {
                      + Action    = "sts:AssumeRole"
                      + Effect    = "Allow"
                      + Principal = {
                          + Service = "lambda.amazonaws.com"
                        }
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + create_date           = (known after apply)
      + force_detach_policies = false
      + id                    = (known after apply)
      + managed_policy_arns   = (known after apply)
      + max_session_duration  = 3600
      + name                  = "role-control-plane-audit-dev"
      + name_prefix           = (known after apply)
      + path                  = "/"
      + tags                  = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Purpose"     = "Audit"
        }
      + tags_all              = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Purpose"     = "Audit"
        }
      + unique_id             = (known after apply)

      + inline_policy (known after apply)
    }

  # module.identity.aws_iam_role.data_processing_role will be created
  + resource "aws_iam_role" "data_processing_role" {
      + arn                   = (known after apply)
      + assume_role_policy    = jsonencode(
            {
              + Statement = [
                  + {
                      + Action    = "sts:AssumeRole"
                      + Effect    = "Allow"
                      + Principal = {
                          + Service = [
                              + "lambda.amazonaws.com",
                              + "kinesisanalytics.amazonaws.com",
                            ]
                        }
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + create_date           = (known after apply)
      + force_detach_policies = false
      + id                    = (known after apply)
      + managed_policy_arns   = (known after apply)
      + max_session_duration  = 3600
      + name                  = "role-data-processing-dev"
      + name_prefix           = (known after apply)
      + path                  = "/"
      + tags                  = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
        }
      + tags_all              = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
        }
      + unique_id             = (known after apply)

      + inline_policy (known after apply)
    }

  # module.identity.aws_iam_role_policy_attachment.attach_audit_policy will be created
  + resource "aws_iam_role_policy_attachment" "attach_audit_policy" {
      + id         = (known after apply)
      + policy_arn = (known after apply)
      + role       = "role-control-plane-audit-dev"
    }

  # module.identity.aws_iam_role_policy_attachment.attach_data_policy will be created
  + resource "aws_iam_role_policy_attachment" "attach_data_policy" {
      + id         = (known after apply)
      + policy_arn = (known after apply)
      + role       = "role-data-processing-dev"
    }

  # module.kinesis.aws_cloudwatch_log_group.firehose will be created
  + resource "aws_cloudwatch_log_group" "firehose" {
      + arn               = (known after apply)
      + id                = (known after apply)
      + log_group_class   = (known after apply)
      + name              = "/aws/kinesis-firehose/clicks-ecommerce"
      + name_prefix       = (known after apply)
      + retention_in_days = 7
      + skip_destroy      = false
      + tags              = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
        }
      + tags_all          = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
        }
    }

  # module.kinesis.aws_cloudwatch_metric_alarm.iterator_age will be created
  + resource "aws_cloudwatch_metric_alarm" "iterator_age" {
      + actions_enabled                       = true
      + alarm_description                     = "El consumidor se esta atrasando respecto de la punta del shard (backpressure)"
      + alarm_name                            = "kinesis-iterator-age-clicks-ecommerce"
      + arn                                   = (known after apply)
      + comparison_operator                   = "GreaterThanThreshold"
      + dimensions                            = {
          + "StreamName" = "clicks-ecommerce"
        }
      + evaluate_low_sample_count_percentiles = (known after apply)
      + evaluation_periods                    = 2
      + id                                    = (known after apply)
      + metric_name                           = "GetRecords.IteratorAgeMilliseconds"
      + namespace                             = "AWS/Kinesis"
      + period                                = 60
      + statistic                             = "Maximum"
      + tags                                  = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
        }
      + tags_all                              = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
        }
      + threshold                             = 60000
      + treat_missing_data                    = "notBreaching"
    }

  # module.kinesis.aws_cloudwatch_metric_alarm.read_throttle will be created
  + resource "aws_cloudwatch_metric_alarm" "read_throttle" {
      + actions_enabled                       = true
      + alarm_description                     = "Lecturas excediendo la capacidad provisionada del stream"
      + alarm_name                            = "kinesis-read-throttled-clicks-ecommerce"
      + arn                                   = (known after apply)
      + comparison_operator                   = "GreaterThanThreshold"
      + dimensions                            = {
          + "StreamName" = "clicks-ecommerce"
        }
      + evaluate_low_sample_count_percentiles = (known after apply)
      + evaluation_periods                    = 1
      + id                                    = (known after apply)
      + metric_name                           = "ReadProvisionedThroughputExceeded"
      + namespace                             = "AWS/Kinesis"
      + period                                = 60
      + statistic                             = "Sum"
      + tags_all                              = (known after apply)
      + threshold                             = 0
      + treat_missing_data                    = "missing"
    }

  # module.kinesis.aws_cloudwatch_metric_alarm.write_throttle will be created
  + resource "aws_cloudwatch_metric_alarm" "write_throttle" {
      + actions_enabled                       = true
      + alarm_description                     = "Escrituras excediendo la capacidad provisionada del stream"
      + alarm_name                            = "kinesis-write-throttled-clicks-ecommerce"
      + arn                                   = (known after apply)
      + comparison_operator                   = "GreaterThanThreshold"
      + dimensions                            = {
          + "StreamName" = "clicks-ecommerce"
        }
      + evaluate_low_sample_count_percentiles = (known after apply)
      + evaluation_periods                    = 1
      + id                                    = (known after apply)
      + metric_name                           = "WriteProvisionedThroughputExceeded"
      + namespace                             = "AWS/Kinesis"
      + period                                = 60
      + statistic                             = "Sum"
      + tags_all                              = (known after apply)
      + threshold                             = 0
      + treat_missing_data                    = "missing"
    }

  # module.kinesis.aws_iam_role.firehose will be created
  + resource "aws_iam_role" "firehose" {
      + arn                   = (known after apply)
      + assume_role_policy    = jsonencode(
            {
              + Statement = [
                  + {
                      + Action    = "sts:AssumeRole"
                      + Effect    = "Allow"
                      + Principal = {
                          + Service = "firehose.amazonaws.com"
                        }
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + create_date           = (known after apply)
      + force_detach_policies = false
      + id                    = (known after apply)
      + managed_policy_arns   = (known after apply)
      + max_session_duration  = 3600
      + name                  = "firehose-kinesis-dev"
      + name_prefix           = (known after apply)
      + path                  = "/"
      + tags_all              = (known after apply)
      + unique_id             = (known after apply)

      + inline_policy (known after apply)
    }

  # module.kinesis.aws_iam_role_policy.firehose will be created
  + resource "aws_iam_role_policy" "firehose" {
      + id          = (known after apply)
      + name        = "firehose-kinesis-policy"
      + name_prefix = (known after apply)
      + policy      = (known after apply)
      + role        = (known after apply)
    }

  # module.kinesis.aws_kinesis_firehose_delivery_stream.main will be created
  + resource "aws_kinesis_firehose_delivery_stream" "main" {
      + arn            = (known after apply)
      + destination    = "extended_s3"
      + destination_id = (known after apply)
      + id             = (known after apply)
      + name           = "ingesta-clicks-ecommerce"
      + tags           = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "ingesta-clicks-ecommerce"
        }
      + tags_all       = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "ingesta-clicks-ecommerce"
        }
      + version_id     = (known after apply)

      + extended_s3_configuration {
          + bucket_arn          = "arn:aws:s3:::datalake-raw-dev-010798385513"
          + buffering_interval  = 60
          + buffering_size      = 5
          + compression_format  = "GZIP"
          + custom_time_zone    = "UTC"
          + error_output_prefix = "ingesta-errores/!{firehose:error-output-type}/year=!{timestamp:yyyy}/"
          + prefix              = "ingesta/year=!{timestamp:yyyy}/"
          + role_arn            = (known after apply)
          + s3_backup_mode      = "Disabled"

          + cloudwatch_logging_options {
              + enabled         = true
              + log_group_name  = "/aws/kinesis-firehose/clicks-ecommerce"
              + log_stream_name = "S3Delivery"
            }
        }

      + kinesis_source_configuration {
          + kinesis_stream_arn = (known after apply)
          + role_arn           = (known after apply)
        }
    }

  # module.kinesis.aws_kinesis_stream.main will be created
  + resource "aws_kinesis_stream" "main" {
      + arn                       = (known after apply)
      + encryption_type           = "KMS"
      + enforce_consumer_deletion = false
      + id                        = (known after apply)
      + kms_key_id                = "alias/aws/kinesis"
      + name                      = "clicks-ecommerce"
      + retention_period          = 24
      + shard_count               = 2
      + tags                      = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "clicks-ecommerce"
        }
      + tags_all                  = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "clicks-ecommerce"
        }

      + stream_mode_details (known after apply)
    }

  # module.network.aws_route_table.private_rt will be created
  + resource "aws_route_table" "private_rt" {
      + arn              = (known after apply)
      + id               = (known after apply)
      + owner_id         = (known after apply)
      + propagating_vgws = (known after apply)
      + route            = (known after apply)
      + tags             = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "rt-private-dev"
        }
      + tags_all         = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "rt-private-dev"
        }
      + vpc_id           = (known after apply)
    }

  # module.network.aws_route_table_association.private_assoc[0] will be created
  + resource "aws_route_table_association" "private_assoc" {
      + id             = (known after apply)
      + route_table_id = (known after apply)
      + subnet_id      = (known after apply)
    }

  # module.network.aws_route_table_association.private_assoc[1] will be created
  + resource "aws_route_table_association" "private_assoc" {
      + id             = (known after apply)
      + route_table_id = (known after apply)
      + subnet_id      = (known after apply)
    }

  # module.network.aws_route_table_association.private_assoc[2] will be created
  + resource "aws_route_table_association" "private_assoc" {
      + id             = (known after apply)
      + route_table_id = (known after apply)
      + subnet_id      = (known after apply)
    }

  # module.network.aws_subnet.private_subnets[0] will be created
  + resource "aws_subnet" "private_subnets" {
      + arn                                            = (known after apply)
      + assign_ipv6_address_on_creation                = false
      + availability_zone                              = "us-east-1a"
      + availability_zone_id                           = (known after apply)
      + cidr_block                                     = "10.0.1.0/24"
      + enable_dns64                                   = false
      + enable_resource_name_dns_a_record_on_launch    = false
      + enable_resource_name_dns_aaaa_record_on_launch = false
      + id                                             = (known after apply)
      + ipv6_cidr_block_association_id                 = (known after apply)
      + ipv6_native                                    = false
      + map_public_ip_on_launch                        = false
      + owner_id                                       = (known after apply)
      + private_dns_hostname_type_on_launch            = (known after apply)
      + tags                                           = {
          + "Environment" = "dev"
          + "Layer"       = "PrivateData"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "subnet-private-dev-1"
        }
      + tags_all                                       = {
          + "Environment" = "dev"
          + "Layer"       = "PrivateData"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "subnet-private-dev-1"
        }
      + vpc_id                                         = (known after apply)
    }

  # module.network.aws_subnet.private_subnets[1] will be created
  + resource "aws_subnet" "private_subnets" {
      + arn                                            = (known after apply)
      + assign_ipv6_address_on_creation                = false
      + availability_zone                              = "us-east-1b"
      + availability_zone_id                           = (known after apply)
      + cidr_block                                     = "10.0.2.0/24"
      + enable_dns64                                   = false
      + enable_resource_name_dns_a_record_on_launch    = false
      + enable_resource_name_dns_aaaa_record_on_launch = false
      + id                                             = (known after apply)
      + ipv6_cidr_block_association_id                 = (known after apply)
      + ipv6_native                                    = false
      + map_public_ip_on_launch                        = false
      + owner_id                                       = (known after apply)
      + private_dns_hostname_type_on_launch            = (known after apply)
      + tags                                           = {
          + "Environment" = "dev"
          + "Layer"       = "PrivateData"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "subnet-private-dev-2"
        }
      + tags_all                                       = {
          + "Environment" = "dev"
          + "Layer"       = "PrivateData"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "subnet-private-dev-2"
        }
      + vpc_id                                         = (known after apply)
    }

  # module.network.aws_subnet.private_subnets[2] will be created
  + resource "aws_subnet" "private_subnets" {
      + arn                                            = (known after apply)
      + assign_ipv6_address_on_creation                = false
      + availability_zone                              = "us-east-1c"
      + availability_zone_id                           = (known after apply)
      + cidr_block                                     = "10.0.3.0/24"
      + enable_dns64                                   = false
      + enable_resource_name_dns_a_record_on_launch    = false
      + enable_resource_name_dns_aaaa_record_on_launch = false
      + id                                             = (known after apply)
      + ipv6_cidr_block_association_id                 = (known after apply)
      + ipv6_native                                    = false
      + map_public_ip_on_launch                        = false
      + owner_id                                       = (known after apply)
      + private_dns_hostname_type_on_launch            = (known after apply)
      + tags                                           = {
          + "Environment" = "dev"
          + "Layer"       = "PrivateData"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "subnet-private-dev-3"
        }
      + tags_all                                       = {
          + "Environment" = "dev"
          + "Layer"       = "PrivateData"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "subnet-private-dev-3"
        }
      + vpc_id                                         = (known after apply)
    }

  # module.network.aws_vpc.data_vpc will be created
  + resource "aws_vpc" "data_vpc" {
      + arn                                  = (known after apply)
      + cidr_block                           = "10.0.0.0/16"
      + default_network_acl_id               = (known after apply)
      + default_route_table_id               = (known after apply)
      + default_security_group_id            = (known after apply)
      + dhcp_options_id                      = (known after apply)
      + enable_dns_hostnames                 = true
      + enable_dns_support                   = true
      + enable_network_address_usage_metrics = (known after apply)
      + id                                   = (known after apply)
      + instance_tenancy                     = "default"
      + ipv6_association_id                  = (known after apply)
      + ipv6_cidr_block                      = (known after apply)
      + ipv6_cidr_block_network_border_group = (known after apply)
      + main_route_table_id                  = (known after apply)
      + owner_id                             = (known after apply)
      + tags                                 = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "vpc-data-dev"
        }
      + tags_all                             = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "vpc-data-dev"
        }
    }

  # module.network.aws_vpc_endpoint.s3_endpoint will be created
  + resource "aws_vpc_endpoint" "s3_endpoint" {
      + arn                   = (known after apply)
      + cidr_blocks           = (known after apply)
      + dns_entry             = (known after apply)
      + id                    = (known after apply)
      + ip_address_type       = (known after apply)
      + network_interface_ids = (known after apply)
      + owner_id              = (known after apply)
      + policy                = (known after apply)
      + prefix_list_id        = (known after apply)
      + private_dns_enabled   = (known after apply)
      + requester_managed     = (known after apply)
      + route_table_ids       = (known after apply)
      + security_group_ids    = (known after apply)
      + service_name          = "com.amazonaws.us-east-1.s3"
      + service_region        = (known after apply)
      + state                 = (known after apply)
      + subnet_ids            = (known after apply)
      + tags                  = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "vpce-s3-gateway-dev"
        }
      + tags_all              = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "vpce-s3-gateway-dev"
        }
      + vpc_endpoint_type     = "Gateway"
      + vpc_id                = (known after apply)

      + dns_options (known after apply)

      + subnet_configuration (known after apply)
    }

  # module.redshift.aws_iam_role.redshift_role will be created
  + resource "aws_iam_role" "redshift_role" {
      + arn                   = (known after apply)
      + assume_role_policy    = jsonencode(
            {
              + Statement = [
                  + {
                      + Action    = "sts:AssumeRole"
                      + Effect    = "Allow"
                      + Principal = {
                          + Service = [
                              + "redshift.amazonaws.com",
                              + "redshift-serverless.amazonaws.com",
                            ]
                        }
                    },
                ]
              + Version   = "2012-10-17"
            }
        )
      + create_date           = (known after apply)
      + force_detach_policies = false
      + id                    = (known after apply)
      + managed_policy_arns   = (known after apply)
      + max_session_duration  = 3600
      + name                  = "redshift-serverless-dev"
      + name_prefix           = (known after apply)
      + path                  = "/"
      + tags                  = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "redshift-serverless-dev"
        }
      + tags_all              = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "redshift-serverless-dev"
        }
      + unique_id             = (known after apply)

      + inline_policy (known after apply)
    }

  # module.redshift.aws_iam_role_policy.redshift_glue_lakehouse will be created
  + resource "aws_iam_role_policy" "redshift_glue_lakehouse" {
      + id          = (known after apply)
      + name        = "redshift-glue-lakehouse-policy"
      + name_prefix = (known after apply)
      + policy      = (known after apply)
      + role        = (known after apply)
    }

  # module.redshift.aws_iam_role_policy.redshift_kinesis_read will be created
  + resource "aws_iam_role_policy" "redshift_kinesis_read" {
      + id          = (known after apply)
      + name        = "redshift-kinesis-streaming-policy"
      + name_prefix = (known after apply)
      + policy      = (known after apply)
      + role        = (known after apply)
    }

  # module.redshift.aws_redshiftserverless_namespace.lakehouse will be created
  + resource "aws_redshiftserverless_namespace" "lakehouse" {
      + admin_password_secret_arn        = (known after apply)
      + admin_password_secret_kms_key_id = (known after apply)
      + admin_user_password_wo           = (write-only attribute)
      + admin_username                   = (sensitive value)
      + arn                              = (known after apply)
      + db_name                          = "analytics"
      + default_iam_role_arn             = (known after apply)
      + iam_roles                        = (known after apply)
      + id                               = (known after apply)
      + kms_key_id                       = (known after apply)
      + log_exports                      = [
          + "connectionlog",
          + "useractivitylog",
          + "userlog",
        ]
      + manage_admin_password            = true
      + namespace_id                     = (known after apply)
      + namespace_name                   = "lakehouse-ns-dev"
      + tags                             = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "lakehouse-ns-dev"
        }
      + tags_all                         = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "lakehouse-ns-dev"
        }
    }

  # module.redshift.aws_redshiftserverless_workgroup.lakehouse will be created
  + resource "aws_redshiftserverless_workgroup" "lakehouse" {
      + arn                 = (known after apply)
      + base_capacity       = 8
      + endpoint            = (known after apply)
      + id                  = (known after apply)
      + namespace_name      = "lakehouse-ns-dev"
      + port                = (known after apply)
      + publicly_accessible = false
      + security_group_ids  = (known after apply)
      + subnet_ids          = (known after apply)
      + tags                = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "lakehouse-wg-dev"
        }
      + tags_all            = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "lakehouse-wg-dev"
        }
      + track_name          = (known after apply)
      + workgroup_id        = (known after apply)
      + workgroup_name      = "lakehouse-wg-dev"

      + config_parameter (known after apply)

      + price_performance_target (known after apply)
    }

  # module.redshift.aws_security_group.redshift_sg will be created
  + resource "aws_security_group" "redshift_sg" {
      + arn                    = (known after apply)
      + description            = "Security group del workgroup de Redshift Serverless"
      + egress                 = [
          + {
              + cidr_blocks      = [
                  + "0.0.0.0/0",
                ]
              + description      = "Salida a servicios de AWS"
              + from_port        = 0
              + ipv6_cidr_blocks = []
              + prefix_list_ids  = []
              + protocol         = "-1"
              + security_groups  = []
              + self             = false
              + to_port          = 0
            },
        ]
      + id                     = (known after apply)
      + ingress                = [
          + {
              + cidr_blocks      = [
                  + "10.0.0.0/16",
                ]
              + description      = "Redshift desde la VPC"
              + from_port        = 5439
              + ipv6_cidr_blocks = []
              + prefix_list_ids  = []
              + protocol         = "tcp"
              + security_groups  = []
              + self             = false
              + to_port          = 5439
            },
        ]
      + name                   = "redshift-serverless-dev"
      + name_prefix            = (known after apply)
      + owner_id               = (known after apply)
      + revoke_rules_on_delete = false
      + tags                   = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "sg-redshift-serverless-dev"
        }
      + tags_all               = {
          + "Environment" = "dev"
          + "ManagedBy"   = "Terraform"
          + "Name"        = "sg-redshift-serverless-dev"
        }
      + vpc_id                 = (known after apply)
    }

Plan: 45 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + audit_role_arn            = (known after apply)
  + data_role_arn             = (known after apply)
  + private_subnets           = [
      + (known after apply),
      + (known after apply),
      + (known after apply),
    ]
  + raw_bucket_name           = "datalake-raw-dev-010798385513"
  + redshift_admin_secret_arn = (known after apply)
  + redshift_database         = "analytics"
  + redshift_iam_role_arn     = (known after apply)
  + redshift_workgroup        = "lakehouse-wg-dev"
  + s3_endpoint_id            = (known after apply)
  + vpc_id                    = (known after apply)

ÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇÔöÇ

Note: You didn't use the -out option to save this plan, so Terraform can't
guarantee to take exactly these actions if you run "terraform apply" now.
```
