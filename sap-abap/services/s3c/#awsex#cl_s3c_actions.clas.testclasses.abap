" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_s3c_actions DEFINITION DEFERRED.
CLASS /awsex/cl_s3c_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_s3c_actions.

CLASS ltc_awsex_cl_s3c_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    CLASS-DATA ao_s3        TYPE REF TO /aws1/if_s3.
    CLASS-DATA ao_s3c       TYPE REF TO /aws1/if_s3c.
    CLASS-DATA ao_sts       TYPE REF TO /aws1/if_sts.
    CLASS-DATA ao_iam       TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_session   TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_s3c_acts  TYPE REF TO /awsex/cl_s3c_actions.

    " Shared resources set up once in class_setup
    CLASS-DATA gv_account_id    TYPE /aws1/s3caccountid.
    CLASS-DATA gv_bucket_name   TYPE /aws1/s3_bucketname.
    CLASS-DATA gv_role_arn      TYPE /aws1/s3ciamrolearn.
    CLASS-DATA gv_role_name     TYPE /aws1/iamrolename.
    CLASS-DATA gv_manifest_arn  TYPE /aws1/s3cs3keyarnstring.
    CLASS-DATA gv_manifest_etag TYPE /aws1/s3cnonemptymaxlength1024st.
    CLASS-DATA gv_report_bucket TYPE /aws1/s3cs3bucketarnstring.
    CLASS-DATA gv_uuid          TYPE string.

    " Shared job for read-only tests (describe, list, get/put/delete tags)
    CLASS-DATA gv_shared_job_id TYPE /aws1/s3cjobid.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    METHODS create_job          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS describe_job        FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_job_priority FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_job_status   FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS get_job_tagging     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS put_job_tagging     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_jobs           FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_job_tagging  FOR TESTING RAISING /aws1/cx_rt_generic.

    " Helper: create a fresh S3 Batch job and return its ID.
    " The job uses ConfirmationRequired=true so it lands in Suspended state.
    CLASS-METHODS create_fresh_job
      RETURNING
        VALUE(rv_job_id) TYPE /aws1/s3cjobid
      RAISING
        /aws1/cx_rt_generic.

    " Helper: poll until the given job reaches iv_desired_status or a terminal state.
    CLASS-METHODS wait_for_job
      IMPORTING
        iv_job_id        TYPE /aws1/s3cjobid
        iv_desired_status TYPE string
      RAISING
        /aws1/cx_rt_generic.

ENDCLASS.

CLASS ltc_awsex_cl_s3c_actions IMPLEMENTATION.

* ─────────────────────────────────────────────────────────────────────────────
  METHOD class_setup.
