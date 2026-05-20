" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_s3c_actions DEFINITION DEFERRED.
CLASS /awsex/cl_s3c_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_s3c_actions.

CLASS ltc_awsex_cl_s3c_actions DEFINITION
  FOR TESTING
  DURATION LONG
  RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl           TYPE /aws1/rt_profile_id  VALUE 'ZCODE_DEMO'.
    CONSTANTS cv_role_name     TYPE /aws1/iamrolenametype VALUE 's3c-batch-ops-role-abap'.
    CONSTANTS cv_policy_name   TYPE /aws1/iampolicynametype VALUE 's3c-batch-ops-inline'.
    CONSTANTS cv_manifest_key  TYPE /aws1/s3_objectkey    VALUE 'job-manifest.csv'.

    " Shared AWS clients
    CLASS-DATA ao_s3c         TYPE REF TO /aws1/if_s3c.
    CLASS-DATA ao_s3          TYPE REF TO /aws1/if_s3.
    CLASS-DATA ao_iam         TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_session     TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_s3c_actions TYPE REF TO /awsex/cl_s3c_actions.

    " Account / shared resource state
    CLASS-DATA av_account_id    TYPE /aws1/s3caccountid.
    CLASS-DATA av_bucket_name   TYPE /aws1/s3_bucketname.
    CLASS-DATA av_bucket_arn    TYPE /aws1/s3cs3bucketarnstring.
    CLASS-DATA av_role_arn      TYPE /aws1/s3ciamrolearn.
    CLASS-DATA av_manifest_arn  TYPE /aws1/s3cs3keyarnstring.
    CLASS-DATA av_manifest_etag TYPE /aws1/s3cnonemptymaxlength1000.

    " Job IDs shared across read-only tests (describe, get-tagging, list-jobs)
    CLASS-DATA av_shared_job_id   TYPE /aws1/s3cjobid.

    " Dedicated job IDs for mutation tests — one per mutating operation
    CLASS-DATA av_prio_job_id     TYPE /aws1/s3cjobid.
    CLASS-DATA av_cancel_job_id   TYPE /aws1/s3cjobid.
    CLASS-DATA av_tag_job_id      TYPE /aws1/s3cjobid.
    CLASS-DATA av_del_tag_job_id  TYPE /aws1/s3cjobid.

    " Test methods — one per service operation
    METHODS create_job          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_job_priority FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_job_status   FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS describe_job        FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS get_job_tagging     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS put_job_tagging     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_jobs           FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_job_tagging  FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup
      RAISING
        /aws1/cx_rt_generic
        /awsex/cx_generic.

    CLASS-METHODS class_teardown
      RAISING
        /aws1/cx_rt_generic
        /awsex/cx_generic.

    " Helper: create a fresh S3 Batch job (ConfirmationRequired keeps it in
    " 'New'/'Suspended' state so it stays stable for testing).
    CLASS-METHODS create_test_job
      RETURNING
        VALUE(rv_job_id) TYPE /aws1/s3cjobid
      RAISING
        /aws1/cx_rt_generic.

    " Helper: poll until job reaches the desired status or fail.
    CLASS-METHODS wait_for_job_status
      IMPORTING
        iv_job_id         TYPE /aws1/s3cjobid
        iv_desired_status TYPE /aws1/s3cjobstatus
        iv_max_attempts   TYPE i DEFAULT 30
      RAISING
        /aws1/cx_rt_generic.

    " Helper: safely cancel a job; ignore errors if already terminal.
    CLASS-METHODS try_cancel_job
      IMPORTING
        iv_job_id TYPE /aws1/s3cjobid.

ENDCLASS.

CLASS ltc_awsex_cl_s3c_actions IMPLEMENTATION.

