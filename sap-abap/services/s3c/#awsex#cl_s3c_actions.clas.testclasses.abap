" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_s3c_actions DEFINITION DEFERRED.
CLASS /awsex/cl_s3c_actions DEFINITION LOCAL FRIENDS ltc_s3c_actions.

CLASS ltc_s3c_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " Service clients and session
    CLASS-DATA ao_session     TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_s3c         TYPE REF TO /aws1/if_s3c.
    CLASS-DATA ao_s3          TYPE REF TO /aws1/if_s3.
    CLASS-DATA ao_iam         TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_s3c_actions TYPE REF TO /awsex/cl_s3c_actions.

    " Account / region
    CLASS-DATA av_account_id  TYPE /aws1/s3caccountid.

    " S3 bucket used for manifests and reports
    CLASS-DATA av_bucket_name TYPE /aws1/s3_bucketname.
    CLASS-DATA av_bucket_arn  TYPE /aws1/s3cs3bucketarnstring.

    " IAM role used by every batch job in the suite
    CLASS-DATA av_role_arn    TYPE /aws1/s3ciamrolearn.
    CLASS-DATA av_role_name   TYPE /aws1/iamrolenametype.

    " ETag of the manifest object
    CLASS-DATA av_manifest_etag TYPE /aws1/s3cnonemptymaxlength1000.

    " Pre-created batch jobs
    "   av_ro_job_id     – used by read-only tests: describe_job, list_jobs
    "   av_prio_job_id   – used exclusively by update_job_priority
    "   av_cancel_job_id – used exclusively by update_job_status (cancel)
    "   av_get_tag_job_id  – used by get_job_tagging  (pre-tagged in setup)
    "   av_put_tag_job_id  – used by put_job_tagging  (starts untagged)
    "   av_del_tag_job_id  – used by delete_job_tagging (pre-tagged in setup)
    CLASS-DATA av_ro_job_id      TYPE /aws1/s3cjobid.
    CLASS-DATA av_prio_job_id    TYPE /aws1/s3cjobid.
    CLASS-DATA av_cancel_job_id  TYPE /aws1/s3cjobid.
    CLASS-DATA av_get_tag_job_id TYPE /aws1/s3cjobid.
    CLASS-DATA av_put_tag_job_id TYPE /aws1/s3cjobid.
    CLASS-DATA av_del_tag_job_id TYPE /aws1/s3cjobid.

    CLASS-METHODS class_setup
      RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_teardown
      RAISING /aws1/cx_rt_generic.

    " Internal helper: create one S3 Batch job and return its ID.
    " All jobs are created with ConfirmationRequired = TRUE so they land in
    " the Suspended state, making them safe to cancel and re-tag freely.
    CLASS-METHODS create_test_job
      RETURNING VALUE(ov_job_id) TYPE /aws1/s3cjobid
      RAISING   /aws1/cx_rt_generic.

    " Internal helper: cancel a job if it is in a cancellable state.
    CLASS-METHODS try_cancel_job
      IMPORTING iv_job_id TYPE /aws1/s3cjobid.

    METHODS create_job          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_job_priority FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_job_status   FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS describe_job        FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS get_job_tagging     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS put_job_tagging     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_jobs           FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_job_tagging  FOR TESTING RAISING /aws1/cx_rt_generic.

ENDCLASS.


