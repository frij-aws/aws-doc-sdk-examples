" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_s3c_actions DEFINITION DEFERRED.
CLASS /awsex/cl_s3c_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_s3c_actions.

CLASS ltc_awsex_cl_s3c_actions DEFINITION FOR TESTING
  DURATION LONG
  RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " ── Shared service clients ────────────────────────────────────────
    CLASS-DATA ao_s3c     TYPE REF TO /aws1/if_s3c.
    CLASS-DATA ao_s3      TYPE REF TO /aws1/if_s3.
    CLASS-DATA ao_iam     TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_session TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_actions TYPE REF TO /awsex/cl_s3c_actions.

    " ── Shared resource handles ───────────────────────────────────────
    CLASS-DATA av_account_id    TYPE /aws1/s3caccountid.
    CLASS-DATA av_bucket_name   TYPE /aws1/s3_bucketname.
    CLASS-DATA av_bucket_arn    TYPE /aws1/s3cs3bucketarnstring.
    CLASS-DATA av_role_name     TYPE /aws1/iamrolenametype.
    CLASS-DATA av_role_arn      TYPE /aws1/s3ciamrolearn.
    CLASS-DATA av_manifest_arn  TYPE /aws1/s3cs3keyarnstring.
    CLASS-DATA av_manifest_etag TYPE /aws1/s3cnonemptymaxlength1000.

    " ── One dedicated job per mutating test + one shared read-only job ─
    "    (jobs cannot be un-mutated so each mutating test needs its own)
    CLASS-DATA av_job_describe    TYPE /aws1/s3cjobid.  " describe_job
    CLASS-DATA av_job_list        TYPE /aws1/s3cjobid.  " list_jobs
    CLASS-DATA av_job_priority    TYPE /aws1/s3cjobid.  " update_job_priority
    CLASS-DATA av_job_cancel      TYPE /aws1/s3cjobid.  " update_job_status (cancel)
    CLASS-DATA av_job_put_tag     TYPE /aws1/s3cjobid.  " put_job_tagging
    CLASS-DATA av_job_get_tag     TYPE /aws1/s3cjobid.  " get_job_tagging
    CLASS-DATA av_job_del_tag     TYPE /aws1/s3cjobid.  " delete_job_tagging

    " ── Test method declarations ──────────────────────────────────────
    METHODS create_job          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_job_priority FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_job_status   FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS describe_job        FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS get_job_tagging     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS put_job_tagging     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_jobs           FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_job_tagging  FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown.

    " ── Internal helpers ─────────────────────────────────────────────
    " Create one Batch job (ConfirmationRequired=true → stays Suspended).
    CLASS-METHODS create_test_job
      RETURNING
        VALUE(rv_job_id) TYPE /aws1/s3cjobid
      RAISING
        /aws1/cx_rt_generic.

    " Poll DescribeJob until status leaves transient states New/Preparing.
    CLASS-METHODS wait_for_job_ready
      IMPORTING
        iv_job_id TYPE /aws1/s3cjobid
      RAISING
        /aws1/cx_rt_generic.

    " Cancel a single job; ignore errors (job may already be terminal).
    CLASS-METHODS cancel_job_safe
      IMPORTING
        iv_job_id TYPE /aws1/s3cjobid.

ENDCLASS.


CLASS ltc_awsex_cl_s3c_actions IMPLEMENTATION.