" ==========================================================================
"  class_setup
"  Creates every AWS resource the tests depend on:
"    1. S3 bucket (manifest + report destination), tagged convert_test
"    2. IAM role with the trust policy for batchoperations.s3.amazonaws.com
"       and an inline permissions policy scoped to the test bucket
"    3. Bucket policy granting the role access to objects in the bucket
"    4. CSV manifest object uploaded to the bucket
"    5. Five pre-created S3 Batch jobs (one shared + four for mutation tests)
" ==========================================================================
  METHOD class_setup.
    ao_session    = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_s3c        = /aws1/cl_s3c_factory=>create( ao_session ).
    ao_s3         = /aws1/cl_s3_factory=>create( ao_session ).
    ao_iam        = /aws1/cl_iam_factory=>create( ao_session ).
    ao_s3c_actions = NEW /awsex/cl_s3c_actions( ).

    av_account_id = ao_session->get_account_id( ).

    " -----------------------------------------------------------------------
    " 1. Create the S3 bucket used for the manifest and job reports.
    " -----------------------------------------------------------------------
    av_bucket_name = |sap-abap-s3c-test-{ av_account_id }|.
    av_bucket_arn  = |arn:aws:s3:::{ av_bucket_name }|.

    " /awsex/cl_utils=>create_bucket handles the us-east-1 / other-region
    " LocationConstraint logic automatically.
    TRY.
        /awsex/cl_utils=>create_bucket(
          iv_bucket  = av_bucket_name
          io_s3      = ao_s3
          io_session = ao_session ).
      CATCH /aws1/cx_s3_bktalrdyownedbyyou.
        " Bucket already owned by this account — fine, proceed.
    ENDTRY.

    " Tag the bucket with convert_test so it is identifiable for cleanup.
    DATA lt_bkt_tags TYPE /aws1/cl_s3_tag=>tt_tagset.
    APPEND NEW /aws1/cl_s3_tag( iv_key = 'convert_test' iv_value = 'true' ) TO lt_bkt_tags.
    ao_s3->putbuckettagging(
      iv_bucket  = av_bucket_name
      io_tagging = NEW /aws1/cl_s3_tagging( it_tagset = lt_bkt_tags ) ).

    " -----------------------------------------------------------------------
    " 2. Create the IAM role that S3 Batch Operations will assume.
    "    Trust policy: allow batchoperations.s3.amazonaws.com to assume it.
    "    Inline permissions policy: scoped exactly to the test bucket.
    " -----------------------------------------------------------------------
    DATA lv_trust_policy TYPE /aws1/iampolicydocumenttype.
    lv_trust_policy =
      '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",' &&
      '"Principal":{"Service":"batchoperations.s3.amazonaws.com"},' &&
      '"Action":"sts:AssumeRole"}]}'.

    DATA lt_iam_tags TYPE /aws1/cl_iamtag=>tt_taglisttype.
    APPEND NEW /aws1/cl_iamtag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_iam_tags.

    TRY.
        DATA(lo_role_result) = ao_iam->createrole(
          iv_rolename                = cv_role_name
          iv_assumerolepolicydocument = lv_trust_policy
          iv_description             = 'ABAP SDK S3 Batch Ops test role'
          it_tags                    = lt_iam_tags ).
        av_role_arn = lo_role_result->get_role( )->get_arn( ).
      CATCH /aws1/cx_iamentityalrdyexex.
        " Role already exists — retrieve its ARN.
        DATA(lo_get_role) = ao_iam->getrole( iv_rolename = cv_role_name ).
        av_role_arn = lo_get_role->get_role( )->get_arn( ).
    ENDTRY.

    cl_abap_unit_assert=>assert_not_initial(
      act = av_role_arn
      msg = 'class_setup: IAM role ARN must not be empty' ).

    " Inline permissions policy for PutObjectTagging + manifest read +
    " report write, all scoped to the single test bucket.
    DATA lv_inline_policy TYPE /aws1/iampolicydocumenttype.
    lv_inline_policy =
      '{"Version":"2012-10-17","Statement":[' &&
      '{"Sid":"AllowTaggingObjects","Effect":"Allow",' &&
        '"Action":["s3:PutObjectTagging","s3:PutObjectVersionTagging"],' &&
        '"Resource":"arn:aws:s3:::' && av_bucket_name && '/*"},' &&
      '{"Sid":"AllowReadManifest","Effect":"Allow",' &&
        '"Action":["s3:GetObject","s3:GetObjectVersion"],' &&
        '"Resource":"arn:aws:s3:::' && av_bucket_name && '/*"},' &&
      '{"Sid":"AllowWriteReport","Effect":"Allow",' &&
        '"Action":["s3:PutObject"],' &&
        '"Resource":"arn:aws:s3:::' && av_bucket_name && '/*"},' &&
      '{"Sid":"AllowListBucket","Effect":"Allow",' &&
        '"Action":["s3:GetBucketLocation","s3:ListBucket"],' &&
        '"Resource":"arn:aws:s3:::' && av_bucket_name && '"}' &&
      ']}' .

    ao_iam->putrolepolicy(
      iv_rolename      = cv_role_name
      iv_policyname    = cv_policy_name
      iv_policydocument = lv_inline_policy ).

    " IAM changes are eventually consistent — wait for propagation.
    WAIT UP TO 10 SECONDS.

    " -----------------------------------------------------------------------
    " 3. Apply a bucket policy so the Batch Operations service principal
    "    (acting as the role) can read objects and write reports.
    " -----------------------------------------------------------------------
    DATA lv_bucket_policy TYPE /aws1/s3_policy.
    lv_bucket_policy =
      '{"Version":"2012-10-17","Statement":[' &&
      '{"Sid":"BatchOpsReadManifest","Effect":"Allow",' &&
        '"Principal":{"AWS":"' && av_role_arn && '"},' &&
        '"Action":["s3:GetObject","s3:GetObjectVersion","s3:GetBucketLocation"],' &&
        '"Resource":["arn:aws:s3:::' && av_bucket_name && '",' &&
                    '"arn:aws:s3:::' && av_bucket_name && '/*"]},' &&
      '{"Sid":"BatchOpsWriteReport","Effect":"Allow",' &&
        '"Principal":{"AWS":"' && av_role_arn && '"},' &&
        '"Action":["s3:PutObject","s3:PutObjectTagging",' &&
                  '"s3:PutObjectVersionTagging"],' &&
        '"Resource":"arn:aws:s3:::' && av_bucket_name && '/*"}' &&
      ']}' .

    ao_s3->putbucketpolicy(
      iv_bucket = av_bucket_name
      iv_policy = lv_bucket_policy ).

    " -----------------------------------------------------------------------
    " 4. Upload the CSV manifest and capture its ETag.
    " -----------------------------------------------------------------------
    DATA lv_manifest_body TYPE string.
    lv_manifest_body = |{ av_bucket_name },test-obj-1.txt\n| &&
                       |{ av_bucket_name },test-obj-2.txt\n|.
    DATA lv_manifest_xs TYPE xstring.
    lv_manifest_xs = cl_abap_codepage=>convert_to( lv_manifest_body ).

    DATA(lo_put_result) = ao_s3->putobject(
      iv_bucket = av_bucket_name
      iv_key    = cv_manifest_key
      iv_body   = lv_manifest_xs ).

    av_manifest_arn  = |arn:aws:s3:::{ av_bucket_name }/{ cv_manifest_key }|.
    DATA lv_raw_etag TYPE string.
    lv_raw_etag = lo_put_result->get_etag( ).
    REPLACE ALL OCCURRENCES OF '"' IN lv_raw_etag WITH ''.
    av_manifest_etag = lv_raw_etag.

    cl_abap_unit_assert=>assert_not_initial(
      act = av_manifest_etag
      msg = 'class_setup: manifest ETag must not be empty' ).

    " -----------------------------------------------------------------------
    " 5. Pre-create jobs:  one shared (read-only) + four for mutation tests.
    " -----------------------------------------------------------------------
    av_shared_job_id  = create_test_job( ).
    av_prio_job_id    = create_test_job( ).
    av_cancel_job_id  = create_test_job( ).
    av_tag_job_id     = create_test_job( ).
    av_del_tag_job_id = create_test_job( ).

    " All five jobs must have been created successfully.
    cl_abap_unit_assert=>assert_not_initial(
      act = av_shared_job_id
      msg = 'class_setup: shared job must be created' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_prio_job_id
      msg = 'class_setup: priority-test job must be created' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_cancel_job_id
      msg = 'class_setup: cancel-test job must be created' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_tag_job_id
      msg = 'class_setup: tagging-test job must be created' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_del_tag_job_id
      msg = 'class_setup: delete-tagging-test job must be created' ).
  ENDMETHOD.

