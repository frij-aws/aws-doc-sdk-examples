" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_s3c_actions DEFINITION DEFERRED.
CLASS /awsex/cl_s3c_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_s3c_actions.

CLASS ltc_awsex_cl_s3c_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    CLASS-DATA ao_s3c         TYPE REF TO /aws1/if_s3c.
    CLASS-DATA ao_s3          TYPE REF TO /aws1/if_s3.
    CLASS-DATA ao_iam         TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_session     TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_s3c_actions  TYPE REF TO /awsex/cl_s3c_actions.

    " Stable shared infrastructure created in class_setup
    CLASS-DATA av_account_id    TYPE /aws1/s3caccountid.
    CLASS-DATA av_bucket_name   TYPE /aws1/s3_bucketname.
    CLASS-DATA av_manifest_arn  TYPE /aws1/s3cs3keyarnstring.
    CLASS-DATA av_manifest_etag TYPE /aws1/s3cnonemptymaxlength1024st.
    CLASS-DATA av_report_bucket TYPE /aws1/s3cs3bucketarnstring.
    CLASS-DATA av_role_arn      TYPE /aws1/s3ciamrolearn.
    CLASS-DATA av_role_name     TYPE /aws1/iamrolename.

    " One dedicated job per test method that performs a mutation
    CLASS-DATA av_job_id_create      TYPE /aws1/s3cjobid.   " used by create_job test
    CLASS-DATA av_job_id_priority    TYPE /aws1/s3cjobid.   " used by update_job_priority
    CLASS-DATA av_job_id_cancel      TYPE /aws1/s3cjobid.   " used by update_job_status
    CLASS-DATA av_job_id_describe    TYPE /aws1/s3cjobid.   " used by describe_job
    CLASS-DATA av_job_id_get_tag     TYPE /aws1/s3cjobid.   " used by get_job_tagging
    CLASS-DATA av_job_id_put_tag     TYPE /aws1/s3cjobid.   " used by put_job_tagging
    CLASS-DATA av_job_id_del_tag     TYPE /aws1/s3cjobid.   " used by delete_job_tagging
    CLASS-DATA av_job_id_list        TYPE /aws1/s3cjobid.   " used by list_jobs

    METHODS: create_job FOR TESTING RAISING /aws1/cx_rt_generic,
      update_job_priority FOR TESTING RAISING /aws1/cx_rt_generic,
      update_job_status FOR TESTING RAISING /aws1/cx_rt_generic,
      describe_job FOR TESTING RAISING /aws1/cx_rt_generic,
      get_job_tagging FOR TESTING RAISING /aws1/cx_rt_generic,
      put_job_tagging FOR TESTING RAISING /aws1/cx_rt_generic,
      list_jobs FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_job_tagging FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup
      RAISING /aws1/cx_rt_generic /awsex/cx_generic.
    CLASS-METHODS class_teardown
      RAISING /aws1/cx_rt_generic /awsex/cx_generic.

    " Create a fresh S3 Batch Operations job; FAIL the test if unsuccessful.
    CLASS-METHODS create_test_job
      RETURNING VALUE(rv_job_id) TYPE /aws1/s3cjobid
      RAISING   /aws1/cx_rt_generic.

    " Poll until a job reaches a terminal/stable status or the max iterations.
    " Acceptable stable statuses: Suspended, Ready, Active, Cancelled, Failed, Complete.
    " Fails the test if the job is still Preparing/New after 5 minutes.
    CLASS-METHODS wait_for_stable_status
      IMPORTING iv_job_id TYPE /aws1/s3cjobid
      RAISING   /aws1/cx_rt_generic.

    " Attempt to cancel a job; swallow all exceptions (used only in teardown).
    CLASS-METHODS cancel_job_safe
      IMPORTING iv_job_id TYPE /aws1/s3cjobid.

ENDCLASS.



