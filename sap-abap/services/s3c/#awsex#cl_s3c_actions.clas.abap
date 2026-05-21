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
        iv_account_id    TYPE /aws1/s3caccountid
        iv_job_id        TYPE /aws1/s3cjobid
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_s3cupdjobpriorityrslt.

    METHODS update_job_status
      IMPORTING
        iv_account_id    TYPE /aws1/s3caccountid
        iv_job_id        TYPE /aws1/s3cjobid
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_s3cupdjobstatusrslt.

    METHODS describe_job
      IMPORTING
        iv_account_id    TYPE /aws1/s3caccountid
        iv_job_id        TYPE /aws1/s3cjobid
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_s3cdescribejobresult.

    METHODS get_job_tagging
      IMPORTING
        iv_account_id    TYPE /aws1/s3caccountid
        iv_job_id        TYPE /aws1/s3cjobid
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_s3cgetjobtagresult.

    METHODS put_job_tagging
      IMPORTING
        iv_account_id  TYPE /aws1/s3caccountid
        iv_job_id      TYPE /aws1/s3cjobid.

    METHODS list_jobs
      IMPORTING
        iv_account_id    TYPE /aws1/s3caccountid
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_s3clistjobsresult.

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
        " Build tag set for the objects to be tagged by the batch job
        DATA lt_tagset TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
        APPEND NEW /aws1/cl_s3cs3tag(
          iv_key   = 'BatchTag'   " e.g. 'project'
          iv_value = 'BatchValue' " e.g. 'my-project'
        ) TO lt_tagset.

        " Build manifest field list: Bucket and Key columns
        DATA lt_fields TYPE /aws1/cl_s3cjobmanifestfield00=>tt_jobmanifestfieldlist.
        APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Bucket' ) TO lt_fields.
        APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Key' )    TO lt_fields.

        DATA(oo_result) = lo_s3c->createjob(
          iv_accountid          = iv_account_id
          iv_rolearn            = iv_role_arn
          iv_priority           = 10
          iv_confirmationrequired = abap_true
          iv_description        = 'Batch job for tagging objects'
          io_operation          = NEW /aws1/cl_s3cjoboperation(
            io_s3putobjecttagging = NEW /aws1/cl_s3cs3setobjecttagop(
              it_tagset = lt_tagset
            )
          )
          io_manifest           = NEW /aws1/cl_s3cjobmanifest(
            io_spec     = NEW /aws1/cl_s3cjobmanifestspec(
              iv_format = 'S3BatchOperations_CSV_20180820'
              it_fields = lt_fields
            )
            io_location = NEW /aws1/cl_s3cjobmanifestloc(
              iv_objectarn = iv_manifest_arn
              iv_etag      = iv_manifest_etag
            )
          )
          io_report             = NEW /aws1/cl_s3cjobreport(
            iv_bucket      = iv_report_bucket
            iv_format      = 'Report_CSV_20180820'
            iv_enabled     = abap_true
            iv_prefix      = 'batch-op-reports'
            iv_reportscope = 'AllTasks'
          )
        ).
        ov_job_id = oo_result->get_jobid( ).
        MESSAGE |S3 Batch job created: { ov_job_id }| TYPE 'I'.
      CATCH /aws1/cx_s3cbadrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_server_ex).
        MESSAGE lo_server_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.create_job]
  ENDMETHOD.


  METHOD update_job_priority.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.update_job_priority]
    TRY.
        oo_result = lo_s3c->updatejobpriority(
          iv_accountid = iv_account_id
          iv_jobid     = iv_job_id
          iv_priority  = 60
        ).
        MESSAGE |Job priority updated: { oo_result->get_jobid( ) } new priority: { oo_result->get_priority( ) }| TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_server_ex).
        MESSAGE lo_server_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.update_job_priority]
  ENDMETHOD.


  METHOD update_job_status.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.update_job_status]
    TRY.
        oo_result = lo_s3c->updatejobstatus(
          iv_accountid           = iv_account_id
          iv_jobid               = iv_job_id
          iv_requestedjobstatus  = 'Cancelled'
          iv_statusupdatereason  = 'Cancelled by example scenario'
        ).
        MESSAGE |Job { oo_result->get_jobid( ) } status updated to: { oo_result->get_status( ) }| TYPE 'I'.
      CATCH /aws1/cx_s3cjobstatusexception INTO DATA(lo_status_ex).
        MESSAGE lo_status_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_server_ex).
        MESSAGE lo_server_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.update_job_status]
  ENDMETHOD.


  METHOD describe_job.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.describe_job]
    TRY.
        oo_result = lo_s3c->describejob(
          iv_accountid = iv_account_id
          iv_jobid     = iv_job_id
        ).
        DATA(lo_job) = oo_result->get_job( ).
        IF lo_job IS BOUND.
          DATA(lv_status)   = lo_job->get_status( ).
          DATA(lv_priority) = lo_job->get_priority( ).
          DATA(lo_progress) = lo_job->get_progresssummary( ).
          DATA lv_total    TYPE /aws1/s3cjobtotalnumberoftasks.
          DATA lv_succ     TYPE /aws1/s3cjobnumberoftaskssucc.
          DATA lv_failed   TYPE /aws1/s3cjobnumoftasksfailed.
          IF lo_progress IS BOUND.
            lv_total  = lo_progress->get_totalnumberoftasks( ).
            lv_succ   = lo_progress->get_numberoftaskssucceeded( ).
            lv_failed = lo_progress->get_numberoftasksfailed( ).
          ENDIF.
          MESSAGE |Job { iv_job_id } status: { lv_status } priority: { lv_priority } | &&
                  |total: { lv_total } succeeded: { lv_succ } failed: { lv_failed }| TYPE 'I'.
        ENDIF.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_server_ex).
        MESSAGE lo_server_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.describe_job]
  ENDMETHOD.


  METHOD get_job_tagging.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.get_job_tagging]
    TRY.
        oo_result = lo_s3c->getjobtagging(
          iv_accountid = iv_account_id
          iv_jobid     = iv_job_id
        ).
        DATA(lt_tags) = oo_result->get_tags( ).
        MESSAGE |Retrieved { lines( lt_tags ) } tag(s) for job { iv_job_id }| TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_server_ex).
        MESSAGE lo_server_ex->get_text( ) TYPE 'I'.
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
          iv_key   = 'Environment' " e.g. 'project'
          iv_value = 'Development' " e.g. 'my-project'
        ) TO lt_tags.
        APPEND NEW /aws1/cl_s3cs3tag(
          iv_key   = 'Team'           " e.g. 'owner'
          iv_value = 'DataProcessing' " e.g. 'my-team'
        ) TO lt_tags.

        lo_s3c->putjobtagging(
          iv_accountid = iv_account_id
          iv_jobid     = iv_job_id
          it_tags      = lt_tags
        ).
        MESSAGE |{ lines( lt_tags ) } tag(s) added to job { iv_job_id }| TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3ctoomanytagsex INTO DATA(lo_tags_ex).
        MESSAGE lo_tags_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_server_ex).
        MESSAGE lo_server_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.put_job_tagging]
  ENDMETHOD.


  METHOD list_jobs.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    " snippet-start:[s3c.abapv1.list_jobs]
    TRY.
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

        oo_result = lo_s3c->listjobs(
          iv_accountid   = iv_account_id
          it_jobstatuses = lt_statuses
        ).
        DATA(lt_jobs) = oo_result->get_jobs( ).
        MESSAGE |Listed { lines( lt_jobs ) } S3 Batch job(s)| TYPE 'I'.
      CATCH /aws1/cx_s3cinvalidrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_server_ex).
        MESSAGE lo_server_ex->get_text( ) TYPE 'I'.
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
        MESSAGE |All tags deleted from job { iv_job_id }| TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cserverexc INTO DATA(lo_server_ex).
        MESSAGE lo_server_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.delete_job_tagging]
  ENDMETHOD.

ENDCLASS.