" ==========================================================================
"  class_teardown
"  Best-effort cleanup:
"    - Cancel any still-running jobs (tagged convert_test; fast operation).
"    - Delete the inline policy and then the IAM role.
"    - Remove all objects from and then delete the S3 bucket.
"  The IAM role is tagged convert_test in case deletion fails; the user can
"  locate and delete it manually using the tag.
" ==========================================================================
  METHOD class_teardown.
    " Collect all job IDs created during setup.
    DATA lt_job_ids TYPE STANDARD TABLE OF /aws1/s3cjobid WITH DEFAULT KEY.
    APPEND av_shared_job_id   TO lt_job_ids.
    APPEND av_prio_job_id     TO lt_job_ids.
    APPEND av_cancel_job_id   TO lt_job_ids.
    APPEND av_tag_job_id      TO lt_job_ids.
    APPEND av_del_tag_job_id  TO lt_job_ids.

    " Cancel any job that is still in a cancellable state.
    LOOP AT lt_job_ids ASSIGNING FIELD-SYMBOL(<lv_jid>).
      IF <lv_jid> IS NOT INITIAL.
        try_cancel_job( <lv_jid> ).
      ENDIF.
    ENDLOOP.

    " Delete the inline policy from the role, then delete the role itself.
    TRY.
        ao_iam->deleterolepolicy(
          iv_rolename   = cv_role_name
          iv_policyname = cv_policy_name ).
      CATCH /aws1/cx_rt_generic.
        " Policy may not exist (e.g. setup failed before attaching it).
    ENDTRY.

    TRY.
        ao_iam->deleterole( iv_rolename = cv_role_name ).
      CATCH /aws1/cx_rt_generic.
        " Role tagged convert_test; user can clean up manually if needed.
    ENDTRY.

    " Delete the bucket policy before deleting objects, then clean up bucket.
    TRY.
        ao_s3->deletebucketpolicy( iv_bucket = av_bucket_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    TRY.
        /awsex/cl_utils=>cleanup_bucket(
          iv_bucket = av_bucket_name
          io_s3     = ao_s3 ).
      CATCH /aws1/cx_rt_generic.
        " Bucket tagged convert_test; user can clean up manually if needed.
    ENDTRY.
  ENDMETHOD.

" ==========================================================================
"  create_test_job  (helper)
"  Creates one S3 Batch job with ConfirmationRequired = true.
"  This keeps the job in 'New' or 'Suspended' state so it is stable for
"  tests.  Tags every job with convert_test.
" ==========================================================================
  METHOD create_test_job.
    DATA lt_fields TYPE /aws1/cl_s3cjobmanifestfield00=>tt_jobmanifestfieldlist.
    APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Bucket' ) TO lt_fields.
    APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Key' )    TO lt_fields.

    " The job operation tags the objects; we also tag the job itself.
    DATA lt_job_tags TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_job_tags.

    DATA lt_op_tagset TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag(
      iv_key   = 'BatchTag'
      iv_value = 'BatchValue' ) TO lt_op_tagset.

    DATA(lo_result) = ao_s3c->createjob(
      iv_accountid            = av_account_id
      iv_confirmationrequired = abap_true
      iv_priority             = 10
      iv_rolearn              = av_role_arn
      iv_description          = 'ABAP SDK s3c unit test job'
      it_tags                 = lt_job_tags
      io_operation            = NEW /aws1/cl_s3cjoboperation(
        io_s3putobjecttagging = NEW /aws1/cl_s3cs3setobjecttagop(
          it_tagset = lt_op_tagset ) )
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
      msg = 'create_test_job: job ID must not be empty after CreateJob' ).
  ENDMETHOD.

" ==========================================================================
"  wait_for_job_status  (helper)
"  Polls DescribeJob every 5 seconds until the job reaches iv_desired_status.
"  Fails the test if the maximum number of attempts is exhausted.
" ==========================================================================
  METHOD wait_for_job_status.
    DATA lv_attempts TYPE i VALUE 0.
    WHILE lv_attempts < iv_max_attempts.
      DATA(lo_desc) = ao_s3c->describejob(
        iv_accountid = av_account_id
        iv_jobid     = iv_job_id ).
      DATA(lv_current) = lo_desc->get_job( )->get_status( ).
      IF lv_current = iv_desired_status.
        RETURN.
      ENDIF.
      " If the job reached a terminal state that is NOT the desired one, fail.
      IF lv_current = 'Complete'  OR lv_current = 'Failed'.
        cl_abap_unit_assert=>fail(
          msg = |wait_for_job_status: job { iv_job_id } reached terminal| &&
                | state { lv_current } before desired { iv_desired_status }| ).
      ENDIF.
      WAIT UP TO 5 SECONDS.
      lv_attempts = lv_attempts + 1.
    ENDWHILE.
    cl_abap_unit_assert=>fail(
      msg = |wait_for_job_status: job { iv_job_id } did not reach| &&
            | { iv_desired_status } within { iv_max_attempts } attempts| ).
  ENDMETHOD.

" ==========================================================================
"  try_cancel_job  (helper)
"  Cancels a job silently — used in teardown where failures must not abort
"  the remainder of the cleanup sequence.
" ==========================================================================
  METHOD try_cancel_job.
    TRY.
        DATA(lo_desc) = ao_s3c->describejob(
          iv_accountid = av_account_id
          iv_jobid     = iv_job_id ).
        DATA(lv_status) = lo_desc->get_job( )->get_status( ).
        IF lv_status = 'New'      OR lv_status = 'Suspended'
        OR lv_status = 'Ready'   OR lv_status = 'Active'
        OR lv_status = 'Paused'  OR lv_status = 'Pausing'.
          TRY.
              ao_s3c->updatejobstatus(
                iv_accountid          = av_account_id
                iv_jobid              = iv_job_id
                iv_requestedjobstatus = 'Cancelled' ).
            CATCH /aws1/cx_rt_generic.
          ENDTRY.
        ENDIF.
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.

" ============================================================
"  Test: create_job
"  Exercises /awsex/cl_s3c_actions=>create_job.
"  Verifies the returned job ID is non-empty and that the job
"  can be described, proving it was actually created.
" ============================================================
  METHOD create_job.
    DATA lv_new_job_id TYPE /aws1/s3cjobid.

    lv_new_job_id = ao_s3c_actions->create_job(
      iv_account_id    = av_account_id
      iv_role_arn      = av_role_arn
      iv_manifest_arn  = av_manifest_arn
      iv_manifest_etag = av_manifest_etag
      iv_report_bucket = av_bucket_arn ).

    " The returned job ID must be non-empty — the action must have succeeded.
    cl_abap_unit_assert=>assert_not_initial(
      act = lv_new_job_id
      msg = 'create_job: action must return a non-empty job ID' ).

    " Verify the job physically exists in S3 Batch Operations.
    DATA(lo_desc) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = lv_new_job_id ).

    cl_abap_unit_assert=>assert_equals(
      exp = lv_new_job_id
      act = lo_desc->get_job( )->get_jobid( )
      msg = 'create_job: described job ID must match the created job ID' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_desc->get_job( )->get_status( )
      msg = 'create_job: newly created job must have a non-empty status' ).

    " Clean up the extra job created by this test.
    try_cancel_job( lv_new_job_id ).
  ENDMETHOD.

