" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS /awsex/cl_s3c_actions DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS create_job
      IMPORTING
        iv_account_id     TYPE /aws1/s3caccountid
        iv_role_arn       TYPE /aws1/s3ciamrolearn
        iv_manifest_arn   TYPE /aws1/s3cs3keyarnstring
        iv_manifest_etag  TYPE /aws1/s3cnonemptymaxlength1000
        iv_report_bucket  TYPE /aws1/s3cs3bucketarnstring
      RETURNING
        VALUE(ov_job_id)  TYPE /aws1/s3cjobid.

    METHODS update_job_priority
      IMPORTING
        iv_account_id TYPE /aws1/s3caccountid
        iv_job_id     TYPE /aws1/s3cjobid.

    METHODS update_job_status
      IMPORTING
        iv_account_id TYPE /aws1/s3caccountid
        iv_job_id     TYPE /aws1/s3cjobid.

    METHODS describe_job
      IMPORTING
        iv_account_id TYPE /aws1/s3caccountid
        iv_job_id     TYPE /aws1/s3cjobid.

    METHODS get_job_tagging
      IMPORTING
        iv_account_id TYPE /aws1/s3caccountid
        iv_job_id     TYPE /aws1/s3cjobid.

    METHODS put_job_tagging
      IMPORTING
        iv_account_id TYPE /aws1/s3caccountid
        iv_job_id     TYPE /aws1/s3cjobid.

    METHODS list_jobs
      IMPORTING
        iv_account_id TYPE /aws1/s3caccountid.

    METHODS delete_job_tagging
      IMPORTING
        iv_account_id TYPE /aws1/s3caccountid
        iv_job_id     TYPE /aws1/s3cjobid.

ENDCLASS.