* ─────────────────────────────────────────────────────────────────────────────
    DATA lv_uuid_string   TYPE string.
    DATA lv_region        TYPE /aws1/s3_bucketlocationcnstrnt.
    DATA lv_trust_policy  TYPE string.
    DATA lv_inline_policy TYPE string.
    DATA lv_file_xstr     TYPE xstring.
    DATA lv_manifest_body TYPE string.
    DATA lv_manifest_xstr TYPE xstring.
    DATA lv_etag_raw      TYPE string.

    ao_session  = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_s3       = /aws1/cl_s3_factory=>create( ao_session ).
    ao_s3c      = /aws1/cl_s3c_factory=>create( ao_session ).
    ao_sts      = /aws1/cl_sts_factory=>create( ao_session ).
    ao_iam      = /aws1/cl_iam_factory=>create( ao_session ).
    ao_s3c_acts = NEW /awsex/cl_s3c_actions( ).

    " ── Unique suffix for all resource names ───────────────────────────────
    lv_uuid_string = /awsex/cl_utils=>get_random_string( ).
    CONDENSE lv_uuid_string NO-GAPS.
    gv_uuid = to_lower( lv_uuid_string(10) ).

    " ── Resolve AWS account ID via STS ────────────────────────────────────
    DATA(lo_sts_result) = ao_sts->getcalleridentity( ).
    gv_account_id = lo_sts_result->get_account( ).
    IF gv_account_id IS INITIAL.
      cl_abap_unit_assert=>fail( msg = 'Could not determine AWS account ID' ).
    ENDIF.

    " ── Create test S3 bucket (respects us-east-1 constraint rule) ─────────
    gv_bucket_name = |s3c-test-{ gv_uuid }|.
    /awsex/cl_utils=>create_bucket(
      iv_bucket  = gv_bucket_name
      io_s3      = ao_s3
      io_session = ao_session ).

    " Tag bucket with convert_test
    TRY.
        ao_s3->putbuckettagging(
          iv_bucket   = gv_bucket_name
          io_tagging  = NEW /aws1/cl_s3_tagging(
            it_tagset = VALUE /aws1/cl_s3_tag=>tt_tagset(
              ( NEW /aws1/cl_s3_tag( iv_key = 'convert_test' iv_value = 'true' ) )
            ) ) ).
      CATCH /aws1/cx_rt_generic.
        " Tagging failure is non-fatal here
    ENDTRY.

    " ── Upload three sample objects ────────────────────────────────────────
    lv_file_xstr = cl_abap_codepage=>convert_to( 'Content for object1.txt' ).
    ao_s3->putobject( iv_bucket = gv_bucket_name iv_key = 'object1.txt' iv_body = lv_file_xstr ).
    lv_file_xstr = cl_abap_codepage=>convert_to( 'Content for object2.txt' ).
    ao_s3->putobject( iv_bucket = gv_bucket_name iv_key = 'object2.txt' iv_body = lv_file_xstr ).
    lv_file_xstr = cl_abap_codepage=>convert_to( 'Content for object3.txt' ).
    ao_s3->putobject( iv_bucket = gv_bucket_name iv_key = 'object3.txt' iv_body = lv_file_xstr ).

    " ── Build and upload the job manifest CSV ─────────────────────────────
    lv_manifest_body = |{ gv_bucket_name },object1.txt\n| &&
                       |{ gv_bucket_name },object2.txt\n| &&
                       |{ gv_bucket_name },object3.txt\n|.
    lv_manifest_xstr = cl_abap_codepage=>convert_to( lv_manifest_body ).
    ao_s3->putobject(
      iv_bucket = gv_bucket_name
      iv_key    = 'job-manifest.csv'
      iv_body   = lv_manifest_xstr ).

    " ── Retrieve the manifest ETag (strip surrounding quotes) ─────────────
    DATA(lo_head) = ao_s3->headobject(
      iv_bucket = gv_bucket_name
      iv_key    = 'job-manifest.csv' ).
    lv_etag_raw = lo_head->get_etag( ).
    REPLACE ALL OCCURRENCES OF '"' IN lv_etag_raw WITH ''.
    gv_manifest_etag = lv_etag_raw.

    IF gv_manifest_etag IS INITIAL.
      cl_abap_unit_assert=>fail( msg = 'Could not retrieve manifest ETag' ).
    ENDIF.

    gv_manifest_arn  = |arn:aws:s3:::{ gv_bucket_name }/job-manifest.csv|.
    gv_report_bucket = |arn:aws:s3:::{ gv_bucket_name }|.

    " ── Create IAM role that S3 Batch Operations will assume ───────────────
    gv_role_name = |s3c-test-role-{ gv_uuid }|.
    lv_trust_policy =
      '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",' &&
      '"Principal":{"Service":"batchoperations.s3.amazonaws.com"},' &&
      '"Action":"sts:AssumeRole"}]}'.

    DATA(lo_iam_result) = ao_iam->createrole(
      iv_rolename                 = gv_role_name
      iv_assumerolepolicydocument = lv_trust_policy
      iv_description              = 'Role for S3 Batch Operations ABAP test'
      it_tags                     = VALUE /aws1/cl_iamtag=>tt_taglisttype(
        ( NEW /aws1/cl_iamtag( iv_key = 'convert_test' iv_value = 'true' ) )
      ) ).
    gv_role_arn = lo_iam_result->get_role( )->get_arn( ).

    IF gv_role_arn IS INITIAL.
      cl_abap_unit_assert=>fail( msg = 'Failed to create IAM role' ).
    ENDIF.

    " ── Attach an inline policy that grants the role the minimum permissions
    "    required by S3 Batch Operations for PutObjectTagging jobs.
    "    Permissions needed:
    "      s3:GetObject, s3:GetObjectVersion – read the objects in the manifest
    "      s3:PutObjectTagging               – apply tags to those objects
    "      s3:GetBucketLocation              – resolve the bucket region
    "      s3:GetBucketObjectLockConfiguration – required for some job types
    "      s3:PutObject, s3:GetObject,
    "      s3:DeleteObject on the report prefix – write the job completion report
    " ─────────────────────────────────────────────────────────────────────────
    lv_inline_policy =
      '{"Version":"2012-10-17","Statement":[' &&
        '{"Sid":"ReadObjects","Effect":"Allow",' &&
          '"Action":["s3:GetObject","s3:GetObjectVersion",' &&
                   '"s3:GetObjectTagging","s3:GetObjectVersionTagging"],' &&
          '"Resource":"arn:aws:s3:::' && gv_bucket_name && '/*"},' &&
        '{"Sid":"TagObjects","Effect":"Allow",' &&
          '"Action":["s3:PutObjectTagging","s3:PutObjectVersionTagging"],' &&
          '"Resource":"arn:aws:s3:::' && gv_bucket_name && '/*"},' &&
        '{"Sid":"BucketAccess","Effect":"Allow",' &&
          '"Action":["s3:GetBucketLocation","s3:GetBucketObjectLockConfiguration",' &&
                   '"s3:GetBucketVersioning","s3:ListBucket","s3:ListBucketVersions"],' &&
          '"Resource":"arn:aws:s3:::' && gv_bucket_name && '"},' &&
        '{"Sid":"WriteReports","Effect":"Allow",' &&
          '"Action":["s3:PutObject","s3:GetObject","s3:GetBucketLocation"],' &&
          '"Resource":["arn:aws:s3:::' && gv_bucket_name && '/batch-op-reports/*",' &&
                      '"arn:aws:s3:::' && gv_bucket_name && '"]}' &&
      ']}' .

    ao_iam->putrolepolicy(
      iv_rolename       = gv_role_name
      iv_policyname     = 's3c-batch-policy'
      iv_policydocument = lv_inline_policy ).

    " IAM changes take a few seconds to propagate globally
    WAIT UP TO 15 SECONDS.

    " ── Create the shared read-only job ───────────────────────────────────
    "    ConfirmationRequired = true  →  job lands in Suspended state
    "    which is a stable state that supports describe/list/tag operations.
    gv_shared_job_id = create_fresh_job( ).

    IF gv_shared_job_id IS INITIAL.
      cl_abap_unit_assert=>fail( msg = 'Failed to create shared S3 Batch Operations job' ).
    ENDIF.

    wait_for_job( iv_job_id = gv_shared_job_id iv_desired_status = 'Suspended' ).
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
  METHOD class_teardown.
