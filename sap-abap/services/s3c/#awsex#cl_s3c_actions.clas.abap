" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS /awsex/cl_s3c_actions DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    METHODS create_job
      IMPORTING
                !iv_account_id      TYPE /aws1/s3caccountid
                !iv_role_arn         TYPE /aws1/s3ciamrolearn
                !iv_manifest_arn     TYPE /aws1/s3cs3keyarnstring
                !iv_manifest_etag    TYPE /aws1/s3cnonemptymaxlength1024st
                !iv_report_bucket    TYPE /aws1/s3cs3bucketarnstring
      RETURNING VALUE(ov_job_id)     TYPE /aws1/s3cjobid
      RAISING   /aws1/cx_rt_generic.

    METHODS update_job_priority
      IMPORTING
                !iv_account_id TYPE /aws1/s3caccountid
                !iv_job_id     TYPE /aws1/s3cjobid
                !iv_priority   TYPE /aws1/s3cjobpriority
      RETURNING VALUE(oo_result) TYPE REF TO /aws1/cl_s3cupdjobpriorityrslt
      RAISING   /aws1/cx_rt_generic.

    METHODS update_job_status
      IMPORTING
                !iv_account_id  TYPE /aws1/s3caccountid
                !iv_job_id      TYPE /aws1/s3cjobid
                !iv_req_status  TYPE /aws1/s3crequestedjobstatus
      RETURNING VALUE(oo_result) TYPE REF TO /aws1/cl_s3cupdjobstatusrslt
      RAISING   /aws1/cx_rt_generic.

    METHODS describe_job
      IMPORTING
                !iv_account_id TYPE /aws1/s3caccountid
                !iv_job_id     TYPE /aws1/s3cjobid
      RETURNING VALUE(oo_result) TYPE REF TO /aws1/cl_s3cdescribejobresult
      RAISING   /aws1/cx_rt_generic.

    METHODS get_job_tagging
      IMPORTING
                !iv_account_id TYPE /aws1/s3caccountid
                !iv_job_id     TYPE /aws1/s3cjobid
      RETURNING VALUE(oo_result) TYPE REF TO /aws1/cl_s3cgetjobtagresult
      RAISING   /aws1/cx_rt_generic.

    METHODS put_job_tagging
      IMPORTING
                !iv_account_id TYPE /aws1/s3caccountid
                !iv_job_id     TYPE /aws1/s3cjobid
                !it_tags        TYPE /aws1/cl_s3cs3tag=>tt_s3tagset
      RAISING   /aws1/cx_rt_generic.

    METHODS list_jobs
      IMPORTING
                !iv_account_id TYPE /aws1/s3caccountid
      RETURNING VALUE(oo_result) TYPE REF TO /aws1/cl_s3clistjobsresult
      RAISING   /aws1/cx_rt_generic.

    METHODS delete_job_tagging
      IMPORTING
                !iv_account_id TYPE /aws1/s3caccountid
                !iv_job_id     TYPE /aws1/s3cjobid
      RAISING   /aws1/cx_rt_generic.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS /awsex/cl_s3c_actions IMPLEMENTATION.


  METHOD create_job.

    " snippet-start:[s3c.abapv1.create_job]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    TRY.
        " Build the S3PutObjectTagging operation
        DATA lt_tagset TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
        APPEND NEW /aws1/cl_s3cs3tag(
          iv_key   = 'BatchTag'
          iv_value = 'BatchValue' ) TO lt_tagset.

        DATA(lo_operation) = NEW /aws1/cl_s3cjoboperation(
          io_s3putobjecttagging = NEW /aws1/cl_s3cs3setobjecttagop(
            it_tagset = lt_tagset ) ).

        " Build the manifest
        " iv_manifest_arn example: 'arn:aws:s3:::my-bucket/job-manifest.csv'
        " iv_manifest_etag example: 'abc1234def5678'
        DATA(lo_manifest) = NEW /aws1/cl_s3cjobmanifest(
          io_spec = NEW /aws1/cl_s3cjobmanifestspec(
            iv_format = 'S3BatchOperations_CSV_20180820'
            it_fields = VALUE /aws1/cl_s3cjobmanifestfield00=>tt_jobmanifestfieldlist(
              ( NEW /aws1/cl_s3cjobmanifestfield00( 'Bucket' ) )
              ( NEW /aws1/cl_s3cjobmanifestfield00( 'Key' ) ) ) )
          io_location = NEW /aws1/cl_s3cjobmanifestloc(
            iv_objectarn = iv_manifest_arn
            iv_etag      = iv_manifest_etag ) ).

        " Build the job report
        " iv_report_bucket example: 'arn:aws:s3:::my-report-bucket'
        DATA(lo_report) = NEW /aws1/cl_s3cjobreport(
          iv_bucket      = iv_report_bucket
          iv_format      = 'Report_CSV_20180820'
          iv_enabled     = abap_true
          iv_prefix      = 'batch-op-reports'
          iv_reportscope = 'AllTasks' ).

        " Generate a unique client request token using UUID
        DATA lv_uuid_string TYPE string.
        DATA lv_uuid TYPE sysuuid_x16.
        TRY.
            cl_system_uuid=>create_uuid_x16_static( IMPORTING uuid = lv_uuid ).
          CATCH cx_uuid_error.
            lv_uuid = '00000000000000000000000000000001'.
        ENDTRY.
        lv_uuid_string = lv_uuid.

        DATA(lo_result) = lo_s3c->createjob(
          iv_accountid           = iv_account_id
          io_operation           = lo_operation
          io_report              = lo_report
          io_manifest            = lo_manifest
          iv_priority            = 10
          iv_rolearn             = iv_role_arn
          iv_description         = 'Batch job for tagging objects'
          iv_confirmationrequired = abap_true
          iv_clientrequesttoken  = lv_uuid_string ).

        ov_job_id = lo_result->get_jobid( ).
        MESSAGE |Batch job created: { ov_job_id }| TYPE 'I'.

      CATCH /aws1/cx_s3cbadrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cidempotencyex INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_ex3).
        MESSAGE lo_ex3->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.create_job]

  ENDMETHOD.


  METHOD update_job_priority.

    " snippet-start:[s3c.abapv1.update_job_priority]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    TRY.
        " iv_priority example: 60
        oo_result = lo_s3c->updatejobpriority(
          iv_accountid = iv_account_id
          iv_jobid     = iv_job_id
          iv_priority  = iv_priority ).

        MESSAGE |Job { oo_result->get_jobid( ) } priority updated to { oo_result->get_priority( ) }| TYPE 'I'.

      CATCH /aws1/cx_s3cbadrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3ctoomanyrequestsex INTO DATA(lo_ex3).
        MESSAGE lo_ex3->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.update_job_priority]

  ENDMETHOD.


  METHOD update_job_status.

    " snippet-start:[s3c.abapv1.update_job_status]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    TRY.
        " iv_req_status examples: 'Cancelled', 'Ready'
        oo_result = lo_s3c->updatejobstatus(
          iv_accountid          = iv_account_id
          iv_jobid              = iv_job_id
          iv_requestedjobstatus = iv_req_status ).

        MESSAGE |Job { oo_result->get_jobid( ) } status changed to { oo_result->get_status( ) }| TYPE 'I'.

      CATCH /aws1/cx_s3cbadrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cjobstatusexception INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex3).
        MESSAGE lo_ex3->get_text( ) TYPE 'I'.
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
          iv_jobid     = iv_job_id ).

        DATA(lo_job) = oo_result->get_job( ).
        IF lo_job IS NOT INITIAL.
          DATA(lv_status)   = lo_job->get_status( ).
          DATA(lv_priority) = lo_job->get_priority( ).
          DATA(lv_desc)     = lo_job->get_description( ).
          DATA(lo_progress) = lo_job->get_progresssummary( ).

          MESSAGE |Job ID: { lo_job->get_jobid( ) } Status: { lv_status }| TYPE 'I'.
          MESSAGE |Description: { lv_desc } Priority: { lv_priority }| TYPE 'I'.

          IF lo_progress IS NOT INITIAL.
            MESSAGE |Progress: Total={ lo_progress->get_totalnumberoftasks( ) }| &&
                    | Succeeded={ lo_progress->get_numberoftaskssucceeded( ) }| &&
                    | Failed={ lo_progress->get_numberoftasksfailed( ) }| TYPE 'I'.
          ENDIF.
        ENDIF.

      CATCH /aws1/cx_s3cbadrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
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
          iv_jobid     = iv_job_id ).

        DATA(lt_tags) = oo_result->get_tags( ).
        IF lt_tags IS NOT INITIAL.
          MESSAGE |Retrieved { lines( lt_tags ) } tag(s) for job { iv_job_id }| TYPE 'I'.
        ELSE.
          MESSAGE |No tags found for job { iv_job_id }| TYPE 'I'.
        ENDIF.

      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3ctoomanyrequestsex INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.get_job_tagging]

  ENDMETHOD.


  METHOD put_job_tagging.

    " snippet-start:[s3c.abapv1.put_job_tagging]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

    TRY.
        " it_tags example:
        "   VALUE /aws1/cl_s3cs3tag=>tt_s3tagset(
        "     ( NEW /aws1/cl_s3cs3tag( iv_key = 'Environment' iv_value = 'Development' ) )
        "     ( NEW /aws1/cl_s3cs3tag( iv_key = 'Team' iv_value = 'DataProcessing' ) ) )
        lo_s3c->putjobtagging(
          iv_accountid = iv_account_id
          iv_jobid     = iv_job_id
          it_tags      = it_tags ).

        MESSAGE |Tags added to job { iv_job_id }| TYPE 'I'.

      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3ctoomanytagsex INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3ctoomanyrequestsex INTO DATA(lo_ex3).
        MESSAGE lo_ex3->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.put_job_tagging]

  ENDMETHOD.


  METHOD list_jobs.

    " snippet-start:[s3c.abapv1.list_jobs]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_s3c) = /aws1/cl_s3c_factory=>create( lo_session ).

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
          it_jobstatuses = lt_statuses ).

        MESSAGE |Retrieved { lines( oo_result->get_jobs( ) ) } S3 Batch Operations job(s)| TYPE 'I'.

      CATCH /aws1/cx_s3cinternalserviceex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3cinvalidrequestex INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
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
          iv_jobid     = iv_job_id ).

        MESSAGE |Tags deleted for job { iv_job_id }| TYPE 'I'.

      CATCH /aws1/cx_s3cnotfoundexception INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
      CATCH /aws1/cx_s3ctoomanyrequestsex INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[s3c.abapv1.delete_job_tagging]

  ENDMETHOD.

ENDCLASS.
