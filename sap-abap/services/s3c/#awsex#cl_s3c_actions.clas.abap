" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS /awsex/cl_s3c_actions DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.

    METHODS create_job
      IMPORTING
        !iv_account_id       TYPE /aws1/s3caccountid
        !iv_role_arn         TYPE /aws1/s3ciamrolearn
        !iv_manifest_arn     TYPE /aws1/s3cs3keyarnstring
        !iv_manifest_etag    TYPE /aws1/s3cnonemptymaxlength1000
        !iv_report_bucket    TYPE /aws1/s3cs3bucketarnstring
      RETURNING
        VALUE(ov_job_id)     TYPE /aws1/s3cjobid
      RAISING
        /aws1/cx_rt_generic.

    METHODS update_job_priority
      IMPORTING
        !iv_account_id TYPE /aws1/s3caccountid
        !iv_job_id     TYPE /aws1/s3cjobid
      RAISING
        /aws1/cx_rt_generic.

    METHODS update_job_status
      IMPORTING
        !iv_account_id TYPE /aws1/s3caccountid
        !iv_job_id     TYPE /aws1/s3cjobid
      RAISING
        /aws1/cx_rt_generic.

    METHODS describe_job
      IMPORTING
        !iv_account_id TYPE /aws1/s3caccountid
        !iv_job_id     TYPE /aws1/s3cjobid
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_s3cdescribejobresult
      RAISING
        /aws1/cx_rt_generic.

    METHODS get_job_tagging
      IMPORTING
        !iv_account_id TYPE /aws1/s3caccountid
        !iv_job_id     TYPE /aws1/s3cjobid
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_s3cgetjobtagresult
      RAISING
        /aws1/cx_rt_generic.

    METHODS put_job_tagging
      IMPORTING
        !iv_account_id TYPE /aws1/s3caccountid
        !iv_job_id     TYPE /aws1/s3cjobid
      RAISING
        /aws1/cx_rt_generic.

    METHODS list_jobs
      IMPORTING
        !iv_account_id TYPE /aws1/s3caccountid
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_s3clistjobsresult
      RAISING
        /aws1/cx_rt_generic.

    METHODS delete_job_tagging
      IMPORTING
        !iv_account_id TYPE /aws1/s3caccountid
        !iv_job_id     TYPE /aws1/s3cjobid
      RAISING
        /aws1/cx_rt_generic.

ENDCLASS.

