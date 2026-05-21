" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_s3c_actions DEFINITION DEFERRED.
CLASS /awsex/cl_s3c_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_s3c_actions.

CLASS ltc_awsex_cl_s3c_actions DEFINITION
  FOR TESTING
  DURATION LONG
  RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " Shared AWS client handles
    CLASS-DATA ao_session      TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_s3           TYPE REF TO /aws1/if_s3.
    CLASS-DATA ao_s3c          TYPE REF TO /aws1/if_s3c.
    CLASS-DATA ao_iam          TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_s3c_actions  TYPE REF TO /awsex/cl_s3c_actions.

    " Shared state set in class_setup
    CLASS-DATA av_account_id     TYPE /aws1/s3caccountid.
    CLASS-DATA av_region         TYPE /aws1/rt_region_id.
    CLASS-DATA av_src_bucket     TYPE /aws1/s3_bucketname.
    CLASS-DATA av_rpt_bucket     TYPE /aws1/s3_bucketname.
    CLASS-DATA av_role_name      TYPE /aws1/iamrolenametype.
    CLASS-DATA av_role_arn       TYPE /aws1/s3ciamrolearn.
    CLASS-DATA av_manifest_arn   TYPE /aws1/s3cs3keyarnstring.
    CLASS-DATA av_manifest_etag  TYPE /aws1/s3cnonemptymaxlength1000.
    CLASS-DATA av_rpt_bucket_arn TYPE /aws1/s3cs3bucketarnstring.

    " Dedicated job IDs – one per mutating test so tests are independent
    CLASS-DATA av_job_id_shared   TYPE /aws1/s3cjobid.  " read-only tests
    CLASS-DATA av_job_id_upd_pri  TYPE /aws1/s3cjobid.  " update_job_priority
    CLASS-DATA av_job_id_cancel   TYPE /aws1/s3cjobid.  " update_job_status
    CLASS-DATA av_job_id_get_tag  TYPE /aws1/s3cjobid.  " get_job_tagging
    CLASS-DATA av_job_id_put_tag  TYPE /aws1/s3cjobid.  " put_job_tagging
    CLASS-DATA av_job_id_del_tag  TYPE /aws1/s3cjobid.  " delete_job_tagging

    CLASS-METHODS class_setup
      RAISING
        /aws1/cx_rt_generic
        /awsex/cx_generic.

    CLASS-METHODS class_teardown
      RAISING
        /aws1/cx_rt_generic
        /awsex/cx_generic.

    " Builds a fresh batch job against the shared manifest and returns its job ID.
    " Jobs are created with ConfirmationRequired=true so they sit in New/Suspended
    " state and never automatically consume S3 objects.
    CLASS-METHODS create_test_job
      RETURNING
        VALUE(ov_job_id) TYPE /aws1/s3cjobid
      RAISING
        /aws1/cx_rt_generic.

    METHODS create_job          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_job_priority FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_job_status   FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS describe_job        FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS get_job_tagging     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS put_job_tagging     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_jobs           FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_job_tagging  FOR TESTING RAISING /aws1/cx_rt_generic.

ENDCLASS.