CLASS /awsex/cl_s3c_actions IMPLEMENTATION.

  METHOD create_job.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.create_job]
    TRY.
        " Build the manifest fields list: 'Bucket' and 'Key'
        DATA lt_fields TYPE /aws1/cl_s3cjobmanifestfield00=>tt_jobmanifestfieldlist.
        APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Bucket' ) TO lt_fields.
        APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Key' ) TO lt_fields.

        " Build the object tagging operation
        DATA lt_tagset TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
        APPEND NEW /aws1/cl_s3cs3tag(
          iv_key   = 'BatchTag'         " e.g. 'BatchTag'
          iv_value = 'BatchValue'       " e.g. 'BatchValue'
        ) TO lt_tagset.

        DATA(oo_result) = lo_s3c->createjob(
          iv_accountid          = iv_account_id
          iv_confirmationrequired = abap_true
          iv_priority           = 10
          iv_rolearn            = iv_role_arn
          iv_description        = 'Batch job for tagging objects'
          io_operation          = NEW /aws1/cl_s3cjoboperation(
            io_s3putobjecttagging = NEW /aws1/cl_s3cs3setobjecttagop(
              it_tagset = lt_tagset
            )
          )
          io_report             = NEW /aws1/cl_s3cjobreport(
            iv_bucket      = iv_report_bucket
            iv_format      = 'Report_CSV_20180820'
            iv_enabled     = abap_true
            iv_prefix      = 'batch-op-reports'
            iv_reportscope = 'AllTasks'
          )
          io_manifest           = NEW /aws1/cl_s3cjobmanifest(
            io_spec     = NEW /aws1/cl_s3cjobmanifestspec(
              iv_format  = 'S3BatchOperations_CSV_20180820'
              it_fields  = lt_fields
            )
            io_location = NEW /aws1/cl_s3cjobmanifestloc(
              iv_objectarn = iv_manifest_arn
              iv_etag      = iv_manifest_etag
            )
          )
        ).
        ov_job_id = oo_result->get_jobid( ).
        MESSAGE |S3 Batch job created: { ov_job_id }| TYPE 'I'.
      CATCH /aws1/cx_s3cbadrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cidempotencyex INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_ex3).
        MESSAGE lo_ex3->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_ex4).
        MESSAGE lo_ex4->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_ex5).
        MESSAGE lo_ex5->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.create_job]
  ENDMETHOD.

  METHOD update_job_priority.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.update_job_priority]
    TRY.
        lo_s3c->updatejobpriority(
          iv_accountid = iv_account_id
          iv_jobid     = iv_job_id
          iv_priority  = 60
        ).
        MESSAGE |Job priority updated for job: { iv_job_id }| TYPE 'I'.
      CATCH /aws1/cx_s3cbadrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_ex3).
        MESSAGE lo_ex3->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_ex4).
        MESSAGE lo_ex4->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_ex5).
        MESSAGE lo_ex5->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.update_job_priority]
  ENDMETHOD.

  METHOD update_job_status.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.update_job_status]
    TRY.
        lo_s3c->updatejobstatus(
          iv_accountid          = iv_account_id
          iv_jobid              = iv_job_id
          iv_requestedjobstatus = 'Cancelled'
        ).
        MESSAGE |S3 Batch job cancelled: { iv_job_id }| TYPE 'I'.
      CATCH /aws1/cx_s3cjobstatusexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cbadrequestex INTO DATA(lo_ex3).
        MESSAGE lo_ex3->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_ex4).
        MESSAGE lo_ex4->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_ex5).
        MESSAGE lo_ex5->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_ex6).
        MESSAGE lo_ex6->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.update_job_status]
  ENDMETHOD.

  METHOD describe_job.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.describe_job]
    TRY.
        DATA(oo_result) = lo_s3c->describejob(
          iv_accountid = iv_account_id
          iv_jobid     = iv_job_id
        ).
        DATA(lo_job) = oo_result->get_job( ).
        DATA(lv_status)   = lo_job->get_status( ).
        DATA(lv_priority) = lo_job->get_priority( ).
        DATA(lo_progress) = lo_job->get_progresssummary( ).
        DATA lv_total    TYPE /aws1/s3cjobtotalnumberoftasks.
        DATA lv_success  TYPE /aws1/s3cjobnumberoftaskssucc.
        DATA lv_failed   TYPE /aws1/s3cjobnumoftasksfailed.
        IF lo_progress IS BOUND.
          lv_total   = lo_progress->get_totalnumberoftasks( ).
          lv_success = lo_progress->get_numberoftaskssucceeded( ).
          lv_failed  = lo_progress->get_numberoftasksfailed( ).
        ENDIF.
        MESSAGE |Job { iv_job_id } status: { lv_status } priority: { lv_priority }| &&
                | total: { lv_total } succeeded: { lv_success } failed: { lv_failed }| TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cbadrequestex INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_ex3).
        MESSAGE lo_ex3->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_ex4).
        MESSAGE lo_ex4->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_ex5).
        MESSAGE lo_ex5->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.describe_job]
  ENDMETHOD.

  METHOD get_job_tagging.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.get_job_tagging]
    TRY.
        DATA(oo_result) = lo_s3c->getjobtagging(
          iv_accountid = iv_account_id
          iv_jobid     = iv_job_id
        ).
        DATA(lt_tags) = oo_result->get_tags( ).
        MESSAGE |Retrieved { lines( lt_tags ) } tag(s) for job { iv_job_id }| TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_ex3).
        MESSAGE lo_ex3->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_ex4).
        MESSAGE lo_ex4->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.get_job_tagging]
  ENDMETHOD.

  METHOD put_job_tagging.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.put_job_tagging]
    TRY.
        DATA lt_tags TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
        APPEND NEW /aws1/cl_s3cs3tag(
          iv_key   = 'Environment'   " e.g. 'Environment'
          iv_value = 'Development'   " e.g. 'Development'
        ) TO lt_tags.
        APPEND NEW /aws1/cl_s3cs3tag(
          iv_key   = 'Team'          " e.g. 'Team'
          iv_value = 'DataProcessing'" e.g. 'DataProcessing'
        ) TO lt_tags.

        lo_s3c->putjobtagging(
          iv_accountid = iv_account_id
          iv_jobid     = iv_job_id
          it_tags      = lt_tags
        ).
        MESSAGE |{ lines( lt_tags ) } tag(s) added to job { iv_job_id }| TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3ctoomanytagsex INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_ex3).
        MESSAGE lo_ex3->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_ex4).
        MESSAGE lo_ex4->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_ex5).
        MESSAGE lo_ex5->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.put_job_tagging]
  ENDMETHOD.

  METHOD list_jobs.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.list_jobs]
    TRY.
        " Build status filter to include all possible job statuses
        DATA lt_statuses TYPE /aws1/cl_s3cjobstatuslist_w=>tt_jobstatuslist.
        APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Active' )     TO lt_statuses.
        APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Complete' )   TO lt_statuses.
        APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Cancelled' )  TO lt_statuses.
        APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Failed' )     TO lt_statuses.
        APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'New' )        TO lt_statuses.
        APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Paused' )     TO lt_statuses.
        APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Pausing' )    TO lt_statuses.
        APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Preparing' )  TO lt_statuses.
        APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Ready' )      TO lt_statuses.
        APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Suspended' )  TO lt_statuses.

        DATA(oo_result) = lo_s3c->listjobs(
          iv_accountid    = iv_account_id
          it_jobstatuses  = lt_statuses
        ).
        DATA(lt_jobs) = oo_result->get_jobs( ).
        MESSAGE |Retrieved { lines( lt_jobs ) } S3 Batch job(s)| TYPE 'I'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cinvalidnexttokenex INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cinvalidrequestex INTO DATA(lo_ex3).
        MESSAGE lo_ex3->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_ex4).
        MESSAGE lo_ex4->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_ex5).
        MESSAGE lo_ex5->get_text( ) TYPE 'I'.
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
          iv_jobid     = iv_job_id
        ).
        MESSAGE |Tags deleted for job: { iv_job_id }| TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_ex3).
        MESSAGE lo_ex3->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_ex4).
        MESSAGE lo_ex4->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.delete_job_tagging]
  ENDMETHOD.

ENDCLASS.
