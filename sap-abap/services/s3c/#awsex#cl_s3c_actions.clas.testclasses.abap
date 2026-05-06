" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_s3c_actions DEFINITION DEFERRED.
CLASS /awsex/cl_s3c_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_s3c_actions.

CLASS ltc_awsex_cl_s3c_actions DEFINITION FOR TESTING
  DURATION LONG
  RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " -----------------------------------------------------------------------
    " Shared AWS service clients
    " -----------------------------------------------------------------------
    CLASS-DATA ao_s3c     TYPE REF TO /aws1/if_s3c.
    CLASS-DATA ao_s3      TYPE REF TO /aws1/if_s3.
    CLASS-DATA ao_iam     TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_sts     TYPE REF TO /aws1/if_sts.
    CLASS-DATA ao_session TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_actions TYPE REF TO /awsex/cl_s3c_actions.

    " -----------------------------------------------------------------------
    " Account metadata
    " -----------------------------------------------------------------------
    CLASS-DATA av_account_id TYPE /aws1/s3caccountid.
    CLASS-DATA av_region     TYPE string.

    " -----------------------------------------------------------------------
    " Shared test infrastructure (created once in class_setup)
    " -----------------------------------------------------------------------
    CLASS-DATA av_bucket_name    TYPE /aws1/s3_bucketname.
    CLASS-DATA av_role_arn       TYPE /aws1/s3ciamrolearn.
    CLASS-DATA av_role_name      TYPE /aws1/iamrolenametype.
    CLASS-DATA av_manifest_arn   TYPE /aws1/s3cs3keyarnstring.
    CLASS-DATA av_manifest_etag  TYPE /aws1/s3cnonemptymaxlength6400.
    CLASS-DATA av_report_bucket  TYPE /aws1/s3cs3bucketarnstring.

    " -----------------------------------------------------------------------
    " Pre-created jobs — one dedicated job per test that mutates state
    " -----------------------------------------------------------------------
    " av_shared_job_id  : used for describe_job, get_job_tagging, list_jobs
    CLASS-DATA av_shared_job_id  TYPE /aws1/s3cjobid.
    " av_priority_job   : used for update_job_priority test only
    CLASS-DATA av_priority_job   TYPE /aws1/s3cjobid.
    " av_cancel_job     : used for update_job_status (cancel) test only
    CLASS-DATA av_cancel_job     TYPE /aws1/s3cjobid.
    " av_tagging_job    : used for put_job_tagging test only
    CLASS-DATA av_tagging_job    TYPE /aws1/s3cjobid.
    " av_del_tag_job    : used for delete_job_tagging test only
    CLASS-DATA av_del_tag_job    TYPE /aws1/s3cjobid.

    " -----------------------------------------------------------------------
    " Class lifecycle
    " -----------------------------------------------------------------------
    CLASS-METHODS class_setup
      RAISING /aws1/cx_rt_generic /awsex/cx_generic.
    CLASS-METHODS class_teardown
      RAISING /aws1/cx_rt_generic.

    " -----------------------------------------------------------------------
    " Test methods — one per service operation in the actions class
    " -----------------------------------------------------------------------
    METHODS create_job          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS describe_job        FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_job_priority FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_job_status   FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS get_job_tagging     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS put_job_tagging     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_jobs           FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_job_tagging  FOR TESTING RAISING /aws1/cx_rt_generic.

    " -----------------------------------------------------------------------
    " Private helper methods
    " -----------------------------------------------------------------------
    CLASS-METHODS create_raw_job
      " Creates a job via the low-level SDK (not via ao_actions).
      " Returns the new job ID or fails the test.
      IMPORTING
        iv_description   TYPE string DEFAULT 'Unit test batch job'
      RETURNING
        VALUE(ov_job_id) TYPE /aws1/s3cjobid
      RAISING
        /aws1/cx_rt_generic.

    CLASS-METHODS wait_for_suspended_or_ready
      " Polls until job reaches Suspended (confirmation-required path) or
      " Ready/Active/Complete/Cancelled/Failed (confirmation-not-required path).
      " Fails the test if it times out still in New/Preparing state.
      IMPORTING
        iv_job_id TYPE /aws1/s3cjobid
      RAISING
        /aws1/cx_rt_generic.

    CLASS-METHODS cancel_if_possible
      " Best-effort cancel — used in teardown only.
      IMPORTING
        iv_job_id TYPE /aws1/s3cjobid.

    CLASS-METHODS unique_token
      " Returns a fresh idempotency token from wall-clock + random.
      RETURNING
        VALUE(ov_token) TYPE /aws1/s3cnonemptymaxlength6400.