CLASS ltc_awsex_cl_s3c_actions IMPLEMENTATION.

  METHOD class_setup.
    " -----------------------------------------------------------------
    " Initialise SDK clients
    " -----------------------------------------------------------------
    ao_session    = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_s3         = /aws1/cl_s3_factory=>create( ao_session ).
    ao_s3c        = /aws1/cl_s3c_factory=>create( ao_session ).
    ao_iam        = /aws1/cl_iam_factory=>create( ao_session ).
    ao_s3c_actions = NEW /awsex/cl_s3c_actions( ).

    av_account_id = ao_session->get_account_id( ).
    av_region     = ao_session->get_region( ).

    " -----------------------------------------------------------------
    " Build stable, account-scoped resource names
    " -----------------------------------------------------------------
    av_src_bucket = |sap-s3c-test-src-{ av_account_id }|.
    av_rpt_bucket = |sap-s3c-test-rpt-{ av_account_id }|.
    av_role_name  = |sap-s3c-test-role-{ av_account_id }|.

    " -----------------------------------------------------------------
    " Create S3 source and report buckets (idempotent via util helper)
    " -----------------------------------------------------------------
    /awsex/cl_utils=>create_bucket(
      iv_bucket  = av_src_bucket
      io_s3      = ao_s3
      io_session = ao_session ).

    /awsex/cl_utils=>create_bucket(
      iv_bucket  = av_rpt_bucket
      io_s3      = ao_s3
      io_session = ao_session ).

    " Tag both buckets
    DATA lt_s3_tags TYPE /aws1/cl_s3_tag=>tt_tagset.
    APPEND NEW /aws1/cl_s3_tag( iv_key = 'convert_test' iv_value = 'true' ) TO lt_s3_tags.

    TRY.
        ao_s3->putbuckettagging(
          iv_bucket  = av_src_bucket
          io_tagging = NEW /aws1/cl_s3_tagging( it_tagset = lt_s3_tags ) ).
        ao_s3->putbuckettagging(
          iv_bucket  = av_rpt_bucket
          io_tagging = NEW /aws1/cl_s3_tagging( it_tagset = lt_s3_tags ) ).
      CATCH /aws1/cx_rt_generic.
        " Tagging failures are non-fatal
    ENDTRY.

    " -----------------------------------------------------------------
    " Upload a minimal CSV manifest object
    " The manifest lists one entry for the source bucket.
    " -----------------------------------------------------------------
    CONSTANTS cv_manifest_key TYPE /aws1/s3_objectkey VALUE 'job-manifest.csv'.

    DATA lv_body TYPE string.
    lv_body = |{ av_src_bucket },placeholder-key|.

    DATA(lo_put) = ao_s3->putobject(
      iv_bucket = av_src_bucket
      iv_key    = cv_manifest_key
      iv_body   = cl_abap_codepage=>convert_to( lv_body ) ).

    " Capture ETag (strip surrounding double-quotes returned by S3)
    av_manifest_etag = lo_put->get_etag( ).
    REPLACE ALL OCCURRENCES OF '"' IN av_manifest_etag WITH ''.

    av_manifest_arn = |arn:aws:s3:::{ av_src_bucket }/{ cv_manifest_key }|.
    av_rpt_bucket_arn = |arn:aws:s3:::{ av_rpt_bucket }|.

    " -----------------------------------------------------------------
    " Create the IAM role that S3 Batch Operations will assume.
    " Trust policy allows batchoperations.s3.amazonaws.com to assume it.
    " -----------------------------------------------------------------
    DATA lv_trust TYPE /aws1/iampolicydocumenttype.
    lv_trust = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",' &&
               '"Principal":{"Service":"batchoperations.s3.amazonaws.com"},' &&
               '"Action":"sts:AssumeRole"}]}'.

    DATA lt_iam_tags TYPE /aws1/cl_iamtag=>tt_taglisttype.
    APPEND NEW /aws1/cl_iamtag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_iam_tags.

    TRY.
        DATA(lo_role) = ao_iam->createrole(
          iv_rolename                = av_role_name
          iv_assumerolepolicydocument = lv_trust
          iv_description             = 'SAP ABAP s3c example test role'
          it_tags                    = lt_iam_tags ).
        av_role_arn = lo_role->get_role( )->get_arn( ).
      CATCH /aws1/cx_iamentityalrdyexex.
        " Role already exists from a previous run; retrieve its ARN
        DATA(lo_get) = ao_iam->getrole( iv_rolename = av_role_name ).
        av_role_arn = lo_get->get_role( )->get_arn( ).
    ENDTRY.

    cl_abap_unit_assert=>assert_not_initial(
      act = av_role_arn
      msg = 'class_setup: failed to obtain IAM role ARN' ).

    " -----------------------------------------------------------------
    " Attach inline permissions so the role can:
    "   1. Read the manifest object from the source bucket
    "   2. Get/Put/Delete object tags on any object in the source bucket
    "   3. Write job reports to the report bucket
    "   4. Report job progress (s3:GetBucketLocation on all buckets)
    " -----------------------------------------------------------------
    DATA lv_policy TYPE /aws1/iampolicydocumenttype.
    lv_policy =
      '{' &&
        '"Version":"2012-10-17",' &&
        '"Statement":[' &&
          '{' &&
            '"Sid":"ManifestRead",' &&
            '"Effect":"Allow",' &&
            '"Action":["s3:GetObject","s3:GetObjectVersion"],' &&
            '"Resource":"arn:aws:s3:::' && av_src_bucket && '/*"' &&
          '},' &&
          '{' &&
            '"Sid":"ObjectTagging",' &&
            '"Effect":"Allow",' &&
            '"Action":["s3:PutObjectTagging","s3:GetObjectTagging",' &&
                      '"s3:DeleteObjectTagging"],' &&
            '"Resource":"arn:aws:s3:::' && av_src_bucket && '/*"' &&
          '},' &&
          '{' &&
            '"Sid":"ReportWrite",' &&
            '"Effect":"Allow",' &&
            '"Action":["s3:PutObject"],' &&
            '"Resource":"arn:aws:s3:::' && av_rpt_bucket && '/*"' &&
          '},' &&
          '{' &&
            '"Sid":"BucketLocation",' &&
            '"Effect":"Allow",' &&
            '"Action":"s3:GetBucketLocation",' &&
            '"Resource":"*"' &&
          '}' &&
        ']' &&
      '}'.

    ao_iam->putrolepolicy(
      iv_rolename      = av_role_name
      iv_policyname    = 'S3BatchOpsPermissions'
      iv_policydocument = lv_policy ).

    " IAM policy propagation takes a few seconds
    WAIT UP TO 10 SECONDS.

    " -----------------------------------------------------------------
    " Pre-create all the batch jobs needed by individual test methods.
    " Each mutating test gets its own dedicated job.
    " -----------------------------------------------------------------
    av_job_id_shared  = create_test_job( ).
    av_job_id_upd_pri = create_test_job( ).
    av_job_id_cancel  = create_test_job( ).
    av_job_id_get_tag = create_test_job( ).
    av_job_id_put_tag = create_test_job( ).
    av_job_id_del_tag = create_test_job( ).

    " Pre-tag the del_tag job so the delete_job_tagging test has something to remove
    DATA lt_init_tags TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag(
      iv_key   = 'InitialKey'
      iv_value = 'InitialValue' ) TO lt_init_tags.

    ao_s3c->putjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_del_tag
      it_tags      = lt_init_tags ).

    " Pre-tag the get_tag job so get_job_tagging has real tags to read back
    DATA lt_get_tags TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag(
      iv_key   = 'ReadKey'
      iv_value = 'ReadValue' ) TO lt_get_tags.

    ao_s3c->putjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_get_tag
      it_tags      = lt_get_tags ).

    " Fail loudly if any pre-created job is missing
    cl_abap_unit_assert=>assert_not_initial(
      act = av_job_id_shared
      msg = 'class_setup: av_job_id_shared is empty' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_job_id_upd_pri
      msg = 'class_setup: av_job_id_upd_pri is empty' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_job_id_cancel
      msg = 'class_setup: av_job_id_cancel is empty' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_job_id_get_tag
      msg = 'class_setup: av_job_id_get_tag is empty' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_job_id_put_tag
      msg = 'class_setup: av_job_id_put_tag is empty' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_job_id_del_tag
      msg = 'class_setup: av_job_id_del_tag is empty' ).
  ENDMETHOD.


  METHOD class_teardown.
    " -----------------------------------------------------------------
    " Cancel all batch jobs created during setup (ignore errors – jobs
    " may have already reached a terminal state).
    " -----------------------------------------------------------------
    DATA lt_jids TYPE STANDARD TABLE OF /aws1/s3cjobid WITH DEFAULT KEY.
    APPEND av_job_id_shared  TO lt_jids.
    APPEND av_job_id_upd_pri TO lt_jids.
    APPEND av_job_id_cancel  TO lt_jids.
    APPEND av_job_id_get_tag TO lt_jids.
    APPEND av_job_id_put_tag TO lt_jids.
    APPEND av_job_id_del_tag TO lt_jids.

    LOOP AT lt_jids ASSIGNING FIELD-SYMBOL(<lv_jid>).
      CHECK <lv_jid> IS NOT INITIAL.
      TRY.
          ao_s3c->updatejobstatus(
            iv_accountid          = av_account_id
            iv_jobid              = <lv_jid>
            iv_requestedjobstatus = 'Cancelled' ).
        CATCH /aws1/cx_rt_generic.
          " Already terminal
      ENDTRY.
    ENDLOOP.

    " -----------------------------------------------------------------
    " Delete the inline role policy then the role itself.
    " The role is tagged 'convert_test' in case cleanup is incomplete.
    " -----------------------------------------------------------------
    IF av_role_name IS NOT INITIAL.
      TRY.
          ao_iam->deleterolepolicy(
            iv_rolename   = av_role_name
            iv_policyname = 'S3BatchOpsPermissions' ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
      TRY.
          ao_iam->deleterole( iv_rolename = av_role_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " -----------------------------------------------------------------
    " Clean up the two S3 buckets using the util helper.
    " -----------------------------------------------------------------
    TRY.
        /awsex/cl_utils=>cleanup_bucket( io_s3 = ao_s3 iv_bucket = av_src_bucket ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        /awsex/cl_utils=>cleanup_bucket( io_s3 = ao_s3 iv_bucket = av_rpt_bucket ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  METHOD create_test_job.
    " Build a minimal S3 Batch Operations job.
    " ConfirmationRequired = true keeps it in New/Suspended so it never
    " executes against real objects in the source bucket.

    DATA lt_fields TYPE /aws1/cl_s3cjobmanifestfield00=>tt_jobmanifestfieldlist.
    APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Bucket' ) TO lt_fields.
    APPEND NEW /aws1/cl_s3cjobmanifestfield00( 'Key' )    TO lt_fields.

    DATA lt_tagset TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag(
      iv_key   = 'BatchTag'
      iv_value = 'BatchValue' ) TO lt_tagset.

    DATA(lo_result) = ao_s3c->createjob(
      iv_accountid            = av_account_id
      iv_confirmationrequired = abap_true
      iv_priority             = 10
      iv_rolearn              = av_role_arn
      iv_description          = 'SAP ABAP s3c test job'
      io_operation            = NEW /aws1/cl_s3cjoboperation(
        io_s3putobjecttagging = NEW /aws1/cl_s3cs3setobjecttagop(
          it_tagset = lt_tagset ) )
      io_manifest             = NEW /aws1/cl_s3cjobmanifest(
        io_spec     = NEW /aws1/cl_s3cjobmanifestspec(
          iv_format = 'S3BatchOperations_CSV_20180820'
          it_fields = lt_fields )
        io_location = NEW /aws1/cl_s3cjobmanifestloc(
          iv_objectarn = av_manifest_arn
          iv_etag      = av_manifest_etag ) )
      io_report               = NEW /aws1/cl_s3cjobreport(
        iv_bucket      = av_rpt_bucket_arn
        iv_format      = 'Report_CSV_20180820'
        iv_enabled     = abap_true
        iv_prefix      = 'batch-op-reports'
        iv_reportscope = 'AllTasks' ) ).

    ov_job_id = lo_result->get_jobid( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = ov_job_id
      msg = 'create_test_job: S3 Batch returned empty job ID' ).
  ENDMETHOD.


  " ===========================================================
  " TEST: create_job
  " Calls the action method under test, verifies the returned
  " job ID is non-empty, then confirms existence via DescribeJob.
  " Cleans up the extra job created by this test.
  " ===========================================================
  METHOD create_job.
    DATA(lv_job_id) = ao_s3c_actions->create_job(
      iv_account_id     = av_account_id
      iv_role_arn       = av_role_arn
      iv_manifest_arn   = av_manifest_arn
      iv_manifest_etag  = av_manifest_etag
      iv_report_bkt_arn = av_rpt_bucket_arn ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_job_id
      msg = 'create_job: action method returned empty job ID' ).

    " Verify the job actually exists in S3 Control
    DATA(lo_desc) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = lv_job_id ).

    cl_abap_unit_assert=>assert_equals(
      exp = lv_job_id
      act = lo_desc->get_job( )->get_jobid( )
      msg = 'create_job: DescribeJob returned different job ID' ).

    " The description must match what the action sets
    cl_abap_unit_assert=>assert_equals(
      exp = 'Batch job for tagging objects'
      act = lo_desc->get_job( )->get_description( )
      msg = 'create_job: job description does not match' ).

    " Clean up: cancel the newly created job
    TRY.
        ao_s3c->updatejobstatus(
          iv_accountid          = av_account_id
          iv_jobid              = lv_job_id
          iv_requestedjobstatus = 'Cancelled' ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  " ===========================================================
  " TEST: update_job_priority
  " Calls the action method which sets priority to 60, then
  " verifies via DescribeJob that the new priority is reflected.
  " ===========================================================
  METHOD update_job_priority.
    ao_s3c_actions->update_job_priority(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id_upd_pri ).

    DATA(lo_result) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_upd_pri ).

    cl_abap_unit_assert=>assert_equals(
      exp = 60
      act = lo_result->get_job( )->get_priority( )
      msg = 'update_job_priority: priority was not updated to 60' ).
  ENDMETHOD.


  " ===========================================================
  " TEST: update_job_status
  " Calls the action method which cancels the job, then polls
  " DescribeJob until status = Cancelled (or fails after timeout).
  " ===========================================================
  METHOD update_job_status.
    ao_s3c_actions->update_job_status(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id_cancel ).

    " Poll for the terminal state – S3 Batch may take a few seconds
    DATA lv_status   TYPE /aws1/s3cjobstatus.
    DATA lv_attempts TYPE i VALUE 0.

    DO 15 TIMES.
      lv_attempts = sy-index.
      DATA(lo_result) = ao_s3c->describejob(
        iv_accountid = av_account_id
        iv_jobid     = av_job_id_cancel ).
      lv_status = lo_result->get_job( )->get_status( ).
      IF lv_status = 'Cancelled'.
        EXIT.
      ENDIF.
      WAIT UP TO 3 SECONDS.
    ENDDO.

    cl_abap_unit_assert=>assert_equals(
      exp = 'Cancelled'
      act = lv_status
      msg = |update_job_status: expected Cancelled after { lv_attempts } polls, got { lv_status }| ).
  ENDMETHOD.


  " ===========================================================
  " TEST: describe_job
  " Calls the action method then independently verifies the job
  " descriptor contains the expected job ID and a non-empty status.
  " ===========================================================
  METHOD describe_job.
    " The action method exercises describe_job against the shared job
    ao_s3c_actions->describe_job(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id_shared ).

    " Independent verification through the raw SDK call
    DATA(lo_result) = ao_s3c->describejob(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_shared ).

    cl_abap_unit_assert=>assert_equals(
      exp = av_job_id_shared
      act = lo_result->get_job( )->get_jobid( )
      msg = 'describe_job: returned job ID does not match expected' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_job( )->get_status( )
      msg = 'describe_job: status field must not be empty' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_job( )->get_rolearn( )
      msg = 'describe_job: role ARN must not be empty' ).
  ENDMETHOD.


  " ===========================================================
  " TEST: get_job_tagging
  " The get_tag job was pre-tagged in class_setup with ReadKey=ReadValue.
  " This test calls the action method then verifies via SDK that at
  " least that tag is still present, proving the call succeeded.
  " ===========================================================
  METHOD get_job_tagging.
    " Call the action under test
    ao_s3c_actions->get_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id_get_tag ).

    " Independently verify the tags we pre-set are readable
    DATA(lo_result) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_get_tag ).

    DATA(lt_tags) = lo_result->get_tags( ).

    cl_abap_unit_assert=>assert_true(
      act  = xsdbool( lines( lt_tags ) > 0 )
      msg  = 'get_job_tagging: expected at least 1 tag on pre-tagged job' ).

    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_tags ASSIGNING FIELD-SYMBOL(<lo_tag>).
      IF <lo_tag>->get_key( ) = 'ReadKey' AND <lo_tag>->get_value( ) = 'ReadValue'.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = 'get_job_tagging: pre-set ReadKey=ReadValue tag not found' ).
  ENDMETHOD.


  " ===========================================================
  " TEST: put_job_tagging
  " Calls the action method (sets Environment=Development,
  " Team=DataProcessing), then verifies both tags via GetJobTagging.
  " ===========================================================
  METHOD put_job_tagging.
    ao_s3c_actions->put_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id_put_tag ).

    DATA(lo_result) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_put_tag ).

    DATA(lt_tags) = lo_result->get_tags( ).

    cl_abap_unit_assert=>assert_equals(
      exp = 2
      act = lines( lt_tags )
      msg = 'put_job_tagging: expected exactly 2 tags after put' ).

    DATA lv_found_env  TYPE abap_bool VALUE abap_false.
    DATA lv_found_team TYPE abap_bool VALUE abap_false.

    LOOP AT lt_tags ASSIGNING FIELD-SYMBOL(<lo_tag>).
      IF <lo_tag>->get_key( ) = 'Environment' AND <lo_tag>->get_value( ) = 'Development'.
        lv_found_env = abap_true.
      ENDIF.
      IF <lo_tag>->get_key( ) = 'Team' AND <lo_tag>->get_value( ) = 'DataProcessing'.
        lv_found_team = abap_true.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found_env
      msg = 'put_job_tagging: Environment=Development tag not found' ).

    cl_abap_unit_assert=>assert_true(
      act = lv_found_team
      msg = 'put_job_tagging: Team=DataProcessing tag not found' ).
  ENDMETHOD.


  " ===========================================================
  " TEST: list_jobs
  " Calls the action method, then verifies via the SDK that the
  " shared job (which must still be in a non-terminal state) appears
  " in the listing returned by the raw ListJobs call.
  " ===========================================================
  METHOD list_jobs.
    " Call the action under test
    ao_s3c_actions->list_jobs( iv_account_id = av_account_id ).

    " Independent verification: list across all non-terminal statuses
    DATA lt_statuses TYPE /aws1/cl_s3cjobstatuslist_w=>tt_jobstatuslist.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'New' )       TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Suspended' ) TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Preparing' ) TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Ready' )     TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Active' )    TO lt_statuses.

    DATA(lo_result) = ao_s3c->listjobs(
      iv_accountid   = av_account_id
      it_jobstatuses = lt_statuses ).

    DATA(lt_jobs) = lo_result->get_jobs( ).

    " We must find the shared job (it was never mutated)
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_jobs ASSIGNING FIELD-SYMBOL(<lo_job>).
      IF <lo_job>->get_jobid( ) = av_job_id_shared.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_jobs: shared job { av_job_id_shared } not found in active job listing| ).
  ENDMETHOD.


  " ===========================================================
  " TEST: delete_job_tagging
  " The del_tag job was pre-tagged in class_setup with InitialKey.
  " Calls the action method which removes all tags, then verifies
  " the tag list is empty via GetJobTagging.
  " ===========================================================
  METHOD delete_job_tagging.
    ao_s3c_actions->delete_job_tagging(
      iv_account_id = av_account_id
      iv_job_id     = av_job_id_del_tag ).

    DATA(lo_result) = ao_s3c->getjobtagging(
      iv_accountid = av_account_id
      iv_jobid     = av_job_id_del_tag ).

    cl_abap_unit_assert=>assert_initial(
      act = lo_result->get_tags( )
      msg = 'delete_job_tagging: tags were not deleted – list is not empty' ).
  ENDMETHOD.

ENDCLASS.
