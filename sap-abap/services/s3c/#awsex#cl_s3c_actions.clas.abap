" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS /awsex/cl_s3c_actions DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    " snippet-start:[s3c.abapv1.create_job]
    "! <p class="shorttext synchronized" lang="en">Creates an S3 Batch Operations job</p>
    "!
    "! @parameter iv_account_id | AWS account ID
    "! @parameter iv_role_arn | IAM role ARN for batch operations
    "! @parameter iv_manifest_arn | S3 ARN of the manifest file
    "! @parameter iv_manifest_etag | ETag of the manifest file
    "! @parameter iv_report_bucket | S3 ARN of the bucket for job reports
    "! @parameter ov_job_id | The ID of the created job
    "! @raising /aws1/cx_rt_generic | Thrown when an exception occurs
    METHODS create_job
      IMPORTING
        !iv_account_id     TYPE /aws1/s3caccountid
        !iv_role_arn       TYPE /aws1/s3ciamrolearn
        !iv_manifest_arn   TYPE /aws1/s3cs3keyarnstring
        !iv_manifest_etag  TYPE /aws1/s3cnonemptymaxlength1024st
        !iv_report_bucket  TYPE /aws1/s3cs3bucketarnstring
      RETURNING
        VALUE(ov_job_id)   TYPE /aws1/s3cjobid
      RAISING
        /aws1/cx_rt_generic .
    " snippet-end:[s3c.abapv1.create_job]

    " snippet-start:[s3c.abapv1.describe_job]
    "! <p class="shorttext synchronized" lang="en">Describes an S3 Batch Operations job</p>
    "!
    "! @parameter iv_account_id | AWS account ID
    "! @parameter iv_job_id | ID of the batch job
    "! @parameter oo_result | The job description result
    "! @raising /aws1/cx_rt_generic | Thrown when an exception occurs
    METHODS describe_job
      IMPORTING
        !iv_account_id TYPE /aws1/s3caccountid
        !iv_job_id     TYPE /aws1/s3cjobid
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_s3cdescribejobresult
      RAISING
        /aws1/cx_rt_generic .
    " snippet-end:[s3c.abapv1.describe_job]

    " snippet-start:[s3c.abapv1.update_job_priority]
    "! <p class="shorttext synchronized" lang="en">Updates the priority of an S3 Batch Operations job</p>
    "!
    "! @parameter iv_account_id | AWS account ID
    "! @parameter iv_job_id | ID of the batch job
    "! @parameter iv_priority | New priority for the job
    "! @raising /aws1/cx_rt_generic | Thrown when an exception occurs
    METHODS update_job_priority
      IMPORTING
        !iv_account_id TYPE /aws1/s3caccountid
        !iv_job_id     TYPE /aws1/s3cjobid
        !iv_priority   TYPE /aws1/s3cjobpriority
      RAISING
        /aws1/cx_rt_generic .
    " snippet-end:[s3c.abapv1.update_job_priority]

    " snippet-start:[s3c.abapv1.update_job_status]
    "! <p class="shorttext synchronized" lang="en">Updates the status of an S3 Batch Operations job</p>
    "!
    "! @parameter iv_account_id | AWS account ID
    "! @parameter iv_job_id | ID of the batch job
    "! @parameter iv_requested_status | The requested job status
    "! @raising /aws1/cx_rt_generic | Thrown when an exception occurs
    METHODS update_job_status
      IMPORTING
        !iv_account_id        TYPE /aws1/s3caccountid
        !iv_job_id            TYPE /aws1/s3cjobid
        !iv_requested_status  TYPE /aws1/s3crequestedjobstatus
      RAISING
        /aws1/cx_rt_generic .
    " snippet-end:[s3c.abapv1.update_job_status]

    " snippet-start:[s3c.abapv1.get_job_tagging]
    "! <p class="shorttext synchronized" lang="en">Gets the tags for an S3 Batch Operations job</p>
    "!
    "! @parameter iv_account_id | AWS account ID
    "! @parameter iv_job_id | ID of the batch job
    "! @parameter oo_result | The job tagging result
    "! @raising /aws1/cx_rt_generic | Thrown when an exception occurs
    METHODS get_job_tagging
      IMPORTING
        !iv_account_id TYPE /aws1/s3caccountid
        !iv_job_id     TYPE /aws1/s3cjobid
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_s3cgetjobtagresult
      RAISING
        /aws1/cx_rt_generic .
    " snippet-end:[s3c.abapv1.get_job_tagging]

    " snippet-start:[s3c.abapv1.put_job_tagging]
    "! <p class="shorttext synchronized" lang="en">Sets the tags for an S3 Batch Operations job</p>
    "!
    "! @parameter iv_account_id | AWS account ID
    "! @parameter iv_job_id | ID of the batch job
    "! @parameter it_tags | The tags to set
    "! @raising /aws1/cx_rt_generic | Thrown when an exception occurs
    METHODS put_job_tagging
      IMPORTING
        !iv_account_id TYPE /aws1/s3caccountid
        !iv_job_id     TYPE /aws1/s3cjobid
        !it_tags       TYPE /aws1/cl_s3cs3tag=>tt_s3tagset
      RAISING
        /aws1/cx_rt_generic .
    " snippet-end:[s3c.abapv1.put_job_tagging]

    " snippet-start:[s3c.abapv1.list_jobs]
    "! <p class="shorttext synchronized" lang="en">Lists all S3 Batch Operations jobs</p>
    "!
    "! @parameter iv_account_id | AWS account ID
    "! @parameter it_job_statuses | Optional list of job statuses to filter
    "! @parameter oo_result | The list of jobs result
    "! @raising /aws1/cx_rt_generic | Thrown when an exception occurs
    METHODS list_jobs
      IMPORTING
        !iv_account_id    TYPE /aws1/s3caccountid
        !it_job_statuses  TYPE /aws1/cl_s3cjobstatuslist_w=>tt_jobstatuslist OPTIONAL
      RETURNING
        VALUE(oo_result)  TYPE REF TO /aws1/cl_s3clistjobsresult
      RAISING
        /aws1/cx_rt_generic .
    " snippet-end:[s3c.abapv1.list_jobs]

    " snippet-start:[s3c.abapv1.delete_job_tagging]
    "! <p class="shorttext synchronized" lang="en">Deletes the tags from an S3 Batch Operations job</p>
    "!
    "! @parameter iv_account_id | AWS account ID
    "! @parameter iv_job_id | ID of the batch job
    "! @raising /aws1/cx_rt_generic | Thrown when an exception occurs
    METHODS delete_job_tagging
      IMPORTING
        !iv_account_id TYPE /aws1/s3caccountid
        !iv_job_id     TYPE /aws1/s3cjobid
      RAISING
        /aws1/cx_rt_generic .
    " snippet-end:[s3c.abapv1.delete_job_tagging]

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS /AWSEX/CL_S3C_ACTIONS IMPLEMENTATION.


  METHOD create_job.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.create_job]
    TRY.
        " Example: 'arn:aws:iam::123456789012:role/S3BatchJobRole'
        DATA(lv_role_arn) = iv_role_arn.
        " Example: 'arn:aws:s3:::my-bucket/job-manifest.csv'
        DATA(lv_manifest_arn) = iv_manifest_arn.
        " Example: 'abc123'
        DATA(lv_etag) = iv_manifest_etag.
        " Example: 'arn:aws:s3:::my-report-bucket'
        DATA(lv_report_bucket) = iv_report_bucket.

        DATA(lo_result) = lo_s3c->createjob(
          iv_accountid = iv_account_id
          iv_rolearn = lv_role_arn
          io_manifest = NEW /aws1/cl_s3cjobmanifest(
            io_location = NEW /aws1/cl_s3cjobmanifestloc(
              iv_etag = lv_etag
              iv_objectarn = lv_manifest_arn
            )
            io_spec = NEW /aws1/cl_s3cjobmanifestspec(
              it_fields = VALUE /aws1/cl_s3cjobmanifestfield00=>tt_jobmanifestfieldlist(
                ( NEW /aws1/cl_s3cjobmanifestfield00( 'Bucket' ) )
                ( NEW /aws1/cl_s3cjobmanifestfield00( 'Key' ) )
              )
              iv_format = 'S3BatchOperations_CSV_20180820'
            )
          )
          io_operation = NEW /aws1/cl_s3cjoboperation(
            io_s3putobjecttagging = NEW /aws1/cl_s3cs3setobjecttagop(
              it_tagset = VALUE /aws1/cl_s3cs3tag=>tt_s3tagset(
                ( NEW /aws1/cl_s3cs3tag( iv_key = 'BatchTag' iv_value = 'BatchValue' ) )
              )
            )
          )
          io_report = NEW /aws1/cl_s3cjobreport(
            iv_bucket = lv_report_bucket
            iv_format = 'Report_CSV_20180820'
            iv_enabled = abap_true
            iv_prefix = 'batch-op-reports'
            iv_reportscope = 'AllTasks'
          )
          iv_priority = 10
          iv_description = 'Batch job for tagging objects'
          iv_confirmationrequired = abap_true
        ).

        ov_job_id = lo_result->get_jobid( ).
        MESSAGE 'Job created successfully with ID: ' && ov_job_id TYPE 'I'.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_exception).
        DATA(lv_error) = |Exception occurred: { lo_exception->get_text( ) }|.
        MESSAGE lv_error TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.create_job]
  ENDMETHOD.


  METHOD describe_job.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.describe_job]
    TRY.
        oo_result = lo_s3c->describejob(
          iv_accountid = iv_account_id
          iv_jobid = iv_job_id
        ).

        DATA(lo_job) = oo_result->get_job( ).
        IF lo_job IS BOUND.
          DATA(lv_status) = lo_job->get_status( ).
          DATA(lv_description) = lo_job->get_description( ).
          DATA(lo_progress) = lo_job->get_progresssummary( ).
          IF lo_progress IS BOUND.
            DATA(lv_total) = lo_progress->get_totalnumberoftasks( ).
            DATA(lv_succeeded) = lo_progress->get_numberoftaskssucceeded( ).
            DATA(lv_failed) = lo_progress->get_numberoftasksfailed( ).
            MESSAGE 'Job Status: ' && lv_status && ', Total: ' && lv_total &&
                    ', Succeeded: ' && lv_succeeded && ', Failed: ' && lv_failed TYPE 'I'.
          ENDIF.
        ENDIF.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_exception).
        DATA(lv_error) = |Exception occurred: { lo_exception->get_text( ) }|.
        MESSAGE lv_error TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.describe_job]
  ENDMETHOD.


  METHOD update_job_priority.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.update_job_priority]
    TRY.
        " Example priority: 60
        DATA(lo_result) = lo_s3c->updatejobpriority(
          iv_accountid = iv_account_id
          iv_jobid = iv_job_id
          iv_priority = iv_priority
        ).

        DATA(lv_job_id) = lo_result->get_jobid( ).
        DATA(lv_priority) = lo_result->get_priority( ).
        MESSAGE 'Job priority updated to: ' && lv_priority TYPE 'I'.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_exception).
        DATA(lv_error) = |Exception occurred: { lo_exception->get_text( ) }|.
        MESSAGE lv_error TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.update_job_priority]
  ENDMETHOD.


  METHOD update_job_status.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.update_job_status]
    TRY.
        " Example status: 'Cancelled' or 'Ready'
        lo_s3c->updatejobstatus(
          iv_accountid = iv_account_id
          iv_jobid = iv_job_id
          iv_requestedjobstatus = iv_requested_status
        ).

        MESSAGE 'Job status updated to: ' && iv_requested_status TYPE 'I'.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_exception).
        DATA(lv_error) = |Exception occurred: { lo_exception->get_text( ) }|.
        MESSAGE lv_error TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.update_job_status]
  ENDMETHOD.


  METHOD get_job_tagging.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.get_job_tagging]
    TRY.
        oo_result = lo_s3c->getjobtagging(
          iv_accountid = iv_account_id
          iv_jobid = iv_job_id
        ).

        DATA(lt_tags) = oo_result->get_tags( ).
        IF lt_tags IS NOT INITIAL.
          MESSAGE 'Retrieved ' && lines( lt_tags ) && ' tags for job' TYPE 'I'.
        ELSE.
          MESSAGE 'No tags found for job' TYPE 'I'.
        ENDIF.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_exception).
        DATA(lv_error) = |Exception occurred: { lo_exception->get_text( ) }|.
        MESSAGE lv_error TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.get_job_tagging]
  ENDMETHOD.


  METHOD put_job_tagging.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.put_job_tagging]
    TRY.
        lo_s3c->putjobtagging(
          iv_accountid = iv_account_id
          iv_jobid = iv_job_id
          it_tags = it_tags
        ).

        MESSAGE 'Tags added to job successfully' TYPE 'I'.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_exception).
        DATA(lv_error) = |Exception occurred: { lo_exception->get_text( ) }|.
        MESSAGE lv_error TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.put_job_tagging]
  ENDMETHOD.


  METHOD list_jobs.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.list_jobs]
    TRY.
        oo_result = lo_s3c->listjobs(
          iv_accountid = iv_account_id
          it_jobstatuses = it_job_statuses
        ).

        DATA(lt_jobs) = oo_result->get_jobs( ).
        IF lt_jobs IS NOT INITIAL.
          MESSAGE 'Found ' && lines( lt_jobs ) && ' jobs' TYPE 'I'.
        ELSE.
          MESSAGE 'No jobs found' TYPE 'I'.
        ENDIF.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_exception).
        DATA(lv_error) = |Exception occurred: { lo_exception->get_text( ) }|.
        MESSAGE lv_error TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.list_jobs]
  ENDMETHOD.


  METHOD delete_job_tagging.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.delete_job_tagging]
    TRY.
        lo_s3c->deletejobtagging(
          iv_accountid = iv_account_id
          iv_jobid = iv_job_id
        ).

        MESSAGE 'Job tagging deleted successfully' TYPE 'I'.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_exception).
        DATA(lv_error) = |Exception occurred: { lo_exception->get_text( ) }|.
        MESSAGE lv_error TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.delete_job_tagging]
  ENDMETHOD.
ENDCLASS.