ENDCLASS.


CLASS ltc_awsex_cl_s3c_actions IMPLEMENTATION.

  " ===========================================================================
  " class_setup — provision all shared test infrastructure once
  " ===========================================================================
  METHOD class_setup.

    ao_session = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_s3c     = /aws1/cl_s3c_factory=>create( ao_session ).
    ao_s3      = /aws1/cl_s3_factory=>create( ao_session ).
    ao_iam     = /aws1/cl_iam_factory=>create( ao_session ).
    ao_sts     = /aws1/cl_sts_factory=>create( ao_session ).
    ao_actions = NEW /awsex/cl_s3c_actions( ).

    " Resolve account ID and region
    DATA(lo_id) = ao_sts->getcalleridentity( ).
    av_account_id = lo_id->get_account( ).
    av_region     = ao_session->get_region( ).

    " =======================================================================
    " 1. S3 bucket — manifest source + report destination (same bucket for
    "    simplicity; that is allowed by S3 Batch Operations)
    " =======================================================================
    av_bucket_name = |sap-s3c-test-{ av_account_id }|.

    " Use the shared util so region-awareness is handled correctly
    /awsex/cl_utils=>create_bucket(
        iv_bucket  = av_bucket_name
        io_s3      = ao_s3
        io_session = ao_session ).

    " Tag the bucket as a test resource
    ao_s3->putbuckettagging(
        iv_bucket  = av_bucket_name
        io_tagging = NEW /aws1/cl_s3_tagging(
            it_tagset = VALUE /aws1/cl_s3_tag=>tt_tagset(
                ( NEW /aws1/cl_s3_tag(
                    iv_key   = 'convert_test'
                    iv_value = 'true' ) ) ) ) ).

    " =======================================================================
    " 2. Upload a manifest CSV that references two non-existent keys.
    "    S3 Batch Operations only requires the manifest to be valid CSV;
    "    the referenced objects do not need to exist for the job to be
    "    created or to reach Suspended/Ready state.
    " =======================================================================
    DATA lv_csv TYPE string.
    lv_csv = |{ av_bucket_name },dummy-key-1\n| &&
             |{ av_bucket_name },dummy-key-2\n|.

    ao_s3->putobject(
        iv_bucket = av_bucket_name
        iv_key    = 'job-manifest.csv'
        iv_body   = /aws1/cl_rt_conv_encoding=>utf8_to_xstring( lv_csv ) ).

    " Retrieve ETag (strip the surrounding quotes S3 includes)
    DATA(lo_head) = ao_s3->headobject(
        iv_bucket = av_bucket_name
        iv_key    = 'job-manifest.csv' ).
    av_manifest_etag = lo_head->get_etag( ).
    REPLACE ALL OCCURRENCES OF '"' IN av_manifest_etag WITH ''.

    " Build ARNs used when constructing every test job
    av_manifest_arn  = |arn:aws:s3:::{ av_bucket_name }/job-manifest.csv|.
    av_report_bucket = |arn:aws:s3:::{ av_bucket_name }|.

    " =======================================================================
    " 3. IAM role for S3 Batch Operations
    "    Policy follows the documented minimum for S3PutObjectTagging jobs:
    "    https://docs.aws.amazon.com/AmazonS3/latest/userguide/
    "          batch-ops-iam-role-policies.html
    "    Extra: s3:GetBucketLocation (needed for region verification)
    "           s3:ListBucket      (needed to access manifest)
    " =======================================================================
    av_role_name = |sap-s3c-batch-test-{ av_account_id }|.

    DATA lv_trust TYPE string.
    lv_trust =
      '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",' &&
      '"Principal":{"Service":"batchoperations.s3.amazonaws.com"},' &&
      '"Action":"sts:AssumeRole"}]}'.

    TRY.
        DATA(lo_role_rsp) = ao_iam->createrole(
            iv_rolename                 = av_role_name
            iv_assumerolepolicydocument = lv_trust ).
        av_role_arn = lo_role_rsp->get_role( )->get_arn( ).
      CATCH /aws1/cx_iam_entityalreadyexistsex.
        " Role already exists from a previous run — reuse it
        DATA(lo_gr) = ao_iam->getrole( iv_rolename = av_role_name ).
        av_role_arn = lo_gr->get_role( )->get_arn( ).
    ENDTRY.

    " Tag the role for identification / manual cleanup
    TRY.
        ao_iam->tagrole(
            iv_rolename = av_role_name
            it_tags = VALUE /aws1/cl_iamtag=>tt_taglisttype(
                ( NEW /aws1/cl_iamtag(
                    iv_key   = 'convert_test'
                    iv_value = 'true' ) ) ) ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Permissions policy — covers manifest read, object tagging, and
    " completion-report write, all scoped to the test bucket
    DATA lv_bkt_arn TYPE string.
    lv_bkt_arn = |arn:aws:s3:::{ av_bucket_name }|.

    DATA lv_perm TYPE string.
    lv_perm =
      '{"Version":"2012-10-17","Statement":[' &&
      '{"Sid":"ManifestRead","Effect":"Allow",' &&
      '"Action":["s3:GetObject","s3:GetObjectVersion"],' &&
      '"Resource":"' && lv_bkt_arn && '/*"},' &&
      '{"Sid":"ReportWrite","Effect":"Allow",' &&
      '"Action":"s3:PutObject",' &&
      '"Resource":"' && lv_bkt_arn && '/*"},' &&
      '{"Sid":"ObjectTagging","Effect":"Allow",' &&
      '"Action":["s3:PutObjectTagging","s3:PutObjectVersionTagging"],' &&
      '"Resource":"' && lv_bkt_arn && '/*"},' &&
      '{"Sid":"BucketAccess","Effect":"Allow",' &&
      '"Action":["s3:GetBucketLocation","s3:ListBucket"],' &&
      '"Resource":"' && lv_bkt_arn && '"}' &&
      ']}' .

    ao_iam->putrolepolicy(
        iv_rolename       = av_role_name
        iv_policyname     = 'S3BatchTestPolicy'
        iv_policydocument = lv_perm ).

    " IAM propagation delay — the job creation call below will fail with
    " an InvalidConfguration error if the role policy is not yet visible
    WAIT UP TO 15 SECONDS.

    " =======================================================================
    " 4. Create all dedicated pre-built jobs
    "    All use ConfirmationRequired=true so they go New→Preparing→Suspended
    "    giving us a stable state to test priority-update and cancellation.
    " =======================================================================
    av_shared_job_id = create_raw_job( 'shared job — describe/get-tag/list' ).
    av_priority_job  = create_raw_job( 'priority test job' ).
    av_cancel_job    = create_raw_job( 'cancel test job' ).
    av_tagging_job   = create_raw_job( 'put-tag test job' ).
    av_del_tag_job   = create_raw_job( 'del-tag test job' ).

    " Verify all jobs were created — fail hard if any is missing
    cl_abap_unit_assert=>assert_not_initial(
        act = av_shared_job_id
        msg = 'shared job could not be created in class_setup' ).
    cl_abap_unit_assert=>assert_not_initial(
        act = av_priority_job
        msg = 'priority test job could not be created in class_setup' ).
    cl_abap_unit_assert=>assert_not_initial(
        act = av_cancel_job
        msg = 'cancel test job could not be created in class_setup' ).
    cl_abap_unit_assert=>assert_not_initial(
        act = av_tagging_job
        msg = 'put-tag test job could not be created in class_setup' ).
    cl_abap_unit_assert=>assert_not_initial(
        act = av_del_tag_job
        msg = 'del-tag test job could not be created in class_setup' ).

    " Wait for every job to leave the transient New/Preparing states
    wait_for_suspended_or_ready( av_shared_job_id ).
    wait_for_suspended_or_ready( av_priority_job ).
    wait_for_suspended_or_ready( av_cancel_job ).
    wait_for_suspended_or_ready( av_tagging_job ).
    wait_for_suspended_or_ready( av_del_tag_job ).

    " Seed the get_job_tagging test: pre-apply tags to av_shared_job_id
    " so the test can verify retrieval without relying on ordering of tests
    DATA lt_seed_tags TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag(
        iv_key   = 'convert_test'
        iv_value = 'true' ) TO lt_seed_tags.
    ao_s3c->putjobtagging(
        iv_accountid = av_account_id
        iv_jobid     = av_shared_job_id
        it_tags      = lt_seed_tags ).

    " Seed the delete_job_tagging test: pre-apply tags to av_del_tag_job
    DATA lt_del_seed TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag(
        iv_key   = 'convert_test'
        iv_value = 'true' ) TO lt_del_seed.
    ao_s3c->putjobtagging(
        iv_accountid = av_account_id
        iv_jobid     = av_del_tag_job
        it_tags      = lt_del_seed ).

  ENDMETHOD.


  " ===========================================================================
  " class_teardown — clean up all resources created by class_setup
  " ===========================================================================
  METHOD class_teardown.

    " Cancel surviving jobs (best-effort; jobs already Cancelled/Complete/Failed
    " are silently skipped inside cancel_if_possible)
    cancel_if_possible( av_shared_job_id ).
    cancel_if_possible( av_priority_job ).
    cancel_if_possible( av_cancel_job ).
    cancel_if_possible( av_tagging_job ).
    cancel_if_possible( av_del_tag_job ).

    " Remove IAM inline policy then role
    TRY.
        ao_iam->deleterolepolicy(
            iv_rolename   = av_role_name
            iv_policyname = 'S3BatchTestPolicy' ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iam->deleterole( iv_rolename = av_role_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Remove S3 bucket (all objects first, then bucket)
    TRY.
        /awsex/cl_utils=>cleanup_bucket(
            iv_bucket = av_bucket_name
            io_s3     = ao_s3 ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

  ENDMETHOD.


  " ===========================================================================
  " Helper: create_raw_job
  " Creates a confirmation-required S3PutObjectTagging batch job and returns
  " the job ID.  Raises on failure so class_setup aborts with a clear message.
  " ===========================================================================
  METHOD create_raw_job.

    DATA lt_fields TYPE /aws1/cl_s3cjobmanifestfield00=>tt_jobmanifestfieldlist.
    APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Bucket' ) TO lt_fields.
    APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Key'    ) TO lt_fields.

    DATA lt_tagset TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag(
        iv_key   = 'convert_test'
        iv_value = 'true' ) TO lt_tagset.

    DATA(lo_manifest) = NEW /aws1/cl_s3cjobmanifest(
        io_spec = NEW /aws1/cl_s3cjobmanifestspec(
            iv_format = 'S3BatchOperations_CSV_20180820'
            it_fields = lt_fields )
        io_location = NEW /aws1/cl_s3cjobmanifestloc(
            iv_objectarn = av_manifest_arn
            iv_etag      = av_manifest_etag ) ).

    DATA(lo_operation) = NEW /aws1/cl_s3cjoboperation(
        io_s3putobjecttagging = NEW /aws1/cl_s3cs3setobjecttagop(
            it_tagset = lt_tagset ) ).

    DATA(lo_report) = NEW /aws1/cl_s3cjobreport(
        iv_bucket      = av_report_bucket
        iv_format      = 'Report_CSV_20180820'
        iv_enabled     = abap_true
        iv_prefix      = 'batch-op-reports'
        iv_reportscope = 'AllTasks' ).

    DATA(lo_result) = ao_s3c->createjob(
        iv_accountid            = av_account_id
        iv_rolearn              = av_role_arn
        io_manifest             = lo_manifest
        io_operation            = lo_operation
        io_report               = lo_report
        iv_priority             = 10
        iv_description          = iv_description
        iv_confirmationrequired = abap_true
        iv_clientrequesttoken   = unique_token( ) ).

    ov_job_id = lo_result->get_jobid( ).

  ENDMETHOD.


  " ===========================================================================
  " Helper: wait_for_suspended_or_ready
  " Polls DescribeJob until the job leaves the transient New/Preparing states.
  " Fails the test (via cl_abap_unit_assert=>fail) on timeout.
  " ===========================================================================
  METHOD wait_for_suspended_or_ready.

    DATA lv_status TYPE /aws1/s3cjobstatus.
    DATA lv_stable TYPE abap_bool VALUE abap_false.

    " Poll for up to 120 seconds (24 × 5-second sleep)
    DO 24 TIMES.
      DATA(lo_res) = ao_s3c->describejob(
          iv_accountid = av_account_id
          iv_jobid     = iv_job_id ).
      lv_status = lo_res->get_job( )->get_status( ).

      CASE lv_status.
        WHEN 'New' OR 'Preparing'.
          WAIT UP TO 5 SECONDS.
        WHEN OTHERS.
          " Suspended / Ready / Active / Complete / Cancelled / Failed
          lv_stable = abap_true.
          RETURN.
      ENDCASE.
    ENDDO.

    cl_abap_unit_assert=>fail(
        msg = |Job { iv_job_id } did not leave New/Preparing within 120s| &&
              | (last status: { lv_status })| ).

  ENDMETHOD.


  " ===========================================================================
  " Helper: cancel_if_possible  (teardown helper — never raises)
  " ===========================================================================
  METHOD cancel_if_possible.

    IF iv_job_id IS INITIAL.
      RETURN.
    ENDIF.
    TRY.
        DATA(lo_res) = ao_s3c->describejob(
            iv_accountid = av_account_id
            iv_jobid     = iv_job_id ).
        DATA(lv_st) = lo_res->get_job( )->get_status( ).
        IF lv_st = 'Ready'     OR lv_st = 'Suspended'
        OR lv_st = 'Active'    OR lv_st = 'Paused'.
          ao_s3c->updatejobstatus(
              iv_accountid          = av_account_id
              iv_jobid              = iv_job_id
              iv_requestedjobstatus = 'Cancelled' ).
        ENDIF.
      CATCH /aws1/cx_rt_generic.
        " Swallow all errors — this is a best-effort cleanup
    ENDTRY.

  ENDMETHOD.


  " ===========================================================================
  " Helper: unique_token — returns a wall-clock + random idempotency token
  " ===========================================================================
  METHOD unique_token.

    DATA lv_ts   TYPE timestamp.
    DATA lv_rand TYPE string.
    GET TIME STAMP FIELD lv_ts.
    lv_rand   = /awsex/cl_utils=>get_random_string( ).
    ov_token  = |{ lv_ts }{ lv_rand }|.
    " Truncate to ≤64 chars if needed (field is maxlen 6400, so this is fine)

  ENDMETHOD.


  " ===========================================================================
  " TEST: create_job
  " Calls ao_actions->create_job( ) and verifies it returns a non-initial job ID
  " ===========================================================================
  METHOD create_job.

    DATA lv_job_id TYPE /aws1/s3cjobid.

    lv_job_id = ao_actions->create_job(
        iv_account_id    = av_account_id
        iv_role_arn      = av_role_arn
        iv_manifest_arn  = av_manifest_arn
        iv_manifest_etag = av_manifest_etag
        iv_report_bucket = av_report_bucket ).

    cl_abap_unit_assert=>assert_not_initial(
        act = lv_job_id
        msg = 'create_job must return a non-initial job ID' ).

    " Verify the job actually exists in AWS
    DATA(lo_desc) = ao_s3c->describejob(
        iv_accountid = av_account_id
        iv_jobid     = lv_job_id ).

    cl_abap_unit_assert=>assert_bound(
        act = lo_desc->get_job( )
        msg = |Job { lv_job_id } returned by create_job not found in DescribeJob| ).

    " Clean up this extra job
    cancel_if_possible( lv_job_id ).

  ENDMETHOD.


  " ===========================================================================
  " TEST: describe_job
  " Calls ao_actions->describe_job( ) against av_shared_job_id.
  " Verifies the call succeeds and the job descriptor is reachable via SDK.
  " ===========================================================================
  METHOD describe_job.

    " Call the action under test (it emits a MESSAGE — not verified here)
    ao_actions->describe_job(
        iv_account_id = av_account_id
        iv_job_id     = av_shared_job_id ).

    " Independently verify via the SDK that the job descriptor is populated
    DATA(lo_result) = ao_s3c->describejob(
        iv_accountid = av_account_id
        iv_jobid     = av_shared_job_id ).

    cl_abap_unit_assert=>assert_bound(
        act = lo_result->get_job( )
        msg = 'describe_job: job descriptor must be bound' ).

    cl_abap_unit_assert=>assert_not_initial(
        act = lo_result->get_job( )->get_status( )
        msg = 'describe_job: job status must not be initial' ).

    cl_abap_unit_assert=>assert_not_initial(
        act = lo_result->get_job( )->get_rolearn( )
        msg = 'describe_job: role ARN must not be initial' ).

  ENDMETHOD.


  " ===========================================================================
  " TEST: update_job_priority
  " The job (av_priority_job) is in Suspended state (confirmation-required).
  " Priority can be updated in Suspended state without confirming the job.
  " We update from 10 → 75 and verify via DescribeJob.
  " ===========================================================================
  METHOD update_job_priority.

    " Guard: the job must be in Suspended state (set by class_setup)
    DATA(lo_before) = ao_s3c->describejob(
        iv_accountid = av_account_id
        iv_jobid     = av_priority_job ).
    DATA(lv_status_before) = lo_before->get_job( )->get_status( ).

    cl_abap_unit_assert=>assert_equals(
        exp = 'Suspended'
        act = lv_status_before
        msg = |update_job_priority: pre-condition failed — | &&
              |av_priority_job must be Suspended, got { lv_status_before }| ).

    " Call the action under test
    ao_actions->update_job_priority(
        iv_account_id = av_account_id
        iv_job_id     = av_priority_job
        iv_priority   = 75 ).

    " Verify via SDK
    DATA(lo_after) = ao_s3c->describejob(
        iv_accountid = av_account_id
        iv_jobid     = av_priority_job ).

    cl_abap_unit_assert=>assert_equals(
        exp = 75
        act = lo_after->get_job( )->get_priority( )
        msg = |update_job_priority: priority must be 75 after update, | &&
              |got { lo_after->get_job( )->get_priority( ) }| ).

  ENDMETHOD.


  " ===========================================================================
  " TEST: update_job_status
  " The job (av_cancel_job) is in Suspended state.  We cancel it
  " (RequestedJobStatus = 'Cancelled') and verify the resulting status.
  " ===========================================================================
  METHOD update_job_status.

    " Guard: the job must be in Suspended state
    DATA(lo_before) = ao_s3c->describejob(
        iv_accountid = av_account_id
        iv_jobid     = av_cancel_job ).
    DATA(lv_status_before) = lo_before->get_job( )->get_status( ).

    cl_abap_unit_assert=>assert_equals(
        exp = 'Suspended'
        act = lv_status_before
        msg = |update_job_status: pre-condition failed — | &&
              |av_cancel_job must be Suspended, got { lv_status_before }| ).

    " Call the action under test
    ao_actions->update_job_status(
        iv_account_id = av_account_id
        iv_job_id     = av_cancel_job
        iv_req_status = 'Cancelled' ).

    " The status may be 'Cancelling' transiently; poll for terminal state
    DATA lv_final_status TYPE /aws1/s3cjobstatus.
    DO 12 TIMES.
      DATA(lo_poll) = ao_s3c->describejob(
          iv_accountid = av_account_id
          iv_jobid     = av_cancel_job ).
      lv_final_status = lo_poll->get_job( )->get_status( ).
      IF lv_final_status <> 'Cancelling'.
        EXIT.
      ENDIF.
      WAIT UP TO 5 SECONDS.
    ENDDO.

    cl_abap_unit_assert=>assert_equals(
        exp = 'Cancelled'
        act = lv_final_status
        msg = |update_job_status: job must reach Cancelled, | &&
              |got { lv_final_status }| ).

  ENDMETHOD.


  " ===========================================================================
  " TEST: get_job_tagging
  " av_shared_job_id was pre-tagged in class_setup with convert_test=true.
  " We call get_job_tagging and verify at least one tag is returned.
  " ===========================================================================
  METHOD get_job_tagging.

    " Call the action under test
    ao_actions->get_job_tagging(
        iv_account_id = av_account_id
        iv_job_id     = av_shared_job_id ).

    " Independently verify via the SDK
    DATA(lo_result) = ao_s3c->getjobtagging(
        iv_accountid = av_account_id
        iv_jobid     = av_shared_job_id ).

    cl_abap_unit_assert=>assert_bound(
        act = lo_result
        msg = 'get_job_tagging: result must be bound' ).

    DATA(lt_tags) = lo_result->get_tags( ).

    cl_abap_unit_assert=>assert_true(
        act = xsdbool( lines( lt_tags ) >= 1 )
        msg = |get_job_tagging: at least 1 tag expected, | &&
              |got { lines( lt_tags ) }| ).

    " Verify the convert_test tag applied in class_setup is present
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_tags ASSIGNING FIELD-SYMBOL(<lo_tag>).
      IF <lo_tag>->get_key( ) = 'convert_test'.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
        act = lv_found
        msg = 'get_job_tagging: convert_test tag not found' ).

  ENDMETHOD.


  " ===========================================================================
  " TEST: put_job_tagging
  " av_tagging_job has no tags yet (it was not seeded in class_setup).
  " We call put_job_tagging and verify the two tags (Environment, Team)
  " appear in a subsequent GetJobTagging SDK call.
  " ===========================================================================
  METHOD put_job_tagging.

    " Precondition: confirm the job has no tags yet
    DATA(lo_before) = ao_s3c->getjobtagging(
        iv_accountid = av_account_id
        iv_jobid     = av_tagging_job ).
    cl_abap_unit_assert=>assert_equals(
        exp = 0
        act = lines( lo_before->get_tags( ) )
        msg = 'put_job_tagging: pre-condition failed — job must start with 0 tags' ).

    " Call the action under test
    ao_actions->put_job_tagging(
        iv_account_id = av_account_id
        iv_job_id     = av_tagging_job ).

    " Verify via SDK
    DATA(lo_after) = ao_s3c->getjobtagging(
        iv_accountid = av_account_id
        iv_jobid     = av_tagging_job ).

    DATA(lt_tags) = lo_after->get_tags( ).

    cl_abap_unit_assert=>assert_equals(
        exp = 2
        act = lines( lt_tags )
        msg = |put_job_tagging: expected 2 tags, got { lines( lt_tags ) }| ).

    DATA lv_found_env  TYPE abap_bool VALUE abap_false.
    DATA lv_found_team TYPE abap_bool VALUE abap_false.
    LOOP AT lt_tags ASSIGNING FIELD-SYMBOL(<lo_tag>).
      CASE <lo_tag>->get_key( ).
        WHEN 'Environment'. lv_found_env  = abap_true.
        WHEN 'Team'.        lv_found_team = abap_true.
      ENDCASE.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
        act = lv_found_env
        msg = 'put_job_tagging: Environment tag not found' ).
    cl_abap_unit_assert=>assert_true(
        act = lv_found_team
        msg = 'put_job_tagging: Team tag not found' ).

  ENDMETHOD.


  " ===========================================================================
  " TEST: list_jobs
  " Calls ao_actions->list_jobs( ) and verifies av_shared_job_id appears.
  " ===========================================================================
  METHOD list_jobs.

    " Call the action under test
    ao_actions->list_jobs( iv_account_id = av_account_id ).

    " Independently verify via SDK with all-status filter
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

    DATA(lo_result) = ao_s3c->listjobs(
        iv_accountid   = av_account_id
        it_jobstatuses = lt_statuses ).

    DATA(lt_jobs) = lo_result->get_jobs( ).

    cl_abap_unit_assert=>assert_true(
        act = xsdbool( lines( lt_jobs ) >= 1 )
        msg = |list_jobs: expected at least 1 job, got { lines( lt_jobs ) }| ).

    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_jobs ASSIGNING FIELD-SYMBOL(<lo_job>).
      IF <lo_job>->get_jobid( ) = av_shared_job_id.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
        act = lv_found
        msg = |list_jobs: av_shared_job_id ({ av_shared_job_id }) | &&
              |not found in the listing| ).

  ENDMETHOD.


  " ===========================================================================
  " TEST: delete_job_tagging
  " av_del_tag_job was pre-tagged in class_setup with convert_test=true.
  " We call delete_job_tagging and verify no tags remain.
  " ===========================================================================
  METHOD delete_job_tagging.

    " Precondition: confirm the job has at least one tag
    DATA(lo_before) = ao_s3c->getjobtagging(
        iv_accountid = av_account_id
        iv_jobid     = av_del_tag_job ).

    cl_abap_unit_assert=>assert_true(
        act = xsdbool( lines( lo_before->get_tags( ) ) >= 1 )
        msg = |delete_job_tagging: pre-condition failed — | &&
              |job must have ≥1 tag before deletion, | &&
              |got { lines( lo_before->get_tags( ) ) }| ).

    " Call the action under test
    ao_actions->delete_job_tagging(
        iv_account_id = av_account_id
        iv_job_id     = av_del_tag_job ).

    " Verify via SDK — tags must now be empty (lines() = 0)
    DATA(lo_after) = ao_s3c->getjobtagging(
        iv_accountid = av_account_id
        iv_jobid     = av_del_tag_job ).

    cl_abap_unit_assert=>assert_equals(
        exp = 0
        act = lines( lo_after->get_tags( ) )
        msg = |delete_job_tagging: expected 0 tags after deletion, | &&
              |got { lines( lo_after->get_tags( ) ) }| ).

  ENDMETHOD.

ENDCLASS.