* =====================================================================
* class_setup
* =====================================================================
  METHOD class_setup.
    DATA lv_uuid      TYPE string.
    DATA lv_region    TYPE string.
    DATA lv_role_trust TYPE /aws1/iampolicydocumenttype.
    DATA lv_role_perm  TYPE /aws1/iampolicydocumenttype.

    ao_session  = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_s3c      = /aws1/cl_s3c_factory=>create( ao_session ).
    ao_s3       = /aws1/cl_s3_factory=>create( ao_session ).
    ao_iam      = /aws1/cl_iam_factory=>create( ao_session ).
    ao_actions  = NEW /awsex/cl_s3c_actions( ).

    av_account_id = ao_session->get_account_id( ).
    lv_region     = ao_session->get_region( ).

    " ── 1. Unique resource names ─────────────────────────────────────
    lv_uuid = /awsex/cl_utils=>get_random_string( ).
    CONDENSE lv_uuid NO-GAPS.
    TRANSLATE lv_uuid TO LOWER CASE.

    " Bucket names must be globally unique and lowercase.
    av_bucket_name = |sap-abap-s3c-{ lv_uuid(12) }|.
    av_bucket_arn  = |arn:aws:s3:::{ av_bucket_name }|.
    av_role_name   = |sap-abap-s3c-role-{ lv_uuid(8) }|.

    " ── 2. Create S3 bucket (manifest + reports) ─────────────────────
    /awsex/cl_utils=>create_bucket(
      iv_bucket  = av_bucket_name
      io_s3      = ao_s3
      io_session = ao_session ).

    ao_s3->putbuckettagging(
      iv_bucket  = av_bucket_name
      io_tagging = NEW /aws1/cl_s3_tagging(
        it_tagset = VALUE /aws1/cl_s3_tag=>tt_tagset(
          ( NEW /aws1/cl_s3_tag( iv_key = 'convert_test' iv_value = 'true' ) )
        )
      )
    ).

    " ── 3. Upload sample objects + manifest CSV ───────────────────────
    DATA lt_keys TYPE STANDARD TABLE OF string WITH DEFAULT KEY.
    APPEND 'sample-obj-1.txt' TO lt_keys.
    APPEND 'sample-obj-2.txt' TO lt_keys.

    LOOP AT lt_keys INTO DATA(lv_key).
      ao_s3->putobject(
        iv_bucket = av_bucket_name
        iv_key    = lv_key
        iv_body   = cl_abap_codepage=>convert_to( |Content of { lv_key }| )
      ).
    ENDLOOP.

    " Build CSV: bucket,key per line.
    DATA lv_csv TYPE string.
    LOOP AT lt_keys INTO lv_key.
      lv_csv = lv_csv && |{ av_bucket_name },{ lv_key }\n|.
    ENDLOOP.

    ao_s3->putobject(
      iv_bucket = av_bucket_name
      iv_key    = 'job-manifest.csv'
      iv_body   = cl_abap_codepage=>convert_to( lv_csv )
    ).

    " Read back the ETag (strip surrounding quotes).
    DATA(lo_head) = ao_s3->headobject(
      iv_bucket = av_bucket_name
      iv_key    = 'job-manifest.csv'
    ).
    av_manifest_etag = lo_head->get_etag( ).
    REPLACE ALL OCCURRENCES OF '"' IN av_manifest_etag WITH ''.

    av_manifest_arn = |arn:aws:s3:::{ av_bucket_name }/job-manifest.csv|.

    " ── 4. Create IAM role for S3 Batch Operations ───────────────────
    "    Trust policy: allow batchoperations.s3.amazonaws.com to assume.
    lv_role_trust =
      `{"Version":"2012-10-17","Statement":[` &&
      `{"Effect":"Allow","Principal":{"Service":"batchoperations.s3.amazonaws.com"},` &&
      `"Action":"sts:AssumeRole"}]}`.

    DATA(lo_role_result) = ao_iam->createrole(
      iv_rolename                 = av_role_name
      iv_assumerolepolicydocument = lv_role_trust
      iv_description              = 'SAP ABAP s3c test role'
      it_tags                     = VALUE /aws1/cl_iamtag=>tt_taglisttype(
        ( NEW /aws1/cl_iamtag( iv_key = 'convert_test' iv_value = 'true' ) )
      )
    ).
    av_role_arn = lo_role_result->get_role( )->get_arn( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = av_role_arn
      msg = 'class_setup: IAM role ARN must not be empty' ).

    " ── 5. Attach inline permissions policy to the role ───────────────
    "    S3 Batch Operations needs:
    "      s3:GetObject / s3:GetObjectVersion      – read manifest objects
    "      s3:PutObjectTagging                     – the job operation
    "      s3:GetBucketLocation / s3:ListBucket    – manifest bucket discovery
    "      s3:PutObject                            – write job reports
    lv_role_perm =
      `{"Version":"2012-10-17","Statement":[` &&
      `{"Sid":"BatchObjectOps","Effect":"Allow",` &&
      `"Action":["s3:GetObject","s3:GetObjectVersion",` &&
      `"s3:PutObjectTagging","s3:GetBucketLocation","s3:ListBucket"],` &&
      `"Resource":["arn:aws:s3:::*","arn:aws:s3:::*/*"]},` &&
      `{"Sid":"BatchReports","Effect":"Allow",` &&
      `"Action":"s3:PutObject",` &&
      `"Resource":"arn:aws:s3:::` && av_bucket_name && `/*"}]}`.

    ao_iam->putrolepolicy(
      iv_rolename      = av_role_name
      iv_policyname    = 's3BatchPermissions'
      iv_policydocument = lv_role_perm
    ).

    " IAM is eventually consistent – wait for the role + policy to propagate.
    WAIT UP TO 10 SECONDS.

    " ── 6. Create one dedicated job per mutating test ─────────────────
    av_job_describe = create_test_job( ).
    wait_for_job_ready( av_job_describe ).

    av_job_list = create_test_job( ).
    wait_for_job_ready( av_job_list ).

    av_job_priority = create_test_job( ).
    wait_for_job_ready( av_job_priority ).

    av_job_cancel = create_test_job( ).
    wait_for_job_ready( av_job_cancel ).

    av_job_put_tag = create_test_job( ).
    wait_for_job_ready( av_job_put_tag ).

    av_job_get_tag = create_test_job( ).
    wait_for_job_ready( av_job_get_tag ).

    av_job_del_tag = create_test_job( ).
    wait_for_job_ready( av_job_del_tag ).
  ENDMETHOD.