" ============================================================
"  Test: update_job_priority
"  Exercises /awsex/cl_s3c_actions=>update_job_priority.
"  Uses a dedicated pre-created job so the mutation does not
"  affect other tests.  Verifies that DescribeJob reports the
"  new priority value of 60.
" ============================================================
  METHOD update_job_priority.
    ao_s3c_actions->update_job_priority(
      iv_account_id = av_account_id
      iv_job_id     = av_prio_job_id ).

    DATA(lo_desc) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = av_prio_job_id ).

    cl_abap_unit_assert=>assert_equals(
      exp = 60
      act = lo_desc->get_job( )->get_priority( )
      msg = 'update_job_priority: job priority must be 60 after update' ).
  ENDMETHOD.

" ============================================================
"  Test: update_job_status
"  Exercises /awsex/cl_s3c_actions=>update_job_status, which
"  cancels the supplied job.  Uses a dedicated pre-created job.
"  Polls until the job reaches 'Cancelled' (S3 Batch may
"  transition through intermediate states first).
" ============================================================
  METHOD update_job_status.
    " The job must be in a cancellable state.  Jobs with
    " ConfirmationRequired start as 'New' and may move to
    " 'Suspended'; both are cancellable.
    ao_s3c_actions->update_job_status(
      iv_account_id = av_account_id
      iv_job_id     = av_cancel_job_id ).

    " Poll until the status transitions to Cancelled.
    wait_for_job_status(
      iv_job_id         = av_cancel_job_id
      iv_desired_status = 'Cancelled'
      iv_max_attempts   = 20 ).

    " Final assertion: status must be Cancelled.
    DATA(lo_desc) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = av_cancel_job_id ).

    cl_abap_unit_assert=>assert_equals(
      exp = 'Cancelled'
      act = lo_desc->get_job( )->get_status( )
      msg = 'update_job_status: job status must be Cancelled' ).
  ENDMETHOD.