* ─────────────────────────────────────────────────────────────────────────────

    " ── Cancel the shared job if still in a cancellable state ─────────────
    IF gv_shared_job_id IS NOT INITIAL.
      TRY.
          DATA(lo_desc) = ao_s3c->describejob(
            iv_accountid = gv_account_id
            iv_jobid     = gv_shared_job_id ).
          DATA(lv_st) = lo_desc->get_job( )->get_status( ).
          IF lv_st = 'Suspended' OR lv_st = 'Ready'
             OR lv_st = 'New'    OR lv_st = 'Active'.
            ao_s3c->updatejobstatus(
              iv_accountid          = gv_account_id
              iv_jobid              = gv_shared_job_id
              iv_requestedjobstatus = 'Cancelled' ).
          ENDIF.
        CATCH /aws1/cx_rt_generic.
          " Job may already be terminal – ignore
      ENDTRY.
    ENDIF.

    " ── Empty and delete the test bucket ──────────────────────────────────
    IF gv_bucket_name IS NOT INITIAL.
      TRY.
          /awsex/cl_utils=>cleanup_bucket( iv_bucket = gv_bucket_name io_s3 = ao_s3 ).
        CATCH /aws1/cx_rt_generic.
          " Ignore – bucket may already be gone
      ENDTRY.
    ENDIF.

    " ── Remove IAM inline policy then the role itself ─────────────────────
    IF gv_role_name IS NOT INITIAL.
      TRY.
          ao_iam->deleterolepolicy(
            iv_rolename   = gv_role_name
            iv_policyname = 's3c-batch-policy' ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
      TRY.
          ao_iam->deleterole( iv_rolename = gv_role_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
  METHOD create_fresh_job.
* ─────────────────────────────────────────────────────────────────────────────
    " Creates a brand-new S3 Batch job using the class-level shared infrastructure
    " and returns its Job ID.  ConfirmationRequired=true keeps it in Suspended.
    DATA(lo_result) = ao_s3c->createjob(
      iv_accountid            = gv_account_id
      iv_rolearn              = gv_role_arn
      iv_confirmationrequired = abap_true
      iv_priority             = 10
      iv_description          = |s3c-test-{ gv_uuid }|
      io_operation            = NEW /aws1/cl_s3cjoboperation(
        io_s3putobjecttagging = NEW /aws1/cl_s3cs3setobjecttagop(
          it_tagset = VALUE /aws1/cl_s3cs3tag=>tt_s3tagset(
            ( NEW /aws1/cl_s3cs3tag( iv_key = 'convert_test' iv_value = 'true' ) )
          )
        )
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
          iv_objectarn = gv_manifest_arn
          iv_etag      = gv_manifest_etag
        )
      )
      io_report               = NEW /aws1/cl_s3cjobreport(
        iv_bucket      = gv_report_bucket
        iv_format      = 'Report_CSV_20180820'
        iv_enabled     = abap_true
        iv_prefix      = 'batch-op-reports'
        iv_reportscope = 'AllTasks'
      )
    ).
    rv_job_id = lo_result->get_jobid( ).
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
  METHOD wait_for_job.
* ─────────────────────────────────────────────────────────────────────────────
    " Polls DescribeJob until the job reaches iv_desired_status or a terminal
    " state (Failed / Cancelled / Complete).  Times out after ~2.5 minutes.
    DATA lv_max TYPE i VALUE 30.
    DATA lv_i   TYPE i VALUE 0.
    DATA lv_cur TYPE string.

    WHILE lv_i < lv_max.
      TRY.
          DATA(lo_d) = ao_s3c->describejob(
            iv_accountid = gv_account_id
            iv_jobid     = iv_job_id ).
          lv_cur = lo_d->get_job( )->get_status( ).
          IF lv_cur = iv_desired_status.
            RETURN.
          ENDIF.
          IF lv_cur = 'Failed' OR lv_cur = 'Cancelled' OR lv_cur = 'Complete'.
            RETURN.
          ENDIF.
        CATCH /aws1/cx_rt_generic.
          " Job not visible yet – retry
      ENDTRY.
      WAIT UP TO 5 SECONDS.
      lv_i = lv_i + 1.
    ENDWHILE.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
  METHOD create_job.
* ─────────────────────────────────────────────────────────────────────────────
    " Calls the actions class method and verifies a Job ID is returned.
    " A fresh dedicated job is created; it is cancelled during cleanup.
    DATA(lv_new_job_id) = ao_s3c_acts->create_job(
      iv_account_id    = gv_account_id
      iv_role_arn      = gv_role_arn
      iv_manifest_arn  = gv_manifest_arn
      iv_manifest_etag = gv_manifest_etag
      iv_report_bucket = gv_report_bucket ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_new_job_id
      msg = 'create_job must return a non-empty Job ID' ).

    " Wait for the new job to reach Suspended, then cancel it
    wait_for_job( iv_job_id = lv_new_job_id iv_desired_status = 'Suspended' ).

    TRY.
        DATA(lo_st) = ao_s3c->describejob(
          iv_accountid = gv_account_id iv_jobid = lv_new_job_id ).
        DATA(lv_status) = lo_st->get_job( )->get_status( ).
        IF lv_status = 'Suspended' OR lv_status = 'Ready' OR lv_status = 'New'.
          ao_s3c->updatejobstatus(
            iv_accountid          = gv_account_id
            iv_jobid              = lv_new_job_id
            iv_requestedjobstatus = 'Cancelled' ).
        ENDIF.
      CATCH /aws1/cx_rt_generic.
        " Job is tagged convert_test=true; ignore cleanup errors
    ENDTRY.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
  METHOD describe_job.
* ─────────────────────────────────────────────────────────────────────────────
    " Calls the actions class method; verifies the returned status is non-empty
    " and that a direct SDK call confirms the same Job ID.
    ao_s3c_acts->describe_job(
      iv_account_id = gv_account_id
      iv_job_id     = gv_shared_job_id ).

    DATA(lo_verify) = ao_s3c->describejob(
      iv_accountid = gv_account_id
      iv_jobid     = gv_shared_job_id ).

    cl_abap_unit_assert=>assert_equals(
      exp = gv_shared_job_id
      act = lo_verify->get_job( )->get_jobid( )
      msg = 'Job ID returned by DescribeJob must match the shared job ID' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_verify->get_job( )->get_status( )
      msg = 'DescribeJob must return a non-empty job status' ).
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
  METHOD update_job_priority.
* ─────────────────────────────────────────────────────────────────────────────
    " Uses a dedicated fresh job to avoid order-dependency with other tests.
    DATA(lv_job_id) = create_fresh_job( ).
    wait_for_job( iv_job_id = lv_job_id iv_desired_status = 'Suspended' ).

    ao_s3c_acts->update_job_priority(
      iv_account_id = gv_account_id
      iv_job_id     = lv_job_id ).

    " Verify the priority is now 60 (hard-coded in the action method)
    DATA(lo_verify) = ao_s3c->describejob(
      iv_accountid = gv_account_id
      iv_jobid     = lv_job_id ).
    cl_abap_unit_assert=>assert_equals(
      exp = 60
      act = lo_verify->get_job( )->get_priority( )
      msg = 'Job priority must be 60 after update_job_priority' ).

    " Cancel the dedicated job
    TRY.
        ao_s3c->updatejobstatus(
          iv_accountid          = gv_account_id
          iv_jobid              = lv_job_id
          iv_requestedjobstatus = 'Cancelled' ).
      CATCH /aws1/cx_rt_generic.
        " Tagged convert_test=true; ignore
    ENDTRY.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
  METHOD update_job_status.
* ─────────────────────────────────────────────────────────────────────────────
    " Uses a dedicated fresh job so cancellation does not affect other tests.
    DATA(lv_job_id) = create_fresh_job( ).
    wait_for_job( iv_job_id = lv_job_id iv_desired_status = 'Suspended' ).

    " Verify the job is in a cancellable state before proceeding
    DATA(lo_pre) = ao_s3c->describejob(
      iv_accountid = gv_account_id iv_jobid = lv_job_id ).
    DATA(lv_pre_status) = lo_pre->get_job( )->get_status( ).
    IF lv_pre_status <> 'Suspended' AND lv_pre_status <> 'Ready'
       AND lv_pre_status <> 'New'.
      cl_abap_unit_assert=>fail(
        msg = |Job is in unexpected state '{ lv_pre_status }' – cannot cancel| ).
    ENDIF.

    ao_s3c_acts->update_job_status(
      iv_account_id       = gv_account_id
      iv_job_id           = lv_job_id
      iv_requested_status = 'Cancelled' ).

    " Verify the job is now Cancelled
    DATA(lo_verify) = ao_s3c->describejob(
      iv_accountid = gv_account_id iv_jobid = lv_job_id ).
    cl_abap_unit_assert=>assert_equals(
      exp = 'Cancelled'
      act = lo_verify->get_job( )->get_status( )
      msg = 'Job status must be Cancelled after update_job_status' ).
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
  METHOD put_job_tagging.
* ─────────────────────────────────────────────────────────────────────────────
    " Uses a dedicated fresh job so tag mutations are isolated.
    DATA(lv_job_id) = create_fresh_job( ).
    wait_for_job( iv_job_id = lv_job_id iv_desired_status = 'Suspended' ).

    " Ensure the job starts with no tags
    ao_s3c->deletejobtagging(
      iv_accountid = gv_account_id iv_jobid = lv_job_id ).

    ao_s3c_acts->put_job_tagging(
      iv_account_id = gv_account_id
      iv_job_id     = lv_job_id ).

    " Verify exactly 2 tags are present (Environment + Team)
    DATA(lo_tags) = ao_s3c->getjobtagging(
      iv_accountid = gv_account_id iv_jobid = lv_job_id ).
    DATA(lt_tags) = lo_tags->get_tags( ).
    cl_abap_unit_assert=>assert_equals(
      exp = 2
      act = lines( lt_tags )
      msg = 'put_job_tagging must store exactly 2 tags' ).

    " Verify tag keys are Environment and Team
    DATA lv_found_env  TYPE abap_bool.
    DATA lv_found_team TYPE abap_bool.
    LOOP AT lt_tags INTO DATA(lo_tag).
      IF lo_tag->get_key( ) = 'Environment'. lv_found_env  = abap_true. ENDIF.
      IF lo_tag->get_key( ) = 'Team'.        lv_found_team = abap_true. ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found_env  msg = 'Tag key ''Environment'' must be present' ).
    cl_abap_unit_assert=>assert_true(
      act = lv_found_team msg = 'Tag key ''Team'' must be present' ).

    " Cancel the dedicated job
    TRY.
        ao_s3c->updatejobstatus(
          iv_accountid          = gv_account_id
          iv_jobid              = lv_job_id
          iv_requestedjobstatus = 'Cancelled' ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
  METHOD get_job_tagging.
* ─────────────────────────────────────────────────────────────────────────────
    " Pre-load a known tag on the shared job, then call the action and verify.
    ao_s3c->putjobtagging(
      iv_accountid = gv_account_id
      iv_jobid     = gv_shared_job_id
      it_tags      = VALUE /aws1/cl_s3cs3tag=>tt_s3tagset(
        ( NEW /aws1/cl_s3cs3tag( iv_key = 'convert_test' iv_value = 'true' ) )
      ) ).

    ao_s3c_acts->get_job_tagging(
      iv_account_id = gv_account_id
      iv_job_id     = gv_shared_job_id ).

    " Validate directly that the expected tag is present
    DATA(lo_tags) = ao_s3c->getjobtagging(
      iv_accountid = gv_account_id iv_jobid = gv_shared_job_id ).
    DATA(lt_tags) = lo_tags->get_tags( ).
    cl_abap_unit_assert=>assert_true(
      act  = xsdbool( lines( lt_tags ) >= 1 )
      msg  = 'get_job_tagging: at least 1 tag must be present on the shared job' ).

    DATA lv_found TYPE abap_bool.
    LOOP AT lt_tags INTO DATA(lo_tag).
      IF lo_tag->get_key( ) = 'convert_test'.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = 'Tag convert_test must be present after put + get_job_tagging' ).
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
  METHOD delete_job_tagging.