* =====================================================================
* class_teardown
* =====================================================================
  METHOD class_teardown.
    " Cancel every job we know about (ignore errors – already terminal).
    cancel_job_safe( av_job_describe ).
    cancel_job_safe( av_job_list     ).
    cancel_job_safe( av_job_priority ).
    cancel_job_safe( av_job_cancel   ).
    cancel_job_safe( av_job_put_tag  ).
    cancel_job_safe( av_job_get_tag  ).
    cancel_job_safe( av_job_del_tag  ).

    " Delete inline policy, then the role.
    TRY.
        ao_iam->deleterolepolicy(
          iv_rolename   = av_role_name
          iv_policyname = 's3BatchPermissions'
        ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iam->deleterole( iv_rolename = av_role_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Delete bucket (objects + bucket).
    TRY.
        /awsex/cl_utils=>cleanup_bucket( io_s3 = ao_s3 iv_bucket = av_bucket_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


* =====================================================================
* create_test_job  (class-level helper)
* =====================================================================
  METHOD create_test_job.
    DATA(lo_result) = ao_s3c->createjob(
      iv_accountid            = av_account_id
      iv_confirmationrequired = abap_true
      iv_description          = 'SAP ABAP s3c unit-test job'
      iv_priority             = 10
      iv_rolearn              = av_role_arn
      io_operation            = NEW /aws1/cl_s3cjoboperation(
        io_s3putobjecttagging = NEW /aws1/cl_s3cs3setobjecttagop(
          it_tagset = VALUE /aws1/cl_s3cs3tag=>tt_s3tagset(
            ( NEW /aws1/cl_s3cs3tag( iv_key = 'convert_test' iv_value = 'true' ) )
          )
        )
      )
      io_report               = NEW /aws1/cl_s3cjobreport(
        iv_bucket      = av_bucket_arn
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
          iv_objectarn = av_manifest_arn
          iv_etag      = av_manifest_etag
        )
      )
    ).

    rv_job_id = lo_result->get_jobid( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = rv_job_id
      msg = 'create_test_job: CreateJob returned an empty job ID' ).
  ENDMETHOD.


* =====================================================================
* wait_for_job_ready  (class-level helper)
* =====================================================================
  METHOD wait_for_job_ready.
    " Poll until the job leaves transient states (New, Preparing).
    " ConfirmationRequired jobs land in Suspended – that is "ready".
    CONSTANTS cv_max_iter TYPE i VALUE 30.
    DO cv_max_iter TIMES.
      DATA(lo_desc) = ao_s3c->describejob(
        iv_accountid = av_account_id
        iv_jobid     = iv_job_id
      ).
      DATA(lv_status) = lo_desc->get_job( )->get_status( ).
      IF lv_status <> 'New' AND lv_status <> 'Preparing'.
        RETURN.
      ENDIF.
      WAIT UP TO 10 SECONDS.
    ENDDO.
    cl_abap_unit_assert=>fail(
      msg = |wait_for_job_ready: job { iv_job_id } still transient after | &&
            |{ cv_max_iter * 10 } s| ).
  ENDMETHOD.


* =====================================================================
* cancel_job_safe  (class-level helper)
* =====================================================================
  METHOD cancel_job_safe.
    IF iv_job_id IS INITIAL.
      RETURN.
    ENDIF.
    TRY.
        ao_s3c->updatejobstatus(
          iv_accountid          = av_account_id
          iv_jobid              = iv_job_id
          iv_requestedjobstatus = 'Cancelled'
        ).
      CATCH /aws1/cx_rt_generic.
        " Already terminal or not found – ignore.
    ENDTRY.
  ENDMETHOD.


* =====================================================================
* TEST: create_job
* =====================================================================
  METHOD create_job.
    " Call the action under test and capture the returned job ID.
    DATA(lv_new_job_id) = ao_actions->create_job(
      iv_account_id    = av_account_id
      iv_role_arn      = av_role_arn
      iv_manifest_arn  = av_manifest_arn
      iv_manifest_etag = av_manifest_etag
      iv_report_bucket = av_bucket_arn
    ).

    " The operation must succeed and return a non-empty job ID.
    cl_abap_unit_assert=>assert_not_initial(
      act = lv_new_job_id
      msg = 'create_job: action must return a non-empty job ID' ).

    " Verify the job actually exists by describing it.
    DATA(lo_desc) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = lv_new_job_id
    ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_desc->get_job( )->get_jobid( )
      exp = lv_new_job_id
      msg = 'create_job: DescribeJob must return the same job ID' ).

    " Clean up this test-local job immediately.
    cancel_job_safe( lv_new_job_id ).
  ENDMETHOD.


* =====================================================================
* TEST: update_job_priority
* =====================================================================
  METHOD update_job_priority.
    " Call the action – it hard-codes priority 60.
    ao_actions->update_job_priority(
      iv_account_id = av_account_id
      iv_job_id     = av_job_priority
    ).

    " Verify the priority was actually changed on the service side.
    DATA(lo_desc) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = av_job_priority
    ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_desc->get_job( )->get_priority( )
      exp = 60
      msg = 'update_job_priority: priority must be 60 after the call' ).
  ENDMETHOD.


