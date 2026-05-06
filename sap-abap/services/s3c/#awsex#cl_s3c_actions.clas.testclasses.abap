" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_s3c_actions DEFINITION DEFERRED.
CLASS /awsex/cl_s3c_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_s3c_actions.

CLASS ltc_awsex_cl_s3c_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.
  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    CLASS-DATA ao_session TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_s3c TYPE REF TO /aws1/if_s3c.
    CLASS-DATA ao_s3 TYPE REF TO /aws1/if_s3.
    CLASS-DATA ao_iam TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_s3c_actions TYPE REF TO /awsex/cl_s3c_actions.
    CLASS-DATA av_account_id TYPE /aws1/s3caccountid.
    CLASS-DATA av_bucket_name TYPE /aws1/s3_bucketname.
    CLASS-DATA av_report_bucket TYPE /aws1/s3_bucketname.
    CLASS-DATA av_role_name TYPE /aws1/iamrolename.
    CLASS-DATA av_role_arn TYPE /aws1/s3ciamrolearn.
    CLASS-DATA av_job_id TYPE /aws1/s3cjobid.
    CLASS-DATA av_job_id_priority TYPE /aws1/s3cjobid.
    CLASS-DATA av_job_id_status TYPE /aws1/s3cjobid.
    CLASS-DATA av_job_id_tagging TYPE /aws1/s3cjobid.
    METHODS: create_job FOR TESTING RAISING /aws1/cx_rt_generic,
      describe_job FOR TESTING RAISING /aws1/cx_rt_generic,
      update_job_priority FOR TESTING RAISING /aws1/cx_rt_generic,
      update_job_status FOR TESTING RAISING /aws1/cx_rt_generic,
      get_job_tagging FOR TESTING RAISING /aws1/cx_rt_generic,
      put_job_tagging FOR TESTING RAISING /aws1/cx_rt_generic,
      list_jobs FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_job_tagging FOR TESTING RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_setup RAISING /aws1/cx_rt_generic /awsex/cx_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic /awsex/cx_generic.
    CLASS-METHODS wait_for_job_ready IMPORTING iv_job_id TYPE /aws1/s3cjobid
      RETURNING VALUE(rv_ready) TYPE abap_bool RAISING /aws1/cx_rt_generic.
    CLASS-METHODS create_batch_job IMPORTING iv_job_desc TYPE string
      RETURNING VALUE(rv_job_id) TYPE /aws1/s3cjobid RAISING /aws1/cx_rt_generic.
ENDCLASS.

