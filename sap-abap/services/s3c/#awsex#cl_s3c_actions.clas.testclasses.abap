" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_s3c_actions DEFINITION DEFERRED.
CLASS /awsex/cl_s3c_actions DEFINITION LOCAL FRIENDS ltc_s3c_actions.

CLASS ltc_s3c_actions DEFINITION FOR TESTING
  DURATION LONG
  RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl          TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    CONSTANTS cv_role_name    TYPE /aws1/iamrolenametype VALUE 'S3BatchOpsExampleRole'.
    CONSTANTS cv_policy_name  TYPE /aws1/iampolicynametype VALUE 'S3BatchOpsExamplePolicy'.

    " ---------------------------------------------------------------
    " Shared clients and the class-under-test
    " ---------------------------------------------------------------
    CLASS-DATA ao_s3c      TYPE REF TO /aws1/if_s3c.
    CLASS-DATA ao_s3       TYPE REF TO /aws1/if_s3.
    CLASS-DATA ao_iam      TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_session  TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_actions  TYPE REF TO /awsex/cl_s3c_actions.

    " ---------------------------------------------------------------
    " Test-resource state (all created fresh in class_setup)
    " ---------------------------------------------------------------
    CLASS-DATA av_account_id     TYPE /aws1/s3caccountid.
    CLASS-DATA av_s3_bucket      TYPE /aws1/s3_bucketname.
    CLASS-DATA av_bucket_arn     TYPE /aws1/s3cs3bucketarnstring.
    CLASS-DATA av_manifest_arn   TYPE /aws1/s3cs3keyarnstring.
    CLASS-DATA av_manifest_etag  TYPE /aws1/s3cnonemptymaxlength1000.
    CLASS-DATA av_role_arn       TYPE /aws1/s3ciamrolearn.

    " Shared read-only job (describe, get_tag, list tests)
    CLASS-DATA av_job_id         TYPE /aws1/s3cjobid.

    " Dedicated jobs for mutation tests – each test gets its own
    CLASS-DATA av_job_id_prio    TYPE /aws1/s3cjobid.
    CLASS-DATA av_job_id_cancel  TYPE /aws1/s3cjobid.
    CLASS-DATA av_job_id_puttag  TYPE /aws1/s3cjobid.
    CLASS-DATA av_job_id_deltag  TYPE /aws1/s3cjobid.

    " ---------------------------------------------------------------
    " Lifecycle hooks
    " ---------------------------------------------------------------
    CLASS-METHODS class_setup
      RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_teardown
      RAISING /aws1/cx_rt_generic.

    " ---------------------------------------------------------------
    " Internal helpers
    " ---------------------------------------------------------------
    CLASS-METHODS create_test_job
      RETURNING VALUE(rv_job_id) TYPE /aws1/s3cjobid
      RAISING   /aws1/cx_rt_generic.

    " Poll until the job reaches one of the supplied statuses (or fail)
    CLASS-METHODS wait_for_job
      IMPORTING iv_job_id          TYPE /aws1/s3cjobid
                it_target_statuses TYPE string_table
      RAISING   /aws1/cx_rt_generic.

    " ---------------------------------------------------------------
    " Test methods – one per action
    " ---------------------------------------------------------------
    METHODS create_job          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS describe_job        FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_job_priority FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_job_status   FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS get_job_tagging     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS put_job_tagging     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_jobs           FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_job_tagging  FOR TESTING RAISING /aws1/cx_rt_generic.

ENDCLASS.


CLASS ltc_s3c_actions IMPLEMENTATION.

