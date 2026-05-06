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
        iv_manifest_etag  TYPE /aws1/s3cnonemptymaxlength6400
        iv_report_bucket  TYPE /aws1/s3cs3bucketarnstring
      RETURNING
        VALUE(ov_job_id)  TYPE /aws1/s3cjobid.

    METHODS describe_job
      IMPORTING
        iv_account_id  TYPE /aws1/s3caccountid
        iv_job_id      TYPE /aws1/s3cjobid.

    METHODS update_job_priority
      IMPORTING
        iv_account_id  TYPE /aws1/s3caccountid
        iv_job_id      TYPE /aws1/s3cjobid
        iv_priority    TYPE /aws1/s3cjobpriority.

    METHODS update_job_status
      IMPORTING
        iv_account_id  TYPE /aws1/s3caccountid
        iv_job_id      TYPE /aws1/s3cjobid
        iv_req_status  TYPE /aws1/s3crequestedjobstatus.

    METHODS get_job_tagging
      IMPORTING
        iv_account_id  TYPE /aws1/s3caccountid
        iv_job_id      TYPE /aws1/s3cjobid.

    METHODS put_job_tagging
      IMPORTING
        iv_account_id  TYPE /aws1/s3caccountid
        iv_job_id      TYPE /aws1/s3cjobid.

    METHODS list_jobs
      IMPORTING
        iv_account_id  TYPE /aws1/s3caccountid.

    METHODS delete_job_tagging
      IMPORTING
        iv_account_id  TYPE /aws1/s3caccountid
        iv_job_id      TYPE /aws1/s3cjobid.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS /awsex/cl_s3c_actions IMPLEMENTATION.

  METHOD create_job.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.create_job]
    TRY.
        " Build the manifest spec (CSV format with Bucket and Key fields)
        DATA lt_fields TYPE /aws1/cl_s3cjobmanifestfield00=>tt_jobmanifestfieldlist.
        APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Bucket' ) TO lt_fields.
        APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Key' ) TO lt_fields.

        DATA(lo_manifest_spec) = NEW /aws1/cl_s3cjobmanifestspec(
            iv_format = 'S3BatchOperations_CSV_20180820'
            it_fields = lt_fields ).

        DATA(lo_manifest_loc) = NEW /aws1/cl_s3cjobmanifestloc(
            " Example: 'arn:aws:s3:::my-bucket/job-manifest.csv'
            iv_objectarn = iv_manifest_arn
            iv_etag      = iv_manifest_etag ).

        DATA(lo_manifest) = NEW /aws1/cl_s3cjobmanifest(
            io_spec     = lo_manifest_spec
            io_location = lo_manifest_loc ).

        " Tag the objects with S3PutObjectTagging operation
        DATA lt_tagset TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
        APPEND NEW /aws1/cl_s3cs3tag(
            iv_key   = 'BatchTag'
            iv_value = 'BatchValue' ) TO lt_tagset.

        DATA(lo_operation) = NEW /aws1/cl_s3cjoboperation(
            io_s3putobjecttagging = NEW /aws1/cl_s3cs3setobjecttagop(
                it_tagset = lt_tagset ) ).

        " Report bucket ARN — e.g. 'arn:aws:s3:::my-report-bucket'
        DATA(lo_report) = NEW /aws1/cl_s3cjobreport(
            iv_bucket      = iv_report_bucket
            iv_format      = 'Report_CSV_20180820'
            iv_enabled     = abap_true
            iv_prefix      = 'batch-op-reports'
            iv_reportscope = 'AllTasks' ).

        " Generate a unique client request token
        DATA lv_token TYPE /aws1/s3cnonemptymaxlength6400.
        TRY.
            DATA(lo_guid) = cl_system_uuid=>create_uuid_c32_static( ).
            lv_token = lo_guid.
          CATCH cx_uuid_error.
            lv_token = sy-uzeit.
        ENDTRY.

        DATA(oo_result) = lo_s3c->createjob(
            iv_accountid          = iv_account_id
            iv_rolearn            = iv_role_arn
            io_manifest           = lo_manifest
            io_operation          = lo_operation
            io_report             = lo_report
            iv_priority           = 10
            iv_description        = 'Batch job for tagging objects'
            iv_confirmationrequired = abap_true
            iv_clientrequesttoken = lv_token ).

        ov_job_id = oo_result->get_jobid( ).
        MESSAGE |S3 Batch job created: { ov_job_id }| TYPE 'I'.

      CATCH /aws1/cx_s3cbadrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cidempotencyex INTO DATA(lo_idem_ex).
        MESSAGE lo_idem_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_svc_ex).
        MESSAGE lo_svc_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3ctoomanyrequestsex INTO DATA(lo_thr_ex).
        MESSAGE lo_thr_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.create_job]
  ENDMETHOD.


  METHOD describe_job.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.describe_job]
    TRY.
        DATA(oo_result) = lo_s3c->describejob(
            iv_accountid = iv_account_id
            iv_jobid     = iv_job_id ).

        IF oo_result IS NOT INITIAL.
          DATA(lo_job) = oo_result->get_job( ).
          IF lo_job IS NOT INITIAL.
            DATA(lv_status)  = lo_job->get_status( ).
            DATA(lv_role)    = lo_job->get_rolearn( ).
            DATA(lv_priority) = lo_job->get_priority( ).

            DATA(lo_progress) = lo_job->get_progresssummary( ).
            DATA lv_total TYPE /aws1/s3cjobtotalnumberoftasks.
            DATA lv_succeeded TYPE /aws1/s3cjobnumberoftaskssucc.
            DATA lv_failed TYPE /aws1/s3cjobnumoftasksfailed.
            IF lo_progress IS NOT INITIAL.
              lv_total     = lo_progress->get_totalnumberoftasks( ).
              lv_succeeded = lo_progress->get_numberoftaskssucceeded( ).
              lv_failed    = lo_progress->get_numberoftasksfailed( ).
            ENDIF.

            MESSAGE |Job { iv_job_id } status: { lv_status } | &&
                    |Priority: { lv_priority } | &&
                    |Total: { lv_total } Succeeded: { lv_succeeded } | &&
                    |Failed: { lv_failed }| TYPE 'I'.
          ENDIF.
        ENDIF.

      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_nfe).
        MESSAGE lo_nfe->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cbadrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_svc_ex).
        MESSAGE lo_svc_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.describe_job]
  ENDMETHOD.


  METHOD update_job_priority.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.update_job_priority]
    TRY.
        " Priority value — e.g. 60
        DATA(oo_result) = lo_s3c->updatejobpriority(
            iv_accountid = iv_account_id
            iv_jobid     = iv_job_id
            iv_priority  = iv_priority ).

        MESSAGE |Job { oo_result->get_jobid( ) } priority updated to | &&
                |{ oo_result->get_priority( ) }| TYPE 'I'.

      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_nfe).
        MESSAGE lo_nfe->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cbadrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_svc_ex).
        MESSAGE lo_svc_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.update_job_priority]
  ENDMETHOD.


  METHOD update_job_status.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.update_job_status]
    TRY.
        " RequestedJobStatus values: 'Cancelled' | 'Ready'
        DATA(oo_result) = lo_s3c->updatejobstatus(
            iv_accountid          = iv_account_id
            iv_jobid              = iv_job_id
            iv_requestedjobstatus = iv_req_status ).

        MESSAGE |Job { oo_result->get_jobid( ) } status updated to | &&
                |{ oo_result->get_status( ) }| TYPE 'I'.

      CATCH /aws1/cx_s3cjobstatusexception INTO DATA(lo_jse).
        MESSAGE lo_jse->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_nfe).
        MESSAGE lo_nfe->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cbadrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_svc_ex).
        MESSAGE lo_svc_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.update_job_status]
  ENDMETHOD.


  METHOD get_job_tagging.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.get_job_tagging]
    TRY.
        DATA(oo_result) = lo_s3c->getjobtagging(
            iv_accountid = iv_account_id
            iv_jobid     = iv_job_id ).

        DATA(lt_tags) = oo_result->get_tags( ).
        MESSAGE |Retrieved { lines( lt_tags ) } tag(s) for job { iv_job_id }| TYPE 'I'.

      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_nfe).
        MESSAGE lo_nfe->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_svc_ex).
        MESSAGE lo_svc_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'E'.
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
            iv_key   = 'Environment'
            iv_value = 'Development' ) TO lt_tags.
        APPEND NEW /aws1/cl_s3cs3tag(
            iv_key   = 'Team'
            iv_value = 'DataProcessing' ) TO lt_tags.

        lo_s3c->putjobtagging(
            iv_accountid = iv_account_id
            iv_jobid     = iv_job_id
            it_tags      = lt_tags ).

        MESSAGE |Tags added to job { iv_job_id }| TYPE 'I'.

      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_nfe).
        MESSAGE lo_nfe->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3ctoomanytagsex INTO DATA(lo_tag_ex).
        MESSAGE lo_tag_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_svc_ex).
        MESSAGE lo_svc_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.put_job_tagging]
  ENDMETHOD.


  METHOD list_jobs.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.list_jobs]
    TRY.
        " Retrieve jobs across all statuses
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
            iv_accountid  = iv_account_id
            it_jobstatuses = lt_statuses ).

        DATA(lt_jobs) = oo_result->get_jobs( ).
        MESSAGE |Retrieved { lines( lt_jobs ) } S3 Batch job(s)| TYPE 'I'.

      CATCH /aws1/cx_s3cinvalidrequestex INTO DATA(lo_inv_ex).
        MESSAGE lo_inv_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cinvalidnexttokenex INTO DATA(lo_tok_ex).
        MESSAGE lo_tok_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_svc_ex).
        MESSAGE lo_svc_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'E'.
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
            iv_jobid     = iv_job_id ).

        MESSAGE |Tags deleted for job { iv_job_id }| TYPE 'I'.

      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_nfe).
        MESSAGE lo_nfe->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_svc_ex).
        MESSAGE lo_svc_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.delete_job_tagging]
  ENDMETHOD.

ENDCLASS.