* =====================================================================
* TEST: update_job_status  (cancel)
* =====================================================================
  METHOD update_job_status.
    " The action cancels the job (RequestedJobStatus = 'Cancelled').
    ao_actions->update_job_status(
      iv_account_id = av_account_id
      iv_job_id     = av_job_cancel
    ).

    " Confirm via DescribeJob that the status is now Cancelled.
    DATA(lo_desc) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = av_job_cancel
    ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_desc->get_job( )->get_status( )
      exp = 'Cancelled'
      msg = 'update_job_status: job status must be Cancelled after the call' ).
  ENDMETHOD.


* =====================================================================
* TEST: describe_job
* =====================================================================
  METHOD describe_job.
    " Call the action and validate its RETURNING value directly.
    DATA(lo_result) = ao_actions->describe_job(
      iv_account_id = av_account_id
      iv_job_id     = av_job_describe
    ).

    " Result object must be bound.
    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'describe_job: returned result object must be bound' ).

    " Job ID in the result must match what we asked for.
    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_job( )->get_jobid( )
      exp = av_job_describe
      msg = 'describe_job: returned job ID must match the requested ID' ).

    " Status must be a non-empty string (Suspended / Ready / Active / …).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_job( )->get_status( )
      msg = 'describe_job: job status must not be empty' ).
  ENDMETHOD.