" =====================================================================
"  CLASS_SETUP
" =====================================================================
  METHOD class_setup.
    ao_session = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_s3c     = /aws1/cl_s3c_factory=>create( ao_session ).
    ao_s3      = /aws1/cl_s3_factory=>create( ao_session ).
    ao_iam     = /aws1/cl_iam_factory=>create( ao_session ).
    ao_actions = NEW /awsex/cl_s3c_actions( ).

    av_account_id = ao_session->get_account_id( ).

    " ----------------------------------------------------------------
    " 1.  S3 bucket  (manifest + report destination)
    "     Use /awsex/cl_utils=>create_bucket so region constraint is
    "     handled correctly.  Tag immediately after creation.
    " ----------------------------------------------------------------
    av_s3_bucket = |sap-abap-s3c-{ av_account_id }|.

    /awsex/cl_utils=>create_bucket(
      iv_bucket  = av_s3_bucket
      io_s3      = ao_s3
      io_session = ao_session ).

    DATA lt_s3_tags TYPE /aws1/cl_s3_tag=>tt_tagset.
    APPEND NEW /aws1/cl_s3_tag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_s3_tags.
    ao_s3->putbuckettagging(
      iv_bucket  = av_s3_bucket
      io_tagging = NEW /aws1/cl_s3_tagging( it_tagset = lt_s3_tags ) ).

    " ARN used in report and manifest location
    av_bucket_arn  = |arn:aws:s3:::{ av_s3_bucket }|.
    av_manifest_arn = |arn:aws:s3:::{ av_s3_bucket }/job-manifest.csv|.

    " ----------------------------------------------------------------
    " 2.  Manifest object
    "     The CSV must reference a real bucket name; the key does not
    "     have to exist for CreateJob to succeed with
    "     ConfirmationRequired=true (job stays Suspended).
    " ----------------------------------------------------------------
    DATA lv_csv TYPE string.
    lv_csv = |{ av_s3_bucket },dummy-object.txt\n|.

    DATA(lo_put) = ao_s3->putobject(
      iv_bucket = av_s3_bucket
      iv_key    = 'job-manifest.csv'
      iv_body   = cl_abap_codepage=>convert_to( lv_csv ) ).

    " S3 returns the ETag wrapped in double-quotes; strip them.
    av_manifest_etag = lo_put->get_etag( ).
    REPLACE ALL OCCURRENCES OF '"' IN av_manifest_etag WITH ''.

    " ----------------------------------------------------------------
    " 3.  IAM role for S3 Batch Operations
    "     Always (re)create the role so the exact policy the tests
    "     require is applied.  The correct permissions come straight
    "     from the AWS documentation for PutObjectTagging jobs:
    "
    "       s3:PutObjectTagging / s3:PutObjectVersionTagging  →  target bucket
    "       s3:GetObject / s3:GetObjectVersion                →  manifest bucket
    "       s3:PutObject                                      →  report bucket
    "
    "     Because all three are the same bucket here we can use a
    "     single wildcard statement over that one bucket.
    " ----------------------------------------------------------------
    DATA lv_trust TYPE string.
    lv_trust =
      '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",' &&
      '"Principal":{"Service":"batchoperations.s3.amazonaws.com"},' &&
      '"Action":"sts:AssumeRole"}]}'.

    TRY.
        DATA(lo_cr) = ao_iam->createrole(
          iv_rolename                 = cv_role_name
          iv_assumerolepolicydocument = lv_trust
          iv_description              = 'S3 Batch Ops role for ABAP unit tests'
          it_tags                     = VALUE /aws1/cl_iamtag=>tt_taglisttype(
            ( NEW /aws1/cl_iamtag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).
        av_role_arn = lo_cr->get_role( )->get_arn( ).
      CATCH /aws1/cx_iamentityalrdyexex.
        DATA(lo_gr) = ao_iam->getrole( iv_rolename = cv_role_name ).
        av_role_arn = lo_gr->get_role( )->get_arn( ).
    ENDTRY.

    cl_abap_unit_assert=>assert_not_initial(
      act = av_role_arn
      msg = 'Could not obtain IAM role ARN' ).

    " Build the exact permissions policy the AWS documentation specifies
    " for a PutObjectTagging S3 Batch job.
    DATA lv_bkt TYPE string.
    lv_bkt = av_s3_bucket.
    DATA lv_perms TYPE string.
    lv_perms =
      '{"Version":"2012-10-17","Statement":[' &&
        '{"Sid":"AllowTagging","Effect":"Allow",' &&
         '"Action":["s3:PutObjectTagging","s3:PutObjectVersionTagging"],' &&
         '"Resource":"arn:aws:s3:::' && lv_bkt && '/*"},' &&
        '{"Sid":"AllowManifestRead","Effect":"Allow",' &&
         '"Action":["s3:GetObject","s3:GetObjectVersion"],' &&
         '"Resource":"arn:aws:s3:::' && lv_bkt && '/*"},' &&
        '{"Sid":"AllowReportWrite","Effect":"Allow",' &&
         '"Action":["s3:PutObject"],' &&
         '"Resource":"arn:aws:s3:::' && lv_bkt && '/*"}' &&
      ']}' .

    ao_iam->putrolepolicy(
      iv_rolename       = cv_role_name
      iv_policyname     = cv_policy_name
      iv_policydocument = lv_perms ).

    " IAM changes take a few seconds to propagate globally
    WAIT UP TO 15 SECONDS.

    " ----------------------------------------------------------------
    " 4.  Pre-create the jobs needed by the read-only and mutation tests
    " ----------------------------------------------------------------
    av_job_id        = create_test_job( ).
    av_job_id_prio   = create_test_job( ).
    av_job_id_cancel = create_test_job( ).
    av_job_id_puttag = create_test_job( ).
    av_job_id_deltag = create_test_job( ).

    cl_abap_unit_assert=>assert_not_initial( act = av_job_id        msg = 'Shared job was not created' ).
    cl_abap_unit_assert=>assert_not_initial( act = av_job_id_prio   msg = 'Priority job was not created' ).
    cl_abap_unit_assert=>assert_not_initial( act = av_job_id_cancel msg = 'Cancel job was not created' ).
    cl_abap_unit_assert=>assert_not_initial( act = av_job_id_puttag msg = 'PutTag job was not created' ).
    cl_abap_unit_assert=>assert_not_initial( act = av_job_id_deltag msg = 'DelTag job was not created' ).

    " Wait for all jobs to leave the 'New'/'Preparing' transient states.
    " With ConfirmationRequired=true they land in Suspended.
    DATA lt_ok TYPE string_table.
    APPEND 'Suspended' TO lt_ok.
    APPEND 'Ready'     TO lt_ok.
    APPEND 'Active'    TO lt_ok.
    APPEND 'Complete'  TO lt_ok.
    APPEND 'Failed'    TO lt_ok.
    APPEND 'Cancelled' TO lt_ok.

    wait_for_job( iv_job_id = av_job_id        it_target_statuses = lt_ok ).
    wait_for_job( iv_job_id = av_job_id_prio   it_target_statuses = lt_ok ).
    wait_for_job( iv_job_id = av_job_id_cancel it_target_statuses = lt_ok ).
    wait_for_job( iv_job_id = av_job_id_puttag it_target_statuses = lt_ok ).
    wait_for_job( iv_job_id = av_job_id_deltag it_target_statuses = lt_ok ).
  ENDMETHOD.


" =====================================================================
"  CLASS_TEARDOWN
" =====================================================================
  METHOD class_teardown.
    " Cancel every job that is still in a cancellable state
    DATA lt_ids TYPE string_table.
    APPEND av_job_id        TO lt_ids.
    APPEND av_job_id_prio   TO lt_ids.
    APPEND av_job_id_cancel TO lt_ids.
    APPEND av_job_id_puttag TO lt_ids.
    APPEND av_job_id_deltag TO lt_ids.

    LOOP AT lt_ids INTO DATA(lv_id).
      CHECK lv_id IS NOT INITIAL.
      TRY.
          DATA(lv_st) = ao_s3c->describejob(
            iv_accountid = av_account_id
            iv_jobid     = lv_id )->get_job( )->get_status( ).
          IF lv_st = 'Suspended' OR lv_st = 'Ready' OR lv_st = 'Active'.
            ao_s3c->updatejobstatus(
              iv_accountid          = av_account_id
              iv_jobid              = lv_id
              iv_requestedjobstatus = 'Cancelled' ).
          ENDIF.
        CATCH /aws1/cx_rt_generic.           " Best-effort
      ENDTRY.
    ENDLOOP.

    " Clean up the S3 bucket (objects + bucket itself)
    IF av_s3_bucket IS NOT INITIAL.
      TRY.
          /awsex/cl_utils=>cleanup_bucket(
            iv_bucket = av_s3_bucket
            io_s3     = ao_s3 ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " Remove the inline policy then delete the IAM role.
    " The role is tagged 'convert_test=true' so it can also be
    " located and cleaned up manually if needed.
    TRY.
        ao_iam->deleterolepolicy(
          iv_rolename  = cv_role_name
          iv_policyname = cv_policy_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iam->deleterole( iv_rolename = cv_role_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


" =====================================================================
"  HELPER – create_test_job
" =====================================================================
  METHOD create_test_job.
    " Use /awsex/cl_utils=>get_random_string for the idempotency token
    DATA lv_token TYPE string.
    lv_token = /awsex/cl_utils=>get_random_string( ).
    CONDENSE lv_token NO-GAPS.

    " Tag set for the batch operation itself
    DATA lt_tagset TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag(
      iv_key   = 'BatchTag'
      iv_value = 'BatchValue' ) TO lt_tagset.

    " Manifest field list: Bucket, Key
    DATA lt_fields TYPE /aws1/cl_s3cjobmanifestfield00=>tt_jobmanifestfieldlist.
    APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Bucket' ) TO lt_fields.
    APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Key' )    TO lt_fields.

    DATA(lo_result) = ao_s3c->createjob(
      iv_accountid            = av_account_id
      " ConfirmationRequired=true keeps the job in Suspended so it
      " never actually processes objects during the unit test.
      iv_confirmationrequired = abap_true
      iv_priority             = 10
      iv_rolearn              = av_role_arn
      iv_description          = 'ABAP unit test – S3C batch job'
      iv_clientrequesttoken   = lv_token
      io_operation            = NEW /aws1/cl_s3cjoboperation(
        io_s3putobjecttagging = NEW /aws1/cl_s3cs3setobjecttagop(
          it_tagset = lt_tagset ) )
      io_report               = NEW /aws1/cl_s3cjobreport(
        iv_bucket      = av_bucket_arn
        iv_format      = 'Report_CSV_20180820'
        iv_enabled     = abap_true
        iv_prefix      = 'batch-op-reports'
        iv_reportscope = 'AllTasks' )
      io_manifest             = NEW /aws1/cl_s3cjobmanifest(
        io_spec     = NEW /aws1/cl_s3cjobmanifestspec(
          iv_format = 'S3BatchOperations_CSV_20180820'
          it_fields = lt_fields )
        io_location = NEW /aws1/cl_s3cjobmanifestloc(
          iv_objectarn = av_manifest_arn
          iv_etag      = av_manifest_etag ) ) ).

    rv_job_id = lo_result->get_jobid( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = rv_job_id
      msg = 'create_test_job: CreateJob returned empty job ID' ).
  ENDMETHOD.


" =====================================================================
"  HELPER – wait_for_job
" =====================================================================
  METHOD wait_for_job.
    CONSTANTS cv_max_attempts TYPE i VALUE 60.   " 60 × 5 s = 5 min
    DATA lv_attempt TYPE i.

    DO cv_max_attempts TIMES.
      lv_attempt = sy-index.

      DATA(lv_status) = ao_s3c->describejob(
        iv_accountid = av_account_id
        iv_jobid     = iv_job_id )->get_job( )->get_status( ).

      LOOP AT it_target_statuses INTO DATA(lv_target).
        IF lv_status = lv_target.
          RETURN.
        ENDIF.
      ENDLOOP.

      IF lv_attempt < cv_max_attempts.
        WAIT UP TO 5 SECONDS.
      ENDIF.
    ENDDO.

    " If we get here the job did not reach the desired state
    cl_abap_unit_assert=>fail(
      msg = |Job { iv_job_id } did not reach an expected status | &&
            |after { cv_max_attempts } attempts. | &&
            |Last status: { lv_status }| ).
  ENDMETHOD.


" =====================================================================
"  TEST: create_job
" =====================================================================
  METHOD create_job.
    " create_job is the action-under-test: it calls the ABAP SDK directly.
    DATA lv_new_job_id TYPE /aws1/s3cjobid.

    lv_new_job_id = ao_actions->create_job(
      iv_account_id     = av_account_id
      iv_role_arn       = av_role_arn
      iv_manifest_arn   = av_manifest_arn
      iv_manifest_etag  = av_manifest_etag
      iv_report_bkt_arn = av_bucket_arn ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_new_job_id
      msg = 'create_job must return a non-empty job ID' ).

    " Confirm the job really exists in S3 Batch
    DATA(lo_desc) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = lv_new_job_id ).

    cl_abap_unit_assert=>assert_equals(
      exp = lv_new_job_id
      act = lo_desc->get_job( )->get_jobid( )
      msg = |Created job { lv_new_job_id } was not found via DescribeJob| ).

    " Clean up: cancel the job so it does not linger as Suspended
    TRY.
        ao_s3c->updatejobstatus(
          iv_accountid          = av_account_id
          iv_jobid              = lv_new_job_id
          iv_requestedjobstatus = 'Cancelled' ).
      CATCH /aws1/cx_rt_generic.     " Best-effort
    ENDTRY.
  ENDMETHOD.


" =====================================================================
"  TEST: describe_job
" =====================================================================
  METHOD describe_job.
    " The shared job was created and has reached Suspended in class_setup.
    ao_actions->describe_job(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id ).

    " Validate the response directly so the test cannot silently pass
    DATA(lo_desc) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id ).

    DATA(lo_job) = lo_desc->get_job( ).

    cl_abap_unit_assert=>assert_equals(
      exp = av_job_id
      act = lo_job->get_jobid( )
      msg = 'DescribeJob returned wrong job ID' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_job->get_status( )
      msg = 'DescribeJob returned empty status' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_job->get_rolearn( )
      msg = 'DescribeJob returned empty role ARN' ).
  ENDMETHOD.


" =====================================================================
"  TEST: update_job_priority
" =====================================================================
  METHOD update_job_priority.
    " The priority job must be in Suspended or Ready for this call.
    DATA lt_mutable TYPE string_table.
    APPEND 'Suspended' TO lt_mutable.
    APPEND 'Ready'     TO lt_mutable.

    wait_for_job(
      iv_job_id          = av_job_id_prio
      it_target_statuses = lt_mutable ).

    " Call the action
    ao_actions->update_job_priority(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id_prio
      iv_priority   = 60 ).

    " Confirm the new priority
    DATA(lo_desc) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_prio ).

    cl_abap_unit_assert=>assert_equals(
      exp = 60
      act = lo_desc->get_job( )->get_priority( )
      msg = |Job { av_job_id_prio } priority was not updated to 60| ).
  ENDMETHOD.


" =====================================================================
"  TEST: update_job_status  (cancels av_job_id_cancel)
" =====================================================================
  METHOD update_job_status.
    " Wait until the job is in a state that allows cancellation
    DATA lt_cancellable TYPE string_table.
    APPEND 'Suspended' TO lt_cancellable.
    APPEND 'Ready'     TO lt_cancellable.
    APPEND 'Active'    TO lt_cancellable.

    wait_for_job(
      iv_job_id          = av_job_id_cancel
      it_target_statuses = lt_cancellable ).

    " Call the action
    ao_actions->update_job_status(
      iv_account_id           = av_account_id
      iv_job_id               = av_job_id_cancel
      iv_requested_job_status = 'Cancelled' ).

    " Confirm cancellation
    DATA lt_done TYPE string_table.
    APPEND 'Cancelled' TO lt_done.

    wait_for_job(
      iv_job_id          = av_job_id_cancel
      it_target_statuses = lt_done ).

    DATA(lv_status) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_cancel )->get_job( )->get_status( ).

    cl_abap_unit_assert=>assert_equals(
      exp = 'Cancelled'
      act = lv_status
      msg = |Job { av_job_id_cancel } should be Cancelled| ).
  ENDMETHOD.


" =====================================================================
"  TEST: put_job_tagging
" =====================================================================
  METHOD put_job_tagging.
    " Call the action (adds Environment=Development, Team=DataProcessing)
    ao_actions->put_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id_puttag ).

    " Verify via GetJobTagging
    DATA(lo_result) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_puttag ).

    DATA(lt_tags) = lo_result->get_tags( ).

    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lines( lt_tags ) >= 2 )
      msg = |Job { av_job_id_puttag } should have ≥2 tags after put_job_tagging| ).

    " Verify the exact tag keys are present
    DATA lv_found_env  TYPE abap_bool VALUE abap_false.
    DATA lv_found_team TYPE abap_bool VALUE abap_false.
    LOOP AT lt_tags INTO DATA(lo_tag).
      CASE lo_tag->get_key( ).
        WHEN 'Environment'. lv_found_env  = abap_true.
        WHEN 'Team'.        lv_found_team = abap_true.
      ENDCASE.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found_env
      msg = |Tag 'Environment' not found on job { av_job_id_puttag }| ).
    cl_abap_unit_assert=>assert_true(
      act = lv_found_team
      msg = |Tag 'Team' not found on job { av_job_id_puttag }| ).
  ENDMETHOD.