" ============================================================
"  Test: describe_job
"  Exercises /awsex/cl_s3c_actions=>describe_job.
"  Uses the shared read-only job.  Validates that the raw
"  DescribeJob response returns the expected job metadata.
" ============================================================
  METHOD describe_job.
    " Call the action method — it emits an informational MESSAGE internally.
    ao_s3c_actions->describe_job(
      iv_account_id = av_account_id
      iv_job_id     = av_shared_job_id ).

    " Independent verification: raw DescribeJob must return correct values.
    DATA(lo_result) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = av_shared_job_id ).
    DATA(lo_job) = lo_result->get_job( ).

    cl_abap_unit_assert=>assert_equals(
      exp = av_shared_job_id
      act = lo_job->get_jobid( )
      msg = 'describe_job: returned job ID must match the requested ID' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_job->get_status( )
      msg = 'describe_job: job status must not be empty' ).

    cl_abap_unit_assert=>assert_equals(
      exp = av_role_arn
      act = lo_job->get_rolearn( )
      msg = 'describe_job: role ARN must match the role used at creation' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_job->get_priority( )
      msg = 'describe_job: job priority must not be zero' ).
  ENDMETHOD.

" ============================================================
"  Test: get_job_tagging
"  Exercises /awsex/cl_s3c_actions=>get_job_tagging.
"  The shared job was created with the 'convert_test' tag; this
"  test verifies that at least that tag is returned.
" ============================================================
  METHOD get_job_tagging.
    ao_s3c_actions->get_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_shared_job_id ).

    " Independent verification via the raw client.
    DATA(lo_result) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_shared_job_id ).

    DATA(lt_tags) = lo_result->get_tags( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_tags
      msg = 'get_job_tagging: must return at least one tag' ).

    " The shared job must have the convert_test tag set during class_setup.
    DATA lv_found_convert_test TYPE abap_bool.
    LOOP AT lt_tags INTO DATA(lo_tag).
      IF lo_tag->get_key( ) = 'convert_test' AND lo_tag->get_value( ) = 'true'.
        lv_found_convert_test = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found_convert_test
      msg = 'get_job_tagging: convert_test tag must be present on shared job' ).
  ENDMETHOD.