CLASS ltc_awsex_cl_s3c_actions IMPLEMENTATION.
  METHOD class_setup.
    ao_session = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_s3c = /aws1/cl_s3c_factory=>create( ao_session ).
    ao_s3 = /aws1/cl_s3_factory=>create( ao_session ).
    ao_iam = /aws1/cl_iam_factory=>create( ao_session ).
    ao_s3c_actions = NEW /awsex/cl_s3c_actions( ).
    av_account_id = ao_session->get_account_id( ).
    DATA(lv_random) = /awsex/cl_utils=>get_random_string( ).
    av_bucket_name = |sap-abap-s3c-{ av_account_id }-{ lv_random }|.
    av_report_bucket = |sap-abap-s3c-rep-{ av_account_id }-{ lv_random }|.
    av_role_name = |sap-s3c-batch-{ lv_random }|.
    TRY.
        /awsex/cl_utils=>create_bucket( iv_bucket = av_bucket_name io_s3 = ao_s3 io_session = ao_session ).
        /awsex/cl_utils=>create_bucket( iv_bucket = av_report_bucket io_s3 = ao_s3 io_session = ao_session ).
      CATCH /aws1/cx_s3_bktalrdyownedbyyou.
    ENDTRY.
    DATA lt_tags TYPE /aws1/cl_s3_tag=>tt_tagset.
    APPEND NEW /aws1/cl_s3_tag( iv_key = 'convert_test' iv_value = 'true' ) TO lt_tags.
    TRY.
        ao_s3->putbuckettagging( iv_bucket = av_bucket_name io_tagging = NEW /aws1/cl_s3_tagging( it_tagset = lt_tags ) ).
        ao_s3->putbuckettagging( iv_bucket = av_report_bucket io_tagging = NEW /aws1/cl_s3_tagging( it_tagset = lt_tags ) ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    DATA(lv_trust_policy) = |\{| && |"Version":"2012-10-17",| && |"Statement":[\{| &&
      |"Effect":"Allow",| && |"Principal":\{"Service":"batchoperations.s3.amazonaws.com"\},| &&
      |"Action":"sts:AssumeRole"\}]\}|.
    TRY.
        DATA(lo_role) = ao_iam->createrole( iv_rolename = av_role_name iv_assumerolepolicydocument = lv_trust_policy
          it_tags = VALUE /aws1/cl_iamtag=>tt_taglisttype( ( NEW /aws1/cl_iamtag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).
        av_role_arn = lo_role->get_role( )->get_arn( ).
      CATCH /aws1/cx_iamentityalrdyexists.
        av_role_arn = ao_iam->getrole( iv_rolename = av_role_name )->get_role( )->get_arn( ).
    ENDTRY.
    DATA(lv_policy) = |\{| && |"Version":"2012-10-17","Statement":[\{| &&
      |"Effect":"Allow","Action":["s3:GetObject","s3:GetObjectVersion","s3:PutObject","s3:PutObjectTagging",| &&
      |"s3:GetBucketLocation","s3:ListBucket","s3:ListBucketVersions"],| &&
      |"Resource":["arn:aws:s3:::{ av_bucket_name }","arn:aws:s3:::{ av_bucket_name }/*",| &&
      |"arn:aws:s3:::{ av_report_bucket }","arn:aws:s3:::{ av_report_bucket }/*"]\}]\}|.
    TRY.
        ao_iam->putrolepolicy( iv_rolename = av_role_name iv_policyname = 'S3BatchOpsPolicy' iv_policydocument = lv_policy ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    WAIT UP TO 10 SECONDS.
    DATA(lv_manifest) = |{ av_bucket_name },obj-1.txt{ cl_abap_char_utilities=>newline }| &&
                        |{ av_bucket_name },obj-2.txt{ cl_abap_char_utilities=>newline }| &&
                        |{ av_bucket_name },obj-3.txt|.
    DATA lt_objs TYPE TABLE OF /aws1/s3_objectkey.
    APPEND 'obj-1.txt' TO lt_objs.
    APPEND 'obj-2.txt' TO lt_objs.
    APPEND 'obj-3.txt' TO lt_objs.
    LOOP AT lt_objs INTO DATA(lv_obj).
      TRY.
          ao_s3->putobject( iv_bucket = av_bucket_name iv_key = lv_obj iv_body = |Content { lv_obj }| ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDLOOP.
    TRY.
        ao_s3->putobject( iv_bucket = av_bucket_name iv_key = 'manifest.csv' iv_body = lv_manifest ).
      CATCH /aws1/cx_rt_generic.
        cl_abap_unit_assert=>fail( msg = |Failed to create manifest file| ).
    ENDTRY.
  ENDMETHOD.

  METHOD class_teardown.
    DATA lt_jobs TYPE TABLE OF /aws1/s3cjobid.
    IF av_job_id IS NOT INITIAL.
      APPEND av_job_id TO lt_jobs.
    ENDIF.
    IF av_job_id_priority IS NOT INITIAL.
      APPEND av_job_id_priority TO lt_jobs.
    ENDIF.
    IF av_job_id_status IS NOT INITIAL.
      APPEND av_job_id_status TO lt_jobs.
    ENDIF.
    IF av_job_id_tagging IS NOT INITIAL.
      APPEND av_job_id_tagging TO lt_jobs.
    ENDIF.
    LOOP AT lt_jobs INTO DATA(lv_job).
      TRY.
          DATA(lo_desc) = ao_s3c->describejob( iv_accountid = av_account_id iv_jobid = lv_job ).
          DATA(lv_status) = lo_desc->get_job( )->get_status( ).
          IF lv_status = 'Ready' OR lv_status = 'Suspended' OR lv_status = 'Active'.
            ao_s3c->updatejobstatus( iv_accountid = av_account_id iv_jobid = lv_job iv_requestedjobstatus = 'Cancelled' ).
          ENDIF.
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDLOOP.
    /awsex/cl_utils=>cleanup_bucket( io_s3 = ao_s3 iv_bucket = av_bucket_name ).
    /awsex/cl_utils=>cleanup_bucket( io_s3 = ao_s3 iv_bucket = av_report_bucket ).
    IF av_role_name IS NOT INITIAL.
      TRY.
          ao_iam->deleterolepolicy( iv_rolename = av_role_name iv_policyname = 'S3BatchOpsPolicy' ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
      TRY.
          ao_iam->deleterole( iv_rolename = av_role_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
  ENDMETHOD.

  METHOD wait_for_job_ready.
    DATA(lv_max) = 60.
    DATA(lv_count) = 0.
    rv_ready = abap_false.
    WHILE lv_count < lv_max AND rv_ready = abap_false.
      WAIT UP TO 5 SECONDS.
      lv_count = lv_count + 5.
      TRY.
          DATA(lo_job) = ao_s3c->describejob( iv_accountid = av_account_id iv_jobid = iv_job_id ).
          DATA(lv_stat) = lo_job->get_job( )->get_status( ).
          IF lv_stat = 'Ready' OR lv_stat = 'Suspended' OR lv_stat = 'Active' OR
             lv_stat = 'Complete' OR lv_stat = 'Cancelled' OR lv_stat = 'Failed'.
            rv_ready = abap_true.
          ENDIF.
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDWHILE.
  ENDMETHOD.

  METHOD create_batch_job.
    DATA(lo_manifest) = ao_s3->headobject( iv_bucket = av_bucket_name iv_key = 'manifest.csv' ).
    DATA(lv_etag) = lo_manifest->get_etag( ).
    REPLACE ALL OCCURRENCES OF '"' IN lv_etag WITH ''.
    DATA(lv_manifest_arn) = |arn:aws:s3:::{ av_bucket_name }/manifest.csv|.
    DATA(lv_report_arn) = |arn:aws:s3:::{ av_report_bucket }|.
    TRY.
        DATA(lo_result) = ao_s3c->createjob(
          iv_accountid = av_account_id
          iv_rolearn = av_role_arn
          io_manifest = NEW /aws1/cl_s3cjobmanifest(
            io_location = NEW /aws1/cl_s3cjobmanifestloc( iv_etag = lv_etag iv_objectarn = lv_manifest_arn )
            io_spec = NEW /aws1/cl_s3cjobmanifestspec(
              it_fields = VALUE /aws1/cl_s3cjobmanifestfield00=>tt_jobmanifestfieldlist(
                ( NEW /aws1/cl_s3cjobmanifestfield00( 'Bucket' ) )
                ( NEW /aws1/cl_s3cjobmanifestfield00( 'Key' ) ) )
              iv_format = 'S3BatchOperations_CSV_20180820' ) )
          io_operation = NEW /aws1/cl_s3cjoboperation(
            io_s3putobjecttagging = NEW /aws1/cl_s3cs3setobjecttagop(
              it_tagset = VALUE /aws1/cl_s3cs3tag=>tt_s3tagset(
                ( NEW /aws1/cl_s3cs3tag( iv_key = 'BatchTag' iv_value = 'BatchValue' ) ) ) ) )
          io_report = NEW /aws1/cl_s3cjobreport(
            iv_bucket = lv_report_arn
            iv_format = 'Report_CSV_20180820'
            iv_enabled = abap_true
            iv_prefix = 'batch-reports'
            iv_reportscope = 'AllTasks' )
          iv_priority = 10
          iv_description = iv_job_desc
          iv_confirmationrequired = abap_true ).
        rv_job_id = lo_result->get_jobid( ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex).
        cl_abap_unit_assert=>fail( msg = |Failed to create job: { lo_ex->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.

  METHOD create_job.
    DATA(lv_manifest_arn) = |arn:aws:s3:::{ av_bucket_name }/manifest.csv|.
    DATA(lv_report_arn) = |arn:aws:s3:::{ av_report_bucket }|.
    DATA(lo_manifest) = ao_s3->headobject( iv_bucket = av_bucket_name iv_key = 'manifest.csv' ).
    DATA(lv_etag) = lo_manifest->get_etag( ).
    REPLACE ALL OCCURRENCES OF '"' IN lv_etag WITH ''.
    av_job_id = ao_s3c_actions->create_job(
      iv_account_id = av_account_id
      iv_role_arn = av_role_arn
      iv_manifest_arn = lv_manifest_arn
      iv_manifest_etag = lv_etag
      iv_report_bucket = lv_report_arn ).
    cl_abap_unit_assert=>assert_not_initial( act = av_job_id msg = |Job ID should not be empty| ).
    DATA(lv_ready) = wait_for_job_ready( iv_job_id = av_job_id ).
    cl_abap_unit_assert=>assert_true( act = lv_ready msg = |Job did not become ready in time| ).
  ENDMETHOD.

  METHOD describe_job.
    IF av_job_id IS INITIAL.
      av_job_id = create_batch_job( 'Test job for describe' ).
      wait_for_job_ready( iv_job_id = av_job_id ).
    ENDIF.
    DATA(lo_result) = ao_s3c_actions->describe_job( iv_account_id = av_account_id iv_job_id = av_job_id ).
    cl_abap_unit_assert=>assert_bound( act = lo_result msg = |Result should be bound| ).
    DATA(lo_job) = lo_result->get_job( ).
    cl_abap_unit_assert=>assert_bound( act = lo_job msg = |Job should be bound| ).
    cl_abap_unit_assert=>assert_equals( exp = av_job_id act = lo_job->get_jobid( ) msg = |Job ID should match| ).
  ENDMETHOD.

  METHOD update_job_priority.
    av_job_id_priority = create_batch_job( 'Test job for priority' ).
    DATA(lv_ready) = wait_for_job_ready( iv_job_id = av_job_id_priority ).
    cl_abap_unit_assert=>assert_true( act = lv_ready msg = |Job not ready| ).
    DATA(lo_status) = ao_s3c->describejob( iv_accountid = av_account_id iv_jobid = av_job_id_priority ).
    DATA(lv_stat) = lo_status->get_job( )->get_status( ).
    IF lv_stat <> 'Ready' AND lv_stat <> 'Suspended'.
      cl_abap_unit_assert=>fail( msg = |Job must be in Ready or Suspended state, but is: { lv_stat }| ).
    ENDIF.
    ao_s3c_actions->update_job_priority( iv_account_id = av_account_id iv_job_id = av_job_id_priority iv_priority = 60 ).
    DATA(lo_verify) = ao_s3c->describejob( iv_accountid = av_account_id iv_jobid = av_job_id_priority ).
    cl_abap_unit_assert=>assert_equals( exp = 60 act = lo_verify->get_job( )->get_priority( ) msg = |Priority not updated| ).
  ENDMETHOD.

  METHOD update_job_status.
    av_job_id_status = create_batch_job( 'Test job for status' ).
    DATA(lv_ready) = wait_for_job_ready( iv_job_id = av_job_id_status ).
    cl_abap_unit_assert=>assert_true( act = lv_ready msg = |Job not ready| ).
    DATA(lo_status) = ao_s3c->describejob( iv_accountid = av_account_id iv_jobid = av_job_id_status ).
    DATA(lv_stat) = lo_status->get_job( )->get_status( ).
    IF lv_stat <> 'Ready' AND lv_stat <> 'Suspended' AND lv_stat <> 'Active'.
      cl_abap_unit_assert=>fail( msg = |Job in invalid state: { lv_stat }| ).
    ENDIF.
    ao_s3c_actions->update_job_status( iv_account_id = av_account_id iv_job_id = av_job_id_status
      iv_requested_status = 'Cancelled' ).
    WAIT UP TO 5 SECONDS.
    DATA(lo_verify) = ao_s3c->describejob( iv_accountid = av_account_id iv_jobid = av_job_id_status ).
    DATA(lv_new) = lo_verify->get_job( )->get_status( ).
    cl_abap_unit_assert=>assert_true( act = xsdbool( lv_new = 'Cancelled' OR lv_new = 'Cancelling' )
      msg = |Job should be Cancelled or Cancelling, got: { lv_new }| ).
  ENDMETHOD.

  METHOD get_job_tagging.
    IF av_job_id IS INITIAL.
      av_job_id = create_batch_job( 'Test job for get tagging' ).
      wait_for_job_ready( iv_job_id = av_job_id ).
    ENDIF.
    DATA(lo_result) = ao_s3c_actions->get_job_tagging( iv_account_id = av_account_id iv_job_id = av_job_id ).
    cl_abap_unit_assert=>assert_bound( act = lo_result msg = |Result should be bound| ).
  ENDMETHOD.

  METHOD put_job_tagging.
    av_job_id_tagging = create_batch_job( 'Test job for put tagging' ).
    wait_for_job_ready( iv_job_id = av_job_id_tagging ).
    DATA lt_tags TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
    APPEND NEW /aws1/cl_s3cs3tag( iv_key = 'Environment' iv_value = 'Development' ) TO lt_tags.
    APPEND NEW /aws1/cl_s3cs3tag( iv_key = 'Team' iv_value = 'DataProcessing' ) TO lt_tags.
    ao_s3c_actions->put_job_tagging( iv_account_id = av_account_id iv_job_id = av_job_id_tagging it_tags = lt_tags ).
    DATA(lo_verify) = ao_s3c->getjobtagging( iv_accountid = av_account_id iv_jobid = av_job_id_tagging ).
    cl_abap_unit_assert=>assert_not_initial( act = lo_verify->get_tags( ) msg = |Tags should be set| ).
  ENDMETHOD.

  METHOD list_jobs.
    IF av_job_id IS INITIAL.
      av_job_id = create_batch_job( 'Test job for list' ).
      wait_for_job_ready( iv_job_id = av_job_id ).
    ENDIF.
    DATA lt_statuses TYPE /aws1/cl_s3cjobstatuslist_w=>tt_jobstatuslist.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Active' ) TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Complete' ) TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Cancelled' ) TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Failed' ) TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Ready' ) TO lt_statuses.
    APPEND NEW /aws1/cl_s3cjobstatuslist_w( 'Suspended' ) TO lt_statuses.
    DATA(lo_result) = ao_s3c_actions->list_jobs( iv_account_id = av_account_id it_job_statuses = lt_statuses ).
    cl_abap_unit_assert=>assert_bound( act = lo_result msg = |Result should be bound| ).
    cl_abap_unit_assert=>assert_not_initial( act = lo_result->get_jobs( ) msg = |Should have jobs| ).
  ENDMETHOD.

  METHOD delete_job_tagging.
    IF av_job_id_tagging IS INITIAL.
      av_job_id_tagging = create_batch_job( 'Test job for delete tagging' ).
      wait_for_job_ready( iv_job_id = av_job_id_tagging ).
      DATA lt_tags TYPE /aws1/cl_s3cs3tag=>tt_s3tagset.
      APPEND NEW /aws1/cl_s3cs3tag( iv_key = 'Test' iv_value = 'Value' ) TO lt_tags.
      ao_s3c->putjobtagging( iv_accountid = av_account_id iv_jobid = av_job_id_tagging it_tags = lt_tags ).
    ENDIF.
    ao_s3c_actions->delete_job_tagging( iv_account_id = av_account_id iv_job_id = av_job_id_tagging ).
    DATA(lo_verify) = ao_s3c->getjobtagging( iv_accountid = av_account_id iv_jobid = av_job_id_tagging ).
    cl_abap_unit_assert=>assert_initial( act = lo_verify->get_tags( ) msg = |Tags should be empty| ).
  ENDMETHOD.
ENDCLASS.