* =====================================================================
* TEST: put_job_tagging
* =====================================================================
  METHOD put_job_tagging.
    " Delete any pre-existing tags first so we get an exact count.
    TRY.
        ao_s3c->deletejobtagging(
          iv_accountid = av_account_id
          iv_jobid     = av_job_put_tag
        ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Call the action under test (applies Environment + Team tags).
    ao_actions->put_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_job_put_tag
    ).

    " Verify via GetJobTagging that exactly 2 tags were applied.
    DATA(lo_result) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_put_tag
    ).
    cl_abap_unit_assert=>assert_equals(
      act = lines( lo_result->get_tags( ) )
      exp = 2
      msg = 'put_job_tagging: exactly 2 tags must be present after the call' ).
  ENDMETHOD.


* =====================================================================
* TEST: get_job_tagging
* =====================================================================
  METHOD get_job_tagging.
    " Ensure at least one tag exists before calling the action.
    ao_s3c->putjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_get_tag
      it_tags      = VALUE /aws1/cl_s3cs3tag=>tt_s3tagset(
        ( NEW /aws1/cl_s3cs3tag( iv_key = 'Environment' iv_value = 'Test' ) )
      )
    ).

    " Call the action and validate its RETURNING value directly.
    DATA(lo_result) = ao_actions->get_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_job_get_tag
    ).

    " Result object must be bound.
    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'get_job_tagging: returned result object must be bound' ).

    " The tag we seeded must be present in the returned list.
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lines( lo_result->get_tags( ) ) >= 1 )
      msg = 'get_job_tagging: at least one tag must exist on the job' ).
  ENDMETHOD.


* =====================================================================
* TEST: list_jobs
* =====================================================================
  METHOD list_jobs.
    " Call the action and validate its RETURNING value directly.
    DATA(lo_result) = ao_actions->list_jobs( iv_account_id = av_account_id ).

    " Result object must be bound.
    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_jobs: returned result object must be bound' ).

    " We created several jobs in class_setup – at least one must appear.
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lines( lo_result->get_jobs( ) ) >= 1 )
      msg = 'list_jobs: at least one job must be returned' ).

    " Verify our list-test job is among the results.
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_result->get_jobs( ) INTO DATA(lo_job_entry).
      IF lo_job_entry->get_jobid( ) = av_job_list.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_jobs: job { av_job_list } must appear in the listing| ).
  ENDMETHOD.


* =====================================================================
* TEST: delete_job_tagging
* =====================================================================
  METHOD delete_job_tagging.
    " Pre-condition: put a tag on the job so there is something to delete.
    ao_s3c->putjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_del_tag
      it_tags      = VALUE /aws1/cl_s3cs3tag=>tt_s3tagset(
        ( NEW /aws1/cl_s3cs3tag( iv_key = 'ToDelete' iv_value = 'yes' ) )
      )
    ).

    " Call the action under test.
    ao_actions->delete_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_job_del_tag
    ).

    " Verify via GetJobTagging that the tag set is now empty.
    DATA(lo_result) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_del_tag
    ).
    cl_abap_unit_assert=>assert_equals(
      act = lines( lo_result->get_tags( ) )
      exp = 0
      msg = 'delete_job_tagging: tag list must be empty after the call' ).
  ENDMETHOD.

ENDCLASS.