" ============================================================
"  Test: put_job_tagging
"  Exercises /awsex/cl_s3c_actions=>put_job_tagging.
"  Uses a dedicated pre-created job.  Verifies exactly two tags
"  are present after the operation and checks their key/value.
" ============================================================
  METHOD put_job_tagging.
    ao_s3c_actions->put_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_tag_job_id ).

    DATA(lo_result) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_tag_job_id ).

    DATA(lt_tags) = lo_result->get_tags( ).

    cl_abap_unit_assert=>assert_equals(
      exp = 2
      act = lines( lt_tags )
      msg = 'put_job_tagging: must result in exactly 2 tags on the job' ).

    DATA lv_found_env  TYPE abap_bool.
    DATA lv_found_team TYPE abap_bool.
    LOOP AT lt_tags INTO DATA(lo_tag).
      CASE lo_tag->get_key( ).
        WHEN 'Environment'.
          cl_abap_unit_assert=>assert_equals(
            exp = 'Development'
            act = lo_tag->get_value( )
            msg = 'put_job_tagging: Environment tag value must be Development' ).
          lv_found_env = abap_true.
        WHEN 'Team'.
          cl_abap_unit_assert=>assert_equals(
            exp = 'DataProcessing'
            act = lo_tag->get_value( )
            msg = 'put_job_tagging: Team tag value must be DataProcessing' ).
          lv_found_team = abap_true.
      ENDCASE.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found_env
      msg = 'put_job_tagging: Environment tag must be present' ).
    cl_abap_unit_assert=>assert_true(
      act = lv_found_team
      msg = 'put_job_tagging: Team tag must be present' ).
  ENDMETHOD.