CLASS ltc_awsex_cl_s3c_actions IMPLEMENTATION.

  METHOD class_setup.
    "--------------------------------------------------------------------
    " Initialise SDK clients
    "--------------------------------------------------------------------
    ao_session     = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_s3c         = /aws1/cl_s3c_factory=>create( ao_session ).
    ao_s3          = /aws1/cl_s3_factory=>create( ao_session ).
    ao_iam         = /aws1/cl_iam_factory=>create( ao_session ).
    ao_s3c_actions  = NEW /awsex/cl_s3c_actions( ).

    " Derive the AWS account ID from the session (no STS call required)
    av_account_id = ao_session->get_account_id( ).

    "--------------------------------------------------------------------
    " Build unique, reproducible resource names
    "--------------------------------------------------------------------
    DATA(lv_rand) = /awsex/cl_utils=>get_random_string( ).
    CONDENSE lv_rand NO-GAPS.
    " Bucket names must be ≤63 chars and lowercase
    av_bucket_name  = |s3c-batch-{ lv_rand(10) }|.
    av_role_name    = |s3c-batch-role-{ lv_rand(10) }|.
    av_report_bucket = |arn:aws:s3:::{ av_bucket_name }|.

    "--------------------------------------------------------------------
    " 1) Create the S3 bucket that holds the test objects, the manifest,
    "    and the batch-job reports
    "--------------------------------------------------------------------
    /awsex/cl_utils=>create_bucket(
      iv_bucket  = av_bucket_name
      io_s3      = ao_s3
      io_session = ao_session ).

    " Tag the bucket with convert_test
    ao_s3->putbuckettagging(
      iv_bucket  = av_bucket_name
      io_tagging = NEW /aws1/cl_s3_tagging(
        it_tagset = VALUE /aws1/cl_s3_tag=>tt_tagset(
          ( NEW /aws1/cl_s3_tag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ) ).

    "--------------------------------------------------------------------
    " 2) Upload three small test objects
    "--------------------------------------------------------------------
    DATA lt_keys TYPE STANDARD TABLE OF /aws1/s3_objectkey.
    APPEND 'test-obj-1.txt' TO lt_keys.
    APPEND 'test-obj-2.txt' TO lt_keys.
    APPEND 'test-obj-3.txt' TO lt_keys.

    DATA lv_body TYPE xstring.
    lv_body = cl_abap_codepage=>convert_to( 'test content for s3 batch' ).

    LOOP AT lt_keys INTO DATA(lv_key).
      ao_s3->putobject(
        iv_bucket = av_bucket_name
        iv_key    = lv_key
        iv_body   = lv_body ).
    ENDLOOP.

    "--------------------------------------------------------------------
    " 3) Build and upload the manifest CSV
    "--------------------------------------------------------------------
    DATA lv_csv TYPE string.
    lv_csv = |{ av_bucket_name },test-obj-1.txt\n| &&
             |{ av_bucket_name },test-obj-2.txt\n| &&
             |{ av_bucket_name },test-obj-3.txt\n|.

    ao_s3->putobject(
      iv_bucket = av_bucket_name
      iv_key    = 'job-manifest.csv'
      iv_body   = cl_abap_codepage=>convert_to( lv_csv ) ).

    " Retrieve the ETag of the manifest (required by CreateJob)
    DATA(lo_head) = ao_s3->headobject(
      iv_bucket = av_bucket_name
      iv_key    = 'job-manifest.csv' ).

    av_manifest_etag = lo_head->get_etag( ).
    " Strip surrounding double-quotes that S3 returns
    REPLACE ALL OCCURRENCES OF '"' IN av_manifest_etag WITH ''.

    " Bucket is in the same account, so no versioning needed – use plain ARN
    av_manifest_arn = |arn:aws:s3:::{ av_bucket_name }/job-manifest.csv|.

    cl_abap_unit_assert=>assert_not_initial(
      act = av_manifest_etag
      msg = 'Manifest ETag must not be empty after upload' ).

    "--------------------------------------------------------------------
    " 4) Create the IAM role that S3 Batch Operations will assume
    "--------------------------------------------------------------------
    DATA lv_trust TYPE string.
    lv_trust = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",' &&
               '"Principal":{"Service":"batchoperations.s3.amazonaws.com"},' &&
               '"Action":"sts:AssumeRole"}]}'.

    TRY.
        DATA(lo_role) = ao_iam->createrole(
          iv_rolename                 = av_role_name
          iv_assumerolepolicydocument = lv_trust
          iv_description              = 'SAP ABAP s3c test role'
          it_tags = VALUE /aws1/cl_iam_tag=>tt_taglisttype(
            ( NEW /aws1/cl_iam_tag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).
        av_role_arn = lo_role->get_role( )->get_arn( ).
      CATCH /aws1/cx_iam_entityalreadyexists.
        " Role was left over from a previous run – reuse it
        av_role_arn = ao_iam->getrole( iv_rolename = av_role_name
          )->get_role( )->get_arn( ).
    ENDTRY.

    cl_abap_unit_assert=>assert_not_initial(
      act = av_role_arn
      msg = 'IAM role ARN must not be empty' ).

    "--------------------------------------------------------------------
    " 5) Attach a comprehensive inline policy to the role
    "    S3 Batch Operations requires ALL of the following:
    "      – Read the manifest object
    "      – Perform the requested operation (PutObjectTagging) on objects
    "      – Write the job completion report to the same bucket
    "--------------------------------------------------------------------
    DATA lv_bucket_arn   TYPE string.
    DATA lv_bucket_arn_w TYPE string.
    lv_bucket_arn   = |arn:aws:s3:::{ av_bucket_name }|.
    lv_bucket_arn_w = |arn:aws:s3:::{ av_bucket_name }/*|.

    DATA lv_policy TYPE string.
    lv_policy =
      '{' &&
      '"Version":"2012-10-17",' &&
      '"Statement":[' &&
        '{"Sid":"ManifestRead",' &&
         '"Effect":"Allow",' &&
         '"Action":["s3:GetObject","s3:GetObjectVersion"],' &&
         '"Resource":"' && lv_bucket_arn_w && '"},' &&
        '{"Sid":"BucketLocation",' &&
         '"Effect":"Allow",' &&
         '"Action":["s3:GetBucketLocation"],' &&
         '"Resource":"' && lv_bucket_arn && '"},' &&
        '{"Sid":"ObjectOperations",' &&
         '"Effect":"Allow",' &&
         '"Action":["s3:PutObjectTagging","s3:GetObjectAcl","s3:GetObjectVersionAcl"],' &&
         '"Resource":"' && lv_bucket_arn_w && '"},' &&
        '{"Sid":"ReportWrite",' &&
         '"Effect":"Allow",' &&
         '"Action":["s3:PutObject","s3:GetBucketAcl"],' &&
         '"Resource":["' && lv_bucket_arn && '","' && lv_bucket_arn_w && '"]}' &&
      ']}' .

    ao_iam->putrolepolicy(
      iv_rolename       = av_role_name
      iv_policyname     = 'S3BatchOpsPolicy'
      iv_policydocument = lv_policy ).

    " IAM is eventually consistent – wait for the role and policy to propagate
    WAIT UP TO 15 SECONDS.

    "--------------------------------------------------------------------
    " 6) Pre-create one job per test method that performs a mutation.
    "    create_job test creates its own job; all others reuse a pre-built one.
    "--------------------------------------------------------------------
    av_job_id_priority = create_test_job( ).
    av_job_id_cancel   = create_test_job( ).
    av_job_id_describe = create_test_job( ).
    av_job_id_get_tag  = create_test_job( ).
    av_job_id_put_tag  = create_test_job( ).
    av_job_id_del_tag  = create_test_job( ).
    av_job_id_list     = create_test_job( ).

    " Wait until every pre-created job reaches a stable status
    wait_for_stable_status( av_job_id_priority ).
    wait_for_stable_status( av_job_id_cancel   ).
    wait_for_stable_status( av_job_id_describe ).
    wait_for_stable_status( av_job_id_get_tag  ).
    wait_for_stable_status( av_job_id_put_tag  ).
    wait_for_stable_status( av_job_id_del_tag  ).
    wait_for_stable_status( av_job_id_list     ).

    " Pre-tag the jobs that need tags before their test runs
    DATA lt_init_tags TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag( iv_key = 'InitialTag' iv_value = 'InitialValue' )
      TO lt_init_tags.

    ao_s3c->putjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_get_tag
      it_tags      = lt_init_tags ).

    ao_s3c->putjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_del_tag
      it_tags      = lt_init_tags ).

  ENDMETHOD.


  METHOD class_teardown.
    "--------------------------------------------------------------------
    " Cancel all pre-created jobs (best effort – swallow errors)
    "--------------------------------------------------------------------
    DATA lt_jobs TYPE STANDARD TABLE OF /aws1/s3cjobid.
    APPEND av_job_id_create   TO lt_jobs.
    APPEND av_job_id_priority TO lt_jobs.
    APPEND av_job_id_cancel   TO lt_jobs.
    APPEND av_job_id_describe TO lt_jobs.
    APPEND av_job_id_get_tag  TO lt_jobs.
    APPEND av_job_id_put_tag  TO lt_jobs.
    APPEND av_job_id_del_tag  TO lt_jobs.
    APPEND av_job_id_list     TO lt_jobs.

    LOOP AT lt_jobs INTO DATA(lv_id).
      IF lv_id IS NOT INITIAL.
        cancel_job_safe( lv_id ).
      ENDIF.
    ENDLOOP.

    "--------------------------------------------------------------------
    " Delete all objects and the bucket (using the utility helper)
    "--------------------------------------------------------------------
    IF av_bucket_name IS NOT INITIAL.
      TRY.
          /awsex/cl_utils=>cleanup_bucket( iv_bucket = av_bucket_name io_s3 = ao_s3 ).
        CATCH /aws1/cx_rt_generic.
          " Ignore – bucket may already be empty or gone
      ENDTRY.
    ENDIF.

    "--------------------------------------------------------------------
    " Delete the IAM inline policy and then the role
    "--------------------------------------------------------------------
    IF av_role_name IS NOT INITIAL.
      TRY.
          ao_iam->deleterolepolicy(
            iv_rolename   = av_role_name
            iv_policyname = 'S3BatchOpsPolicy' ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
      TRY.
          ao_iam->deleterole( iv_rolename = av_role_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
  ENDMETHOD.


  METHOD create_test_job.
    "--------------------------------------------------------------------
    " Generate a unique idempotency token (ClientRequestToken)
    "--------------------------------------------------------------------
    DATA lv_uuid TYPE sysuuid_x16.
    DATA lv_token TYPE string.
    TRY.
        cl_system_uuid=>create_uuid_x16_static( IMPORTING uuid = lv_uuid ).
      CATCH cx_uuid_error.
        lv_uuid = '00000000000000000000000000000001'.
    ENDTRY.
    lv_token = lv_uuid.

    "--------------------------------------------------------------------
    " Build the batch operation: tag all objects with BatchTag=BatchValue
    "--------------------------------------------------------------------
    DATA lt_op_tags TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag( iv_key = 'BatchTag' iv_value = 'BatchValue' )
      TO lt_op_tags.

    DATA(lo_op) = NEW /aws1/cl_s3cjoboperation(
      io_s3putobjecttagging = NEW /aws1/cl_s3cs3setobjecttagop( it_tagset = lt_op_tags ) ).

    DATA(lo_manifest) = NEW /aws1/cl_s3cjobmanifest(
      io_spec = NEW /aws1/cl_s3cjobmanifestspec(
        iv_format = 'S3BatchOperations_CSV_20180820'
        it_fields = VALUE /aws1/cl_s3cjobmanifestfield00=>tt_jobmanifestfieldlist(
          ( NEW /aws1/cl_s3cjobmanifestfield00( 'Bucket' ) )
          ( NEW /aws1/cl_s3cjobmanifestfield00( 'Key'    ) ) ) )
      io_location = NEW /aws1/cl_s3cjobmanifestloc(
        iv_objectarn = av_manifest_arn
        iv_etag      = av_manifest_etag ) ).

    DATA(lo_report) = NEW /aws1/cl_s3cjobreport(
      iv_bucket      = av_report_bucket
      iv_format      = 'Report_CSV_20180820'
      iv_enabled     = abap_true
      iv_prefix      = 'batch-reports'
      iv_reportscope = 'AllTasks' ).

    " Tag every job with convert_test so it can be found for manual cleanup
    DATA lt_job_tags TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag( iv_key = 'convert_test' iv_value = 'true' )
      TO lt_job_tags.

    TRY.
        DATA(lo_result) = ao_s3c->createjob(
          iv_accountid            = av_account_id
          io_operation            = lo_op
          io_report               = lo_report
          io_manifest             = lo_manifest
          iv_priority             = 10
          iv_rolearn              = av_role_arn
          iv_description          = 'SAP ABAP s3c test job'
          iv_confirmationrequired = abap_true   " causes Suspended status
          iv_clientrequesttoken   = lv_token
          it_tags                 = lt_job_tags ).
        rv_job_id = lo_result->get_jobid( ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex).
        cl_abap_unit_assert=>fail(
          msg = |create_test_job failed: { lo_ex->get_text( ) }| ).
    ENDTRY.

    cl_abap_unit_assert=>assert_not_initial(
      act = rv_job_id
      msg = 'create_test_job must return a non-empty Job ID' ).
  ENDMETHOD.


  METHOD wait_for_stable_status.
    " Jobs with ConfirmationRequired=true go New → Preparing → Suspended.
    " We poll up to 60 × 5 s = 5 min.  Stable = Suspended | Ready | Active
    "   | Cancelled | Failed | Complete.
    DATA lv_status TYPE /aws1/s3cjobstatus.

    DO 60 TIMES.
      TRY.
          DATA(lo_desc) = ao_s3c->describejob(
            iv_accountid = av_account_id
            iv_jobid     = iv_job_id ).
          lv_status = lo_desc->get_job( )->get_status( ).
        CATCH /aws1/cx_rt_generic.
          WAIT UP TO 5 SECONDS.
          CONTINUE.
      ENDTRY.

      CASE lv_status.
        WHEN 'Suspended' OR 'Ready' OR 'Active'
          OR 'Cancelled' OR 'Failed' OR 'Complete'.
          RETURN.
      ENDCASE.

      WAIT UP TO 5 SECONDS.
    ENDDO.

    cl_abap_unit_assert=>fail(
      msg = |Job { iv_job_id } did not reach a stable status after 5 min (last: { lv_status })| ).
  ENDMETHOD.


  METHOD cancel_job_safe.
    TRY.
        DATA(lo_d) = ao_s3c->describejob(
          iv_accountid = av_account_id
          iv_jobid     = iv_job_id ).
        DATA(lv_st) = lo_d->get_job( )->get_status( ).

        IF lv_st = 'New'       OR lv_st = 'Preparing' OR
           lv_st = 'Suspended' OR lv_st = 'Ready'      OR
           lv_st = 'Active'    OR lv_st = 'Paused'     OR
           lv_st = 'Pausing'.
          ao_s3c->updatejobstatus(
            iv_accountid          = av_account_id
            iv_jobid              = iv_job_id
            iv_requestedjobstatus = 'Cancelled' ).
        ENDIF.
      CATCH /aws1/cx_rt_generic.
        " Ignore all errors in teardown
    ENDTRY.
  ENDMETHOD.


  "======================================================================
  " T E S T   M E T H O D S
  "======================================================================

  METHOD create_job.
    " ----------------------------------------------------------------
    " The create_job action class method creates a brand-new batch job
    " and returns its Job ID.  We verify the Job ID is not empty and
    " that DescribeJob confirms the job exists.
    " ----------------------------------------------------------------
    DATA lv_job_id TYPE /aws1/s3cjobid.

    ao_s3c_actions->create_job(
      EXPORTING
        iv_account_id    = av_account_id
        iv_role_arn      = av_role_arn
        iv_manifest_arn  = av_manifest_arn
        iv_manifest_etag = av_manifest_etag
        iv_report_bucket = av_report_bucket
      RECEIVING
        ov_job_id = lv_job_id ).

    " Store for teardown cancellation
    av_job_id_create = lv_job_id.

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_job_id
      msg = 'create_job must return a non-empty Job ID' ).

    " Poll until the job is stable, then verify it is described correctly
    wait_for_stable_status( lv_job_id ).

    DATA(lo_desc) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = lv_job_id ).

    cl_abap_unit_assert=>assert_equals(
      exp = lv_job_id
      act = lo_desc->get_job( )->get_jobid( )
      msg = 'DescribeJob must return the same Job ID that CreateJob returned' ).
  ENDMETHOD.


  METHOD update_job_priority.
    " ----------------------------------------------------------------
    " update_job_priority changes the priority of an existing job.
    " Pre-condition: av_job_id_priority is a job in Suspended status.
    " ----------------------------------------------------------------
    cl_abap_unit_assert=>assert_not_initial(
      act = av_job_id_priority
      msg = 'Pre-created job for update_job_priority must exist' ).

    DATA(lo_result) = ao_s3c_actions->update_job_priority(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id_priority
      iv_priority   = 60 ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'update_job_priority must return a bound result' ).

    cl_abap_unit_assert=>assert_equals(
      exp = av_job_id_priority
      act = lo_result->get_jobid( )
      msg = 'Returned Job ID must match the input Job ID' ).

    cl_abap_unit_assert=>assert_equals(
      exp = 60
      act = lo_result->get_priority( )
      msg = 'Job priority must be 60 after update_job_priority' ).
  ENDMETHOD.


  METHOD update_job_status.
    " ----------------------------------------------------------------
    " update_job_status cancels an existing Suspended job.
    " ----------------------------------------------------------------
    cl_abap_unit_assert=>assert_not_initial(
      act = av_job_id_cancel
      msg = 'Pre-created job for update_job_status must exist' ).

    DATA(lo_result) = ao_s3c_actions->update_job_status(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id_cancel
      iv_req_status = 'Cancelled' ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'update_job_status must return a bound result' ).

    cl_abap_unit_assert=>assert_equals(
      exp = av_job_id_cancel
      act = lo_result->get_jobid( )
      msg = 'Returned Job ID must match the input Job ID' ).

    " The API returns the new status immediately in the response
    DATA(lv_status) = lo_result->get_status( ).
    cl_abap_unit_assert=>assert_true(
      act = COND abap_bool(
        WHEN lv_status = 'Cancelled' OR lv_status = 'Cancelling'
        THEN abap_true ELSE abap_false )
      msg = |Job must be Cancelled/Cancelling in response; actual: { lv_status }| ).

    " Prevent teardown from trying to cancel an already-cancelled job
    CLEAR av_job_id_cancel.
  ENDMETHOD.


  METHOD describe_job.
    " ----------------------------------------------------------------
    " describe_job returns the full job descriptor.  We verify the
    " returned result object contains the expected Job ID and ARN.
    " ----------------------------------------------------------------
    cl_abap_unit_assert=>assert_not_initial(
      act = av_job_id_describe
      msg = 'Pre-created job for describe_job must exist' ).

    DATA(lo_result) = ao_s3c_actions->describe_job(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id_describe ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'describe_job must return a bound result' ).

    cl_abap_unit_assert=>assert_equals(
      exp = av_job_id_describe
      act = lo_result->get_job( )->get_jobid( )
      msg = 'DescribeJob must return the correct Job ID' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_job( )->get_jobarn( )
      msg = 'Job ARN must be populated' ).
  ENDMETHOD.


  METHOD get_job_tagging.
    " ----------------------------------------------------------------
    " get_job_tagging retrieves the tags on a job.
    " Pre-condition: av_job_id_get_tag has 'InitialTag' set in class_setup.
    " ----------------------------------------------------------------
    cl_abap_unit_assert=>assert_not_initial(
      act = av_job_id_get_tag
      msg = 'Pre-created job for get_job_tagging must exist' ).

    DATA(lo_result) = ao_s3c_actions->get_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id_get_tag ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'get_job_tagging must return a bound result' ).

    " The 'InitialTag' tag set in class_setup must be present
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_result->get_tags( ) INTO DATA(lo_tag).
      IF lo_tag->get_key( ) = 'InitialTag' AND lo_tag->get_value( ) = 'InitialValue'.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Tag 'InitialTag=InitialValue' must be returned by get_job_tagging| ).
  ENDMETHOD.


  METHOD put_job_tagging.
    " ----------------------------------------------------------------
    " put_job_tagging replaces the tag set on a job.
    " ----------------------------------------------------------------
    cl_abap_unit_assert=>assert_not_initial(
      act = av_job_id_put_tag
      msg = 'Pre-created job for put_job_tagging must exist' ).

    DATA lt_new_tags TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag( iv_key = 'Environment' iv_value = 'Development'     )
      TO lt_new_tags.
    APPEND NEW /aws1/cl_s3cs3tag( iv_key = 'Team'        iv_value = 'DataProcessing' )
      TO lt_new_tags.

    ao_s3c_actions->put_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id_put_tag
      it_tags       = lt_new_tags ).

    " Read back and verify
    DATA(lo_verify) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_put_tag ).

    DATA(lt_actual) = lo_verify->get_tags( ).

    cl_abap_unit_assert=>assert_equals(
      exp = 2
      act = lines( lt_actual )
      msg = 'Exactly 2 tags must be present after put_job_tagging' ).

    DATA lv_env_ok TYPE abap_bool VALUE abap_false.
    LOOP AT lt_actual INTO DATA(lo_t).
      IF lo_t->get_key( ) = 'Environment' AND lo_t->get_value( ) = 'Development'.
        lv_env_ok = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_env_ok
      msg = |Tag 'Environment=Development' must exist after put_job_tagging| ).
  ENDMETHOD.


  METHOD list_jobs.
    " ----------------------------------------------------------------
    " list_jobs returns all jobs for all statuses.  We verify that
    " av_job_id_list (a Suspended job) appears in the result.
    " ----------------------------------------------------------------
    cl_abap_unit_assert=>assert_not_initial(
      act = av_job_id_list
      msg = 'Pre-created job for list_jobs must exist' ).

    DATA(lo_result) = ao_s3c_actions->list_jobs( iv_account_id = av_account_id ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_jobs must return a bound result' ).

    " Verify our reference job is in the list
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_result->get_jobs( ) INTO DATA(lo_job).
      IF lo_job->get_jobid( ) = av_job_id_list.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Job { av_job_id_list } must appear in list_jobs result| ).
  ENDMETHOD.


  METHOD delete_job_tagging.
    " ----------------------------------------------------------------
    " delete_job_tagging removes all tags from a job.
    " Pre-condition: av_job_id_del_tag has 'InitialTag' set in class_setup.
    " ----------------------------------------------------------------
    cl_abap_unit_assert=>assert_not_initial(
      act = av_job_id_del_tag
      msg = 'Pre-created job for delete_job_tagging must exist' ).

    ao_s3c_actions->delete_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id_del_tag ).

    " Verify the tag set is now empty
    DATA(lo_verify) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_del_tag ).

    cl_abap_unit_assert=>assert_initial(
      act = lo_verify->get_tags( )
      msg = 'Tag set must be empty after delete_job_tagging' ).
  ENDMETHOD.

ENDCLASS.