* ─────────────────────────────────────────────────────────────────────────────
    " Uses a dedicated fresh job so deletion does not interfere with other tests.
    DATA(lv_job_id) = create_fresh_job( ).
    wait_for_job( iv_job_id = lv_job_id iv_desired_status = 'Suspended' ).

    " First put tags on the job
    ao_s3c->putjobtagging(
      iv_accountid = gv_account_id
      iv_jobid     = lv_job_id
      it_tags      = VALUE /aws1/cl_s3cs3tag=>tt_s3tagset(
        ( NEW /aws1/cl_s3cs3tag( iv_key = 'ToDelete' iv_value = 'yes' ) )
      ) ).

    " Confirm the tag is there before deleting
    DATA(lo_before) = ao_s3c->getjobtagging(
      iv_accountid = gv_account_id iv_jobid = lv_job_id ).
    cl_abap_unit_assert=>assert_true(
      act  = xsdbool( lines( lo_before->get_tags( ) ) >= 1 )
      msg  = 'delete_job_tagging: tag must exist before deletion' ).

    ao_s3c_acts->delete_job_tagging(
      iv_account_id = gv_account_id
      iv_job_id     = lv_job_id ).

    " Verify all tags are gone
    DATA(lo_after) = ao_s3c->getjobtagging(
      iv_accountid = gv_account_id iv_jobid = lv_job_id ).
    cl_abap_unit_assert=>assert_equals(
      exp = 0
      act = lines( lo_after->get_tags( ) )
      msg = 'delete_job_tagging must remove all tags' ).

    " Cancel the dedicated job
    TRY.
        ao_s3c->updatejobstatus(
          iv_accountid          = gv_account_id
          iv_jobid              = lv_job_id
          iv_requestedjobstatus = 'Cancelled' ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
  METHOD list_jobs.
* ─────────────────────────────────────────────────────────────────────────────
    " Calls the actions class method then verifies the shared job appears in the
    " result returned by a direct SDK call.
    ao_s3c_acts->list_jobs( iv_account_id = gv_account_id ).

    " Now verify independently via the SDK
    DATA(lo_result) = ao_s3c->listjobs(
      iv_accountid   = gv_account_id
      it_jobstatuses = VALUE /aws1/cl_s3cjobstatuslist_w=>tt_jobstatuslist(
        ( NEW /aws1/cl_s3cjobstatuslist_w( 'Active'    ) )
        ( NEW /aws1/cl_s3cjobstatuslist_w( 'Cancelled' ) )
        ( NEW /aws1/cl_s3cjobstatuslist_w( 'Complete'  ) )
        ( NEW /aws1/cl_s3cjobstatuslist_w( 'Failed'    ) )
        ( NEW /aws1/cl_s3cjobstatuslist_w( 'New'       ) )
        ( NEW /aws1/cl_s3cjobstatuslist_w( 'Paused'    ) )
        ( NEW /aws1/cl_s3cjobstatuslist_w( 'Pausing'   ) )
        ( NEW /aws1/cl_s3cjobstatuslist_w( 'Preparing' ) )
        ( NEW /aws1/cl_s3cjobstatuslist_w( 'Ready'     ) )
        ( NEW /aws1/cl_s3cjobstatuslist_w( 'Suspended' ) )
      ) ).

    " list_jobs returns at most 1 000 results; the shared job was created in
    " this test run so it must appear.
    DATA lv_found TYPE abap_bool.
    LOOP AT lo_result->get_jobs( ) INTO DATA(lo_job).
      IF lo_job->get_jobid( ) = gv_shared_job_id.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = 'list_jobs: the shared test job must appear in the result' ).
  ENDMETHOD.

ENDCLASS.