CLASS ltc_s3c_actions IMPLEMENTATION.

  METHOD class_setup.
    DATA lv_uuid       TYPE string.
    DATA lv_body       TYPE xstring.
    DATA lv_body_str   TYPE string.
    DATA lv_manifest   TYPE string.
    DATA lt_fields     TYPE /aws1/cl_s3cjobmanifestfield00=>tt_jobmanifestfieldlist.
    DATA lt_tagset     TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.

    ao_session     = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_s3c         = /aws1/cl_s3c_factory=>create( ao_session ).
    ao_s3          = /aws1/cl_s3_factory=>create( ao_session ).
    ao_iam         = /aws1/cl_iam_factory=>create( ao_session ).
    ao_s3c_actions = NEW /awsex/cl_s3c_actions( ).

    av_account_id = ao_session->get_account_id( ).

    " ----------------------------------------------------------------
    " 1. Create S3 bucket (unique per account) using the utility helper
    " ----------------------------------------------------------------
    lv_uuid = /awsex/cl_utils=>get_random_string( ).
    CONDENSE lv_uuid NO-GAPS.
    av_bucket_name = |sap-s3c-{ lv_uuid(10) }|.
    TRANSLATE av_bucket_name TO LOWER CASE.
    av_bucket_arn  = |arn:aws:s3:::{ av_bucket_name }|.

    " /awsex/cl_utils=>create_bucket handles the us-east-1 constraint
    /awsex/cl_utils=>create_bucket(
      iv_bucket  = av_bucket_name
      io_s3      = ao_s3
      io_session = ao_session ).

    " Tag the bucket with convert_test
    DATA lt_s3_tags TYPE /aws1/cl_s3_tag=>tt_tagset.
    APPEND NEW /aws1/cl_s3_tag( iv_key = 'convert_test' iv_value = 'true' ) TO lt_s3_tags.
    ao_s3->putbuckettagging(
      iv_bucket  = av_bucket_name
      io_tagging = NEW /aws1/cl_s3_tagging( it_tagset = lt_s3_tags ) ).

    " ----------------------------------------------------------------
    " 2. Upload two sample objects and the manifest CSV
    " ----------------------------------------------------------------
    DO 2 TIMES.
      DATA(lv_key) = |sample-object-{ sy-index }.txt|.
      lv_body_str  = |Content for { lv_key }|.
      lv_body      = cl_abap_codepage=>convert_to( lv_body_str ).
      ao_s3->putobject(
        iv_bucket = av_bucket_name
        iv_key    = lv_key
        iv_body   = lv_body ).
    ENDDO.

    lv_manifest = |{ av_bucket_name },sample-object-1.txt\n| &&
                  |{ av_bucket_name },sample-object-2.txt\n|.
    DATA lv_mfst_body TYPE xstring.
    lv_mfst_body = cl_abap_codepage=>convert_to( lv_manifest ).
    ao_s3->putobject(
      iv_bucket = av_bucket_name
      iv_key    = 'job-manifest.csv'
      iv_body   = lv_mfst_body ).

    " Retrieve and strip the manifest ETag
    DATA(lo_head) = ao_s3->headobject(
      iv_bucket = av_bucket_name
      iv_key    = 'job-manifest.csv' ).
    av_manifest_etag = lo_head->get_etag( ).
    REPLACE ALL OCCURRENCES OF '"' IN av_manifest_etag WITH ''.

    " ----------------------------------------------------------------
    " 3. Create the IAM execution role for S3 Batch Operations
    " ----------------------------------------------------------------
    lv_uuid = /awsex/cl_utils=>get_random_string( ).
    CONDENSE lv_uuid NO-GAPS.
    av_role_name = |sap-s3c-role-{ lv_uuid(10) }|.

    DATA lv_trust TYPE /aws1/iampolicydocumenttype.
    lv_trust =
      `{"Version":"2012-10-17","Statement":[{"Effect":"Allow",` &&
      `"Principal":{"Service":"batchoperations.s3.amazonaws.com"},` &&
      `"Action":"sts:AssumeRole"}]}`.

    DATA(lo_role_res) = ao_iam->createrole(
      iv_rolename                 = av_role_name
      iv_assumerolepolicydocument = lv_trust
      iv_description              = 'SAP ABAP s3c test role - convert_test'
      it_tags                     = VALUE /aws1/cl_iamtag=>tt_taglisttype(
        ( NEW /aws1/cl_iamtag( iv_key = 'convert_test' iv_value = 'true' ) )
      )
    ).
    av_role_arn = lo_role_res->get_role( )->get_arn( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = av_role_arn
      msg = 'IAM role ARN must not be empty after creation' ).

    " Attach an inline policy granting the role all required S3 permissions:
    "   • s3:GetObject / s3:GetObjectVersion on source objects
    "   • s3:PutObjectTagging / s3:GetObjectTagging on source objects
    "   • s3:PutObject on the report bucket prefix
    "   • s3:GetBucketLocation on both buckets
    DATA lv_policy TYPE /aws1/iampolicydocumenttype.
    lv_policy =
      `{"Version":"2012-10-17","Statement":[` &&
      `{"Sid":"SourceObjects","Effect":"Allow",` &&
      `"Action":["s3:GetObject","s3:GetObjectVersion",` &&
      `"s3:PutObjectTagging","s3:GetObjectTagging"],` &&
      `"Resource":"arn:aws:s3:::` && av_bucket_name && `/*"},` &&
      `{"Sid":"ReportBucket","Effect":"Allow",` &&
      `"Action":["s3:PutObject"],` &&
      `"Resource":"arn:aws:s3:::` && av_bucket_name && `/batch-op-reports/*"},` &&
      `{"Sid":"BucketLocation","Effect":"Allow",` &&
      `"Action":["s3:GetBucketLocation"],` &&
      `"Resource":"arn:aws:s3:::` && av_bucket_name && `"}]}`.

    ao_iam->putrolepolicy(
      iv_rolename       = av_role_name
      iv_policyname     = 's3batch-exec-policy'
      iv_policydocument = lv_policy ).

    " IAM propagation delay – required before using the role in batch jobs
    WAIT UP TO 15 SECONDS.

    " ----------------------------------------------------------------
    " 4. Create the six dedicated test jobs
    " ----------------------------------------------------------------
    " Jobs land in Suspended (ConfirmationRequired=true) so each test
    " can act on them without timing races.

    av_ro_job_id = create_test_job( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_ro_job_id
      msg = 'Could not create read-only test job (ro_job_id)' ).

    av_prio_job_id = create_test_job( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_prio_job_id
      msg = 'Could not create priority test job (prio_job_id)' ).

    av_cancel_job_id = create_test_job( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_cancel_job_id
      msg = 'Could not create cancel test job (cancel_job_id)' ).

    av_get_tag_job_id = create_test_job( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_get_tag_job_id
      msg = 'Could not create get-tagging test job (get_tag_job_id)' ).

    av_put_tag_job_id = create_test_job( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_put_tag_job_id
      msg = 'Could not create put-tagging test job (put_tag_job_id)' ).

    av_del_tag_job_id = create_test_job( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_del_tag_job_id
      msg = 'Could not create delete-tagging test job (del_tag_job_id)' ).

    " Pre-tag av_get_tag_job_id so get_job_tagging has something to read
    ao_s3c->putjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_get_tag_job_id
      it_tags      = VALUE /aws1/cl_s3cs3tag=>tt_s3tagset(
        ( NEW /aws1/cl_s3cs3tag( iv_key = 'SetupKey' iv_value = 'SetupValue' ) )
      )
    ).

    " Pre-tag av_del_tag_job_id so delete_job_tagging has something to remove
    ao_s3c->putjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_del_tag_job_id
      it_tags      = VALUE /aws1/cl_s3cs3tag=>tt_s3tagset(
        ( NEW /aws1/cl_s3cs3tag( iv_key = 'ToDelete' iv_value = 'yes' ) )
      )
    ).
  ENDMETHOD.


  METHOD class_teardown.
    " Cancel every pre-created job that is still in a cancellable state.
    DATA lt_ids TYPE STANDARD TABLE OF /aws1/s3cjobid WITH DEFAULT KEY.
    APPEND av_ro_job_id      TO lt_ids.
    APPEND av_prio_job_id    TO lt_ids.
    APPEND av_cancel_job_id  TO lt_ids.
    APPEND av_get_tag_job_id TO lt_ids.
    APPEND av_put_tag_job_id TO lt_ids.
    APPEND av_del_tag_job_id TO lt_ids.

    LOOP AT lt_ids ASSIGNING FIELD-SYMBOL(<lv_id>).
      IF <lv_id> IS NOT INITIAL.
        try_cancel_job( <lv_id> ).
      ENDIF.
    ENDLOOP.

    " Delete the S3 bucket (objects + bucket) using the utility helper.
    " The helper handles non-empty buckets.
    TRY.
        /awsex/cl_utils=>cleanup_bucket( io_s3 = ao_s3 iv_bucket = av_bucket_name ).
      CATCH /aws1/cx_rt_generic.
        " Best-effort; bucket is tagged convert_test for manual follow-up.
    ENDTRY.

    " Delete the IAM role inline policy, then the role itself.
    TRY.
        ao_iam->deleterolepolicy(
          iv_rolename   = av_role_name
          iv_policyname = 's3batch-exec-policy' ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iam->deleterole( iv_rolename = av_role_name ).
      CATCH /aws1/cx_rt_generic.
        " Role is tagged convert_test for manual cleanup if deletion fails.
    ENDTRY.
  ENDMETHOD.


  METHOD create_test_job.
    DATA lv_manifest_arn TYPE /aws1/s3cs3keyarnstring.
    lv_manifest_arn = |arn:aws:s3:::{ av_bucket_name }/job-manifest.csv|.

    DATA lt_tagset TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag( iv_key = 'BatchTag' iv_value = 'BatchValue' ) TO lt_tagset.

    DATA lt_fields TYPE /aws1/cl_s3cjobmanifestfield00=>tt_jobmanifestfieldlist.
    APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Bucket' ) TO lt_fields.
    APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Key' )    TO lt_fields.

    DATA(lo_result) = ao_s3c->createjob(
      iv_accountid            = av_account_id
      iv_rolearn              = av_role_arn
      iv_priority             = 10
      iv_confirmationrequired = abap_true   " → lands in Suspended; safe to cancel
      iv_description          = 'SAP ABAP s3c test - convert_test'
      io_operation            = NEW /aws1/cl_s3cjoboperation(
        io_s3putobjecttagging = NEW /aws1/cl_s3cs3setobjecttagop(
          it_tagset = lt_tagset ) )
      io_manifest             = NEW /aws1/cl_s3cjobmanifest(
        io_spec     = NEW /aws1/cl_s3cjobmanifestspec(
          iv_format = 'S3BatchOperations_CSV_20180820'
          it_fields = lt_fields )
        io_location = NEW /aws1/cl_s3cjobmanifestloc(
          iv_objectarn = lv_manifest_arn
          iv_etag      = av_manifest_etag ) )
      io_report               = NEW /aws1/cl_s3cjobreport(
        iv_bucket      = av_bucket_arn
        iv_format      = 'Report_CSV_20180820'
        iv_enabled     = abap_true
        iv_prefix      = 'batch-op-reports'
        iv_reportscope = 'AllTasks' )
    ).
    ov_job_id = lo_result->get_jobid( ).
  ENDMETHOD.


  METHOD try_cancel_job.
    " Cancel iv_job_id if the job is still in a cancellable state.
    " Silently ignores all errors – intended for teardown only.
    TRY.
        DATA(lo_desc) = ao_s3c->describejob(
          iv_accountid = av_account_id
          iv_jobid     = iv_job_id ).
        DATA(lv_st) = lo_desc->get_job( )->get_status( ).
        IF lv_st = 'New'       OR lv_st = 'Preparing' OR
           lv_st = 'Suspended' OR lv_st = 'Ready'.
          ao_s3c->updatejobstatus(
            iv_accountid          = av_account_id
            iv_jobid              = iv_job_id
            iv_requestedjobstatus = 'Cancelled' ).
        ENDIF.
      CATCH /aws1/cx_rt_generic.
        " Best-effort; ignore all errors.
    ENDTRY.
  ENDMETHOD.


  " ──────────────────────────────────────────────────────────────────
  " TEST METHODS
  " ──────────────────────────────────────────────────────────────────

  METHOD create_job.
    " Tests the create_job action method by calling it with fresh
    " infrastructure, then verifying the returned job ID is real.
    DATA lv_manifest_arn TYPE /aws1/s3cs3keyarnstring.
    lv_manifest_arn = |arn:aws:s3:::{ av_bucket_name }/job-manifest.csv|.

    DATA(lv_new_job_id) = ao_s3c_actions->create_job(
      iv_account_id    = av_account_id
      iv_role_arn      = av_role_arn
      iv_manifest_arn  = lv_manifest_arn
      iv_manifest_etag = av_manifest_etag
      iv_report_bucket = av_bucket_arn ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_new_job_id
      msg = 'create_job must return a non-empty job ID' ).

    " Verify the job actually exists by describing it
    DATA(lo_desc) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = lv_new_job_id ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_desc->get_job( )
      msg = |Newly created job { lv_new_job_id } could not be described| ).
    cl_abap_unit_assert=>assert_equals(
      exp = lv_new_job_id
      act = lo_desc->get_job( )->get_jobid( )
      msg = 'Described job ID must match the ID returned by create_job' ).

    " Cleanup: cancel the job created by the action method
    try_cancel_job( lv_new_job_id ).
  ENDMETHOD.


  METHOD update_job_priority.
    " Tests the update_job_priority action method.
    " Uses av_prio_job_id which is in Suspended state (safe to update).
    ao_s3c_actions->update_job_priority(
      iv_account_id = av_account_id
      iv_job_id     = av_prio_job_id ).

    " Verify the priority was actually changed to 60
    DATA(lo_desc) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = av_prio_job_id ).
    cl_abap_unit_assert=>assert_equals(
      exp = 60
      act = lo_desc->get_job( )->get_priority( )
      msg = |Job { av_prio_job_id } priority must be 60 after update_job_priority| ).
  ENDMETHOD.


  METHOD update_job_status.
    " Tests the update_job_status action method (cancels a job).
    " Uses av_cancel_job_id which is in Suspended state.

    " Precondition: job must be in Suspended state
    DATA(lo_pre) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = av_cancel_job_id ).
    DATA(lv_pre_status) = lo_pre->get_job( )->get_status( ).
    cl_abap_unit_assert=>assert_equals(
      exp = 'Suspended'
      act = lv_pre_status
      msg = |Job { av_cancel_job_id } must be Suspended before cancel test| ).

    ao_s3c_actions->update_job_status(
      iv_account_id = av_account_id
      iv_job_id     = av_cancel_job_id ).

    " Poll until the job reaches Cancelled (max ~60 s)
    DATA lv_cancelled TYPE abap_bool VALUE abap_false.
    DO 12 TIMES.
      DATA(lo_poll) = ao_s3c->describejob(
        iv_accountid = av_account_id
        iv_jobid     = av_cancel_job_id ).
      IF lo_poll->get_job( )->get_status( ) = 'Cancelled'.
        lv_cancelled = abap_true.
        EXIT.
      ENDIF.
      WAIT UP TO 5 SECONDS.
    ENDDO.
    cl_abap_unit_assert=>assert_true(
      act = lv_cancelled
      msg = |Job { av_cancel_job_id } did not reach Cancelled status| ).
  ENDMETHOD.


  METHOD describe_job.
    " Tests the describe_job action method.
    ao_s3c_actions->describe_job(
      iv_account_id = av_account_id
      iv_job_id     = av_ro_job_id ).

    " Independently verify the job is reachable and carries the correct ID
    DATA(lo_result) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = av_ro_job_id ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_result->get_job( )
      msg = |describe_job: job descriptor for { av_ro_job_id } must be bound| ).
    cl_abap_unit_assert=>assert_equals(
      exp = av_ro_job_id
      act = lo_result->get_job( )->get_jobid( )
      msg = 'Described job ID must match av_ro_job_id' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_job( )->get_status( )
      msg = 'Described job status must not be empty' ).
  ENDMETHOD.


  METHOD get_job_tagging.
    " Tests the get_job_tagging action method.
    " av_get_tag_job_id was pre-tagged in class_setup with SetupKey=SetupValue.
    ao_s3c_actions->get_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_get_tag_job_id ).

    " Independently verify the tag is still present
    DATA(lo_result) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_get_tag_job_id ).
    DATA(lt_tags) = lo_result->get_tags( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_tags
      msg = |get_job_tagging: job { av_get_tag_job_id } must have at least one tag| ).

    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_tags INTO DATA(lo_tag).
      IF lo_tag->get_key( ) = 'SetupKey'.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = 'Tag SetupKey must be present on the get-tagging test job' ).
  ENDMETHOD.


  METHOD put_job_tagging.
    " Tests the put_job_tagging action method.
    " av_put_tag_job_id starts completely untagged.

    " Precondition: the job must have no tags yet
    DATA(lo_pre) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_put_tag_job_id ).
    cl_abap_unit_assert=>assert_initial(
      act = lo_pre->get_tags( )
      msg = |put_job_tagging: job { av_put_tag_job_id } must start untagged| ).

    ao_s3c_actions->put_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_put_tag_job_id ).

    " Verify the tags were applied
    DATA(lo_result) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_put_tag_job_id ).
    DATA(lt_tags) = lo_result->get_tags( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_tags
      msg = |put_job_tagging: job { av_put_tag_job_id } must have tags after the call| ).

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
      msg = 'Tag Environment must be set by put_job_tagging' ).
    cl_abap_unit_assert=>assert_true(
      act = lv_found_team
      msg = 'Tag Team must be set by put_job_tagging' ).
  ENDMETHOD.


  METHOD list_jobs.
    " Tests the list_jobs action method.
    ao_s3c_actions->list_jobs( iv_account_id = av_account_id ).

    " Independently verify via the SDK that at least av_ro_job_id is listed
    DATA lt_statuses TYPE /aws1/cl_s3cjobstatuslist_w=>tt_jobstatuslist.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'New' )       TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Preparing' ) TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Suspended' ) TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Ready' )     TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Active' )    TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Complete' )  TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Cancelled' ) TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Failed' )    TO lt_statuses.

    DATA(lo_result) = ao_s3c->listjobs(
      iv_accountid   = av_account_id
      it_jobstatuses = lt_statuses ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_jobs: result must be bound' ).

    " The read-only test job created in setup must appear in the list
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_result->get_jobs( ) INTO DATA(lo_job).
      IF lo_job->get_jobid( ) = av_ro_job_id.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_jobs: job { av_ro_job_id } must appear in the listing| ).
  ENDMETHOD.


  METHOD delete_job_tagging.
    " Tests the delete_job_tagging action method.
    " av_del_tag_job_id was pre-tagged in class_setup with ToDelete=yes.

    " Precondition: the job must have at least one tag
    DATA(lo_pre) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_del_tag_job_id ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_pre->get_tags( )
      msg = |delete_job_tagging: job { av_del_tag_job_id } must be pre-tagged| ).

    ao_s3c_actions->delete_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_del_tag_job_id ).

    " Verify all tags were removed
    DATA(lo_result) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_del_tag_job_id ).
    cl_abap_unit_assert=>assert_initial(
      act = lo_result->get_tags( )
      msg = |delete_job_tagging: job { av_del_tag_job_id } must have no tags after deletion| ).
  ENDMETHOD.

ENDCLASS.