" =====================================================================
"  TEST: get_job_tagging
" =====================================================================
  METHOD get_job_tagging.
    " Pre-condition: put a known tag so get_job_tagging has something
    "                to retrieve.
    DATA lt_pre TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag(
      iv_key   = 'GetTagTest'
      iv_value = 'true' ) TO lt_pre.

    ao_s3c->putjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id
      it_tags      = lt_pre ).

    " Call the action-under-test
    ao_actions->get_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id ).

    " Validate: GetJobTagging must return the tag we just set
    DATA(lo_result) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id ).

    DATA(lt_tags) = lo_result->get_tags( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_tags
      msg = |Job { av_job_id } must have at least one tag| ).

    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_tags INTO DATA(lo_tag).
      IF lo_tag->get_key( ) = 'GetTagTest'.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Tag 'GetTagTest' should be visible via get_job_tagging| ).
  ENDMETHOD.


" =====================================================================
"  TEST: list_jobs
" =====================================================================
  METHOD list_jobs.
    " Call the action
    ao_actions->list_jobs( iv_account_id = av_account_id ).

    " Independently verify: at least the shared job appears in the list
    DATA lt_statuses TYPE /aws1/cl_s3cjobstatuslist_w=>tt_jobstatuslist.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Active' )    TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Cancelled' ) TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Complete' )  TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Failed' )    TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'New' )       TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Paused' )    TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Pausing' )   TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Preparing' ) TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Ready' )     TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Suspended' ) TO lt_statuses.

    DATA(lo_list) = ao_s3c->listjobs(
      iv_accountid   = av_account_id
      it_jobstatuses = lt_statuses ).

    DATA(lt_jobs) = lo_list->get_jobs( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_jobs
      msg = 'ListJobs returned an empty job list' ).

    " Verify the shared job is present
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_jobs INTO DATA(lo_job).
      IF lo_job->get_jobid( ) = av_job_id.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Shared job { av_job_id } not found in ListJobs response| ).
  ENDMETHOD.


" =====================================================================
"  TEST: delete_job_tagging
" =====================================================================
  METHOD delete_job_tagging.
    " Pre-condition: set at least one tag so DeleteJobTagging has
    "                something to remove.
    DATA lt_pre TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag(
      iv_key   = 'DeleteMe'
      iv_value = 'Yes' ) TO lt_pre.

    ao_s3c->putjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_deltag
      it_tags      = lt_pre ).

    " Confirm the tag is there before calling the action
    DATA(lt_before) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_deltag )->get_tags( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_before
      msg = |Tags were not set on job { av_job_id_deltag } before delete test| ).

    " Call the action-under-test
    ao_actions->delete_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id_deltag ).

    " Validate: all tags must be gone
    DATA(lt_after) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_deltag )->get_tags( ).

    cl_abap_unit_assert=>assert_initial(
      act = lt_after
      msg = |Job { av_job_id_deltag } should have no tags after delete_job_tagging| ).
  ENDMETHOD.

ENDCLASS.