" ============================================================
"  Test: list_jobs
"  Exercises /awsex/cl_s3c_actions=>list_jobs.
"  Verifies that the shared pre-created job appears in the
"  result set when filtering for all possible job statuses.
" ============================================================
  METHOD list_jobs.
    ao_s3c_actions->list_jobs( iv_account_id = av_account_id ).

    " Independent verification: raw ListJobs must include the shared job.
    DATA lt_statuses TYPE /aws1/cl_s3cjobstatuslist_w=>tt_jobstatuslist.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'New' )       TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Suspended' ) TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Ready' )     TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Active' )    TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Paused' )    TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Pausing' )   TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Preparing' ) TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Complete' )  TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Cancelled' ) TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Failed' )    TO lt_statuses.

    DATA(lo_result) = ao_s3c->listjobs(
      iv_accountid   = av_account_id
      it_jobstatuses = lt_statuses ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_jobs( )
      msg = 'list_jobs: result must contain at least one job' ).

    DATA lv_found TYPE abap_bool.
    LOOP AT lo_result->get_jobs( ) INTO DATA(lo_jld).
      IF lo_jld->get_jobid( ) = av_shared_job_id.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_jobs: shared job { av_shared_job_id } must appear in result| ).
  ENDMETHOD.

" ============================================================
"  Test: delete_job_tagging
"  Exercises /awsex/cl_s3c_actions=>delete_job_tagging.
"  Uses a dedicated pre-created job.  Pre-populates a tag,
"  then calls the action and asserts the tag list is empty.
" ============================================================
  METHOD delete_job_tagging.
    " First put a tag on the dedicated job so there is something to delete.
    DATA lt_pre_tags TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag(
      iv_key   = 'TempKey'
      iv_value = 'TempValue' ) TO lt_pre_tags.

    ao_s3c->putjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_del_tag_job_id
      it_tags      = lt_pre_tags ).

    " Confirm the tag is really there before we delete it.
    DATA(lo_before) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_del_tag_job_id ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_before->get_tags( )
      msg = 'delete_job_tagging: pre-condition — tag must exist before delete' ).

    " Call the action method under test.
    ao_s3c_actions->delete_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_del_tag_job_id ).

    " Verify all tags have been removed.
    DATA(lo_after) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_del_tag_job_id ).

    cl_abap_unit_assert=>assert_initial(
      act = lo_after->get_tags( )
      msg = 'delete_job_tagging: all tags must be removed after delete' ).
  ENDMETHOD.

ENDCLASS.