CLASS /awsex/cl_s3c_actions IMPLEMENTATION.

  METHOD create_job.
    " snippet-start:[s3c.abapv1.create_job]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).
    TRY.
        DATA(lo_result) = lo_s3c->createjob(
          iv_accountid            = iv_account_id
          iv_confirmationrequired = abap_true
          iv_description          = 'Batch job for tagging objects'
          iv_priority             = 10
          iv_rolearn              = iv_role_arn
          io_operation            = NEW /aws1/cl_s3cjoboperation(
            io_s3putobjecttagging = NEW /aws1/cl_s3cs3setobjecttagop(
              it_tagset = VALUE /aws1/cl_s3cs3tag=>tt_s3tagset(
                ( NEW /aws1/cl_s3cs3tag(
                    " e.g. 'BatchTag'
                    iv_key   = 'BatchTag'
                    " e.g. 'BatchValue'
                    iv_value = 'BatchValue' ) )
              )
            )
          )
          io_report               = NEW /aws1/cl_s3cjobreport(
            iv_bucket      = iv_report_bucket
            iv_format      = 'Report_CSV_20180820'
            iv_enabled     = abap_true
            iv_prefix      = 'batch-op-reports'
            iv_reportscope = 'AllTasks'
          )
          io_manifest             = NEW /aws1/cl_s3cjobmanifest(
            io_spec     = NEW /aws1/cl_s3cjobmanifestspec(
              iv_format = 'S3BatchOperations_CSV_20180820'
              it_fields = VALUE /aws1/cl_s3cjobmanifestfield00=>tt_jobmanifestfieldlist(
                ( NEW /aws1/cl_s3cjobmanifestfield00( 'Bucket' ) )
                ( NEW /aws1/cl_s3cjobmanifestfield00( 'Key' ) )
              )
            )
            io_location = NEW /aws1/cl_s3cjobmanifestloc(
              iv_objectarn = iv_manifest_arn
              iv_etag      = iv_manifest_etag
            )
          )
        ).
        ov_job_id = lo_result->get_jobid( ).
        MESSAGE |S3 Batch job created: { ov_job_id }| TYPE 'I'.
      CATCH /aws1/cx_s3cbadrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION TYPE /aws1/cx_rt_technical_generic
          EXPORTING previous = lo_ex.
      CATCH /aws1/cx_rt_generic INTO lo_ex.
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
    ENDTRY.
    " snippet-end:[s3c.abapv1.create_job]
  ENDMETHOD.

  METHOD update_job_priority.
    " snippet-start:[s3c.abapv1.update_job_priority]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).
    TRY.
        DATA(lo_result) = lo_s3c->updatejobpriority(
          iv_accountid = iv_account_id
          iv_jobid     = iv_job_id
          iv_priority  = 60
        ).
        MESSAGE |Job { lo_result->get_jobid( ) } priority updated to { lo_result->get_priority( ) }| TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION TYPE /aws1/cx_rt_technical_generic
          EXPORTING previous = lo_ex.
      CATCH /aws1/cx_rt_generic INTO lo_ex.
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
    ENDTRY.
    " snippet-end:[s3c.abapv1.update_job_priority]
  ENDMETHOD.

  METHOD update_job_status.
    " snippet-start:[s3c.abapv1.update_job_status]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).
    TRY.
        DATA(lo_result) = lo_s3c->updatejobstatus(
          iv_accountid          = iv_account_id
          iv_jobid              = iv_job_id
          iv_requestedjobstatus = 'Cancelled'
        ).
        MESSAGE |Job { lo_result->get_jobid( ) } status updated to { lo_result->get_status( ) }| TYPE 'I'.
      CATCH /aws1/cx_s3cjobstatusexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION TYPE /aws1/cx_rt_technical_generic
          EXPORTING previous = lo_ex.
      CATCH /aws1/cx_s3cnotfoundexception INTO lo_ex.
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION TYPE /aws1/cx_rt_technical_generic
          EXPORTING previous = lo_ex.
      CATCH /aws1/cx_rt_generic INTO lo_ex.
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
    ENDTRY.
    " snippet-end:[s3c.abapv1.update_job_status]
  ENDMETHOD.

  METHOD describe_job.
    " snippet-start:[s3c.abapv1.describe_job]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).
    TRY.
        oo_result = lo_s3c->describejob(
          iv_accountid = iv_account_id
          iv_jobid     = iv_job_id
        ).
        DATA(lo_job) = oo_result->get_job( ).
        IF lo_job IS NOT INITIAL.
          MESSAGE |Job { lo_job->get_jobid( ) } | &&
                  |status: { lo_job->get_status( ) } | &&
                  |priority: { lo_job->get_priority( ) }| TYPE 'I'.
        ENDIF.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION TYPE /aws1/cx_rt_technical_generic
          EXPORTING previous = lo_ex.
      CATCH /aws1/cx_rt_generic INTO lo_ex.
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
    ENDTRY.
    " snippet-end:[s3c.abapv1.describe_job]
  ENDMETHOD.

  METHOD get_job_tagging.
    " snippet-start:[s3c.abapv1.get_job_tagging]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).
    TRY.
        oo_result = lo_s3c->getjobtagging(
          iv_accountid = iv_account_id
          iv_jobid     = iv_job_id
        ).
        DATA(lt_tags) = oo_result->get_tags( ).
        MESSAGE |Retrieved { lines( lt_tags ) } tag(s) for job { iv_job_id }| TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION TYPE /aws1/cx_rt_technical_generic
          EXPORTING previous = lo_ex.
      CATCH /aws1/cx_rt_generic INTO lo_ex.
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
    ENDTRY.
    " snippet-end:[s3c.abapv1.get_job_tagging]
  ENDMETHOD.

  METHOD put_job_tagging.
    " snippet-start:[s3c.abapv1.put_job_tagging]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).
    TRY.
        lo_s3c->putjobtagging(
          iv_accountid = iv_account_id
          iv_jobid     = iv_job_id
          it_tags      = VALUE /aws1/cl_s3cs3tag=>tt_s3tagset(
            ( NEW /aws1/cl_s3cs3tag( iv_key = 'Environment' iv_value = 'Development' ) )
            ( NEW /aws1/cl_s3cs3tag( iv_key = 'Team'        iv_value = 'DataProcessing' ) )
          )
        ).
        MESSAGE |Tags added to job { iv_job_id }| TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION TYPE /aws1/cx_rt_technical_generic
          EXPORTING previous = lo_ex.
      CATCH /aws1/cx_rt_generic INTO lo_ex.
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
    ENDTRY.
    " snippet-end:[s3c.abapv1.put_job_tagging]
  ENDMETHOD.

  METHOD list_jobs.
    " snippet-start:[s3c.abapv1.list_jobs]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).
    TRY.
        oo_result = lo_s3c->listjobs(
          iv_accountid   = iv_account_id
          it_jobstatuses = VALUE /aws1/cl_s3cjobstatuslist_w=>tt_jobstatuslist(
            ( NEW /aws1/cl_s3cjobstatuslist_w( 'Active' ) )
            ( NEW /aws1/cl_s3cjobstatuslist_w( 'Complete' ) )
            ( NEW /aws1/cl_s3cjobstatuslist_w( 'Cancelled' ) )
            ( NEW /aws1/cl_s3cjobstatuslist_w( 'Failed' ) )
            ( NEW /aws1/cl_s3cjobstatuslist_w( 'New' ) )
            ( NEW /aws1/cl_s3cjobstatuslist_w( 'Paused' ) )
            ( NEW /aws1/cl_s3cjobstatuslist_w( 'Pausing' ) )
            ( NEW /aws1/cl_s3cjobstatuslist_w( 'Preparing' ) )
            ( NEW /aws1/cl_s3cjobstatuslist_w( 'Ready' ) )
            ( NEW /aws1/cl_s3cjobstatuslist_w( 'Suspended' ) )
          )
        ).
        DATA(lt_jobs) = oo_result->get_jobs( ).
        MESSAGE |Retrieved { lines( lt_jobs ) } S3 Batch job(s)| TYPE 'I'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION TYPE /aws1/cx_rt_technical_generic
          EXPORTING previous = lo_ex.
      CATCH /aws1/cx_rt_generic INTO lo_ex.
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
    ENDTRY.
    " snippet-end:[s3c.abapv1.list_jobs]
  ENDMETHOD.

  METHOD delete_job_tagging.
    " snippet-start:[s3c.abapv1.delete_job_tagging]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).
    TRY.
        lo_s3c->deletejobtagging(
          iv_accountid = iv_account_id
          iv_jobid     = iv_job_id
        ).
        MESSAGE |Tags deleted for job { iv_job_id }| TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION TYPE /aws1/cx_rt_technical_generic
          EXPORTING previous = lo_ex.
      CATCH /aws1/cx_rt_generic INTO lo_ex.
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
    ENDTRY.
    " snippet-end:[s3c.abapv1.delete_job_tagging]
  ENDMETHOD.

ENDCLASS.
