" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_iot_actions DEFINITION DEFERRED.
CLASS /awsex/cl_iot_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_iot_actions.

CLASS ltc_awsex_cl_iot_actions DEFINITION FOR TESTING DURATION SHORT RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    CLASS-DATA ao_iot TYPE REF TO /aws1/if_iot.
    CLASS-DATA ao_iop TYPE REF TO /aws1/if_iop.
    CLASS-DATA ao_session TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_iot_actions TYPE REF TO /awsex/cl_iot_actions.
    CLASS-DATA ao_sns TYPE REF TO /aws1/if_sns.
    CLASS-DATA ao_iam TYPE REF TO /aws1/if_iam.
    CLASS-DATA av_lmd_uuid TYPE string.
    CLASS-DATA av_topic_arn TYPE /aws1/iotawsarn.
    CLASS-DATA av_role_arn TYPE /aws1/iotawsarn.
    CLASS-DATA av_role_name TYPE /aws1/iamrolenametype.

    METHODS: create_thing FOR TESTING RAISING /aws1/cx_rt_generic,
      list_things FOR TESTING RAISING /aws1/cx_rt_generic,
      create_keys_and_cert FOR TESTING RAISING /aws1/cx_rt_generic,
      attach_thing_principal FOR TESTING RAISING /aws1/cx_rt_generic,
      describe_endpoint FOR TESTING RAISING /aws1/cx_rt_generic,
      list_certificates FOR TESTING RAISING /aws1/cx_rt_generic,
      detach_thing_principal FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_certificate FOR TESTING RAISING /aws1/cx_rt_generic,
      create_topic_rule FOR TESTING RAISING /aws1/cx_rt_generic,
      list_topic_rules FOR TESTING RAISING /aws1/cx_rt_generic,
      search_index FOR TESTING RAISING /aws1/cx_rt_generic,
      update_index_config FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_thing FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_topic_rule FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown.

    METHODS get_uuid
      RETURNING
        VALUE(ov_uuid) TYPE string.
ENDCLASS.

CLASS ltc_awsex_cl_iot_actions IMPLEMENTATION.

  METHOD class_setup.
    ao_session = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_iot = /aws1/cl_iot_factory=>create( ao_session ).
    ao_iop = /aws1/cl_iop_factory=>create( ao_session ).
    ao_iot_actions = NEW /awsex/cl_iot_actions( ).
    ao_sns = /aws1/cl_sns_factory=>create( ao_session ).
    ao_iam = /aws1/cl_iam_factory=>create( ao_session ).

    " Use utils function to get random string
    av_lmd_uuid = /awsex/cl_utils=>get_random_string( ).

    " Create SNS topic for testing with tag
    DATA lt_topic_tags TYPE /aws1/cl_snstag=>tt_taglist.
    APPEND NEW /aws1/cl_snstag( iv_key = 'convert_test' iv_value = 'true' ) TO lt_topic_tags.
    DATA(lv_topic_name) = |iot-test-topic-{ av_lmd_uuid }|.

    TRY.
        DATA(lo_create_topic_result) = ao_sns->createtopic( iv_name = lv_topic_name it_tags = lt_topic_tags ).
        av_topic_arn = lo_create_topic_result->get_topicarn( ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_sns_error).
        " Fail test if we cannot create SNS topic
        cl_abap_unit_assert=>fail( msg = |Failed to create SNS topic: { lo_sns_error->get_text( ) }| ).
    ENDTRY.

    " Create IAM role for IoT with all necessary permissions
    av_role_name = |iot-test-role-{ av_lmd_uuid }|.
    DATA(lv_assume_role_policy) = |\{ "Version": "2012-10-17", "Statement": [ \{ "Effect": "Allow", "Principal": \{ "Service": "iot.amazonaws.com" \}, "Action": "sts:AssumeRole" \} ] \}|.
    DATA lt_iam_tags TYPE /aws1/cl_iamtag=>tt_taglisttype.
    APPEND NEW /aws1/cl_iamtag( iv_key = 'convert_test' iv_value = 'true' ) TO lt_iam_tags.

    TRY.
        DATA(lo_create_role_result) = ao_iam->createrole(
          iv_rolename = av_role_name
          iv_assumerolepolicydocument = lv_assume_role_policy
          it_tags = lt_iam_tags ).
        av_role_arn = lo_create_role_result->get_role( )->get_arn( ).
      CATCH /aws1/cx_iamentityalrdyexex.
        " Role already exists from previous failed test, get it
        TRY.
            DATA(lo_get_role_result) = ao_iam->getrole( iv_rolename = av_role_name ).
            av_role_arn = lo_get_role_result->get_role( )->get_arn( ).
          CATCH /aws1/cx_rt_generic INTO DATA(lo_role_error).
            " Fail test if we cannot get role
            cl_abap_unit_assert=>fail( msg = |Failed to get IAM role: { lo_role_error->get_text( ) }| ).
        ENDTRY.
      CATCH /aws1/cx_rt_generic INTO lo_role_error.
        " Fail test if we cannot create role
        cl_abap_unit_assert=>fail( msg = |Failed to create IAM role: { lo_role_error->get_text( ) }| ).
    ENDTRY.

    " Attach comprehensive policy for SNS publish
    DATA(lv_policy_doc) = |\{ "Version": "2012-10-17", "Statement": [ \{ "Effect": "Allow", "Action": [ "sns:Publish", "sns:GetTopicAttributes" ], "Resource": "*" \} ] \}|.
    TRY.
        ao_iam->putrolepolicy(
          iv_rolename = av_role_name
          iv_policyname = 'IoTSNSPublishPolicy'
          iv_policydocument = lv_policy_doc ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_policy_error).
        " Fail test if we cannot attach policy
        cl_abap_unit_assert=>fail( msg = |Failed to attach IAM policy: { lo_policy_error->get_text( ) }| ).
    ENDTRY.

    " Wait for IAM role to propagate (required for IAM resources)
    DATA lv_max_wait_time TYPE i VALUE 30.
    DATA lv_elapsed_time TYPE i VALUE 0.
    DATA lv_role_ready TYPE abap_bool VALUE abap_false.

    " Poll until role is ready or timeout
    WHILE lv_elapsed_time < lv_max_wait_time AND lv_role_ready = abap_false.
      WAIT UP TO 2 SECONDS.
      lv_elapsed_time = lv_elapsed_time + 2.
      TRY.
          " Try to get role to verify it's propagated
          ao_iam->getrole( iv_rolename = av_role_name ).
          lv_role_ready = abap_true.
        CATCH /aws1/cx_rt_generic.
          " Role not ready yet, continue waiting
      ENDTRY.
    ENDWHILE.

    IF lv_role_ready = abap_false.
      cl_abap_unit_assert=>fail( msg = 'IAM role did not propagate within expected time' ).
    ENDIF.
  ENDMETHOD.

  METHOD class_teardown.
    " Clean up SNS topic
    IF av_topic_arn IS NOT INITIAL.
      TRY.
          ao_sns->deletetopic( iv_topicarn = av_topic_arn ).
        CATCH /aws1/cx_rt_generic.
          " Ignore errors during cleanup
      ENDTRY.
    ENDIF.

    " Clean up IAM role
    IF av_role_name IS NOT INITIAL.
      TRY.
          " Delete inline policies first
          ao_iam->deleterolepolicy(
            iv_rolename = av_role_name
            iv_policyname = 'IoTSNSPublishPolicy' ).
        CATCH /aws1/cx_rt_generic.
          " Ignore errors during cleanup
      ENDTRY.
      TRY.
          ao_iam->deleterole( iv_rolename = av_role_name ).
        CATCH /aws1/cx_rt_generic.
          " Ignore errors during cleanup
      ENDTRY.
    ENDIF.

    " Note: All IoT resources are tagged with 'convert_test' for manual cleanup if needed
  ENDMETHOD.

  METHOD get_uuid.
    " Use utils function to get random string
    ov_uuid = /awsex/cl_utils=>get_random_string( ).
  ENDMETHOD.

  METHOD create_thing.
    DATA(lv_uuid) = get_uuid( ).
    DATA(lv_thing_name) = |code-ex-thing-{ lv_uuid }|.

    " Test create_thing operation
    DATA(lo_result) = ao_iot_actions->create_thing( lv_thing_name ).

    " Verify thing was created successfully
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_thingarn( )
      msg = |Thing { lv_thing_name } was not created| ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_thingname( )
      msg = |Thing name should not be empty| ).

    " Clean up
    TRY.
        ao_iot->deletething( iv_thingname = lv_thing_name ).
      CATCH /aws1/cx_rt_generic.
        " Ignore cleanup errors
    ENDTRY.
  ENDMETHOD.

  METHOD list_things.
    DATA(lv_uuid) = get_uuid( ).
    DATA(lv_thing_name) = |code-ex-list-thing-{ lv_uuid }|.

    " Create a thing for listing
    TRY.
        ao_iot->creatething( iv_thingname = lv_thing_name ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_create_error).
        cl_abap_unit_assert=>fail( msg = |Failed to create thing for test: { lo_create_error->get_text( ) }| ).
    ENDTRY.

    " Test list_things operation
    DATA(lo_result) = ao_iot_actions->list_things( ).

    " Verify at least one thing exists
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_things( )
      msg = 'Things list should not be empty' ).

    " Clean up
    TRY.
        ao_iot->deletething( iv_thingname = lv_thing_name ).
      CATCH /aws1/cx_rt_generic.
        " Ignore cleanup errors
    ENDTRY.
  ENDMETHOD.

  METHOD create_keys_and_cert.
    " Test create_keys_and_certificate operation
    DATA(lo_result) = ao_iot_actions->create_keys_and_cert( ).

    " Verify certificate was created successfully
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificateid( )
      msg = 'Certificate ID should not be empty' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificatearn( )
      msg = 'Certificate ARN should not be empty' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificatepem( )
      msg = 'Certificate PEM should not be empty' ).

    " Clean up - need to deactivate and then delete
    DATA(lv_certificate_id) = lo_result->get_certificateid( ).
    TRY.
        ao_iot->updatecertificate(
          iv_certificateid = lv_certificate_id
          iv_newstatus = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = lv_certificate_id ).
      CATCH /aws1/cx_rt_generic.
        " Ignore cleanup errors
    ENDTRY.
  ENDMETHOD.

  METHOD attach_thing_principal.
    DATA(lv_uuid) = get_uuid( ).
    DATA(lv_thing_name) = |code-ex-attach-{ lv_uuid }|.

    " Create thing
    TRY.
        ao_iot->creatething( iv_thingname = lv_thing_name ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_thing_error).
        cl_abap_unit_assert=>fail( msg = |Failed to create thing: { lo_thing_error->get_text( ) }| ).
    ENDTRY.

    " Create certificate
    DATA(lo_cert_result) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
    DATA(lv_certificate_arn) = lo_cert_result->get_certificatearn( ).
    DATA(lv_certificate_id) = lo_cert_result->get_certificateid( ).

    " Test attach_thing_principal operation
    TRY.
        ao_iot_actions->attach_thing_principal(
          iv_thing_name = lv_thing_name
          iv_principal = lv_certificate_arn ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_attach_error).
        " Clean up before failing
        ao_iot->updatecertificate( iv_certificateid = lv_certificate_id iv_newstatus = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = lv_certificate_id ).
        ao_iot->deletething( iv_thingname = lv_thing_name ).
        cl_abap_unit_assert=>fail( msg = |Failed to attach principal: { lo_attach_error->get_text( ) }| ).
    ENDTRY.

    " Verify attachment
    DATA(lo_principals) = ao_iot->listthingprincipals( iv_thingname = lv_thing_name ).
    DATA(lt_principals) = lo_principals->get_principals( ).
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_principals INTO DATA(lo_principal).
      IF lo_principal->get_value( ) = lv_certificate_arn.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Certificate { lv_certificate_arn } should be attached to thing { lv_thing_name }| ).

    " Clean up
    TRY.
        ao_iot->detachthingprincipal(
          iv_thingname = lv_thing_name
          iv_principal = lv_certificate_arn ).
        ao_iot->updatecertificate(
          iv_certificateid = lv_certificate_id
          iv_newstatus = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = lv_certificate_id ).
        ao_iot->deletething( iv_thingname = lv_thing_name ).
      CATCH /aws1/cx_rt_generic.
        " Ignore cleanup errors
    ENDTRY.
  ENDMETHOD.

  METHOD describe_endpoint.
    " Test describe_endpoint operation
    DATA(lo_result) = ao_iot_actions->describe_endpoint( ).

    " Verify endpoint was retrieved
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_endpointaddress( )
      msg = 'Endpoint address should not be empty' ).

    " Verify endpoint format (should contain amazonaws.com)
    DATA(lv_endpoint) = lo_result->get_endpointaddress( ).
    IF lv_endpoint NS 'amazonaws.com' AND lv_endpoint NS 'iot'.
      cl_abap_unit_assert=>fail( msg = |Invalid endpoint format: { lv_endpoint }| ).
    ENDIF.
  ENDMETHOD.

  METHOD list_certificates.
    " Create a test certificate
    TRY.
        DATA(lo_cert_result) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
        DATA(lv_certificate_id) = lo_cert_result->get_certificateid( ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_create_error).
        cl_abap_unit_assert=>fail( msg = |Failed to create certificate: { lo_create_error->get_text( ) }| ).
    ENDTRY.

    " Test list_certificates operation
    DATA(lo_result) = ao_iot_actions->list_certificates( ).

    " Verify at least one certificate exists
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificates( )
      msg = 'Certificates list should not be empty' ).

    " Clean up
    TRY.
        ao_iot->updatecertificate(
          iv_certificateid = lv_certificate_id
          iv_newstatus = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = lv_certificate_id ).
      CATCH /aws1/cx_rt_generic.
        " Ignore cleanup errors
    ENDTRY.
  ENDMETHOD.

  METHOD detach_thing_principal.
    DATA(lv_uuid) = get_uuid( ).
    DATA(lv_thing_name) = |code-ex-detach-{ lv_uuid }|.

    " Create thing
    TRY.
        ao_iot->creatething( iv_thingname = lv_thing_name ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_thing_error).
        cl_abap_unit_assert=>fail( msg = |Failed to create thing: { lo_thing_error->get_text( ) }| ).
    ENDTRY.

    " Create certificate and attach
    DATA(lo_cert_result) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
    DATA(lv_certificate_arn) = lo_cert_result->get_certificatearn( ).
    DATA(lv_certificate_id) = lo_cert_result->get_certificateid( ).

    TRY.
        ao_iot->attachthingprincipal(
          iv_thingname = lv_thing_name
          iv_principal = lv_certificate_arn ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_attach_error).
        ao_iot->updatecertificate( iv_certificateid = lv_certificate_id iv_newstatus = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = lv_certificate_id ).
        ao_iot->deletething( iv_thingname = lv_thing_name ).
        cl_abap_unit_assert=>fail( msg = |Failed to attach principal: { lo_attach_error->get_text( ) }| ).
    ENDTRY.

    " Test detach_thing_principal operation
    TRY.
        ao_iot_actions->detach_thing_principal(
          iv_thing_name = lv_thing_name
          iv_principal = lv_certificate_arn ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_detach_error).
        ao_iot->updatecertificate( iv_certificateid = lv_certificate_id iv_newstatus = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = lv_certificate_id ).
        ao_iot->deletething( iv_thingname = lv_thing_name ).
        cl_abap_unit_assert=>fail( msg = |Failed to detach principal: { lo_detach_error->get_text( ) }| ).
    ENDTRY.

    " Verify detachment
    DATA(lo_principals) = ao_iot->listthingprincipals( iv_thingname = lv_thing_name ).
    DATA(lt_principals) = lo_principals->get_principals( ).

    cl_abap_unit_assert=>assert_initial(
      act = lt_principals
      msg = |Certificate should be detached from thing { lv_thing_name }| ).

    " Clean up
    TRY.
        ao_iot->updatecertificate(
          iv_certificateid = lv_certificate_id
          iv_newstatus = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = lv_certificate_id ).
        ao_iot->deletething( iv_thingname = lv_thing_name ).
      CATCH /aws1/cx_rt_generic.
        " Ignore cleanup errors
    ENDTRY.
  ENDMETHOD.

  METHOD delete_certificate.
    " Create certificate
    TRY.
        DATA(lo_cert_result) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
        DATA(lv_certificate_id) = lo_cert_result->get_certificateid( ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_create_error).
        cl_abap_unit_assert=>fail( msg = |Failed to create certificate: { lo_create_error->get_text( ) }| ).
    ENDTRY.

    " Test delete_certificate operation
    TRY.
        ao_iot_actions->delete_certificate( lv_certificate_id ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_delete_error).
        " Clean up before failing
        TRY.
            ao_iot->updatecertificate( iv_certificateid = lv_certificate_id iv_newstatus = 'INACTIVE' ).
            ao_iot->deletecertificate( iv_certificateid = lv_certificate_id ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
        cl_abap_unit_assert=>fail( msg = |Failed to delete certificate: { lo_delete_error->get_text( ) }| ).
    ENDTRY.

    " Verify deletion
    TRY.
        ao_iot->describecertificate( iv_certificateid = lv_certificate_id ).
        cl_abap_unit_assert=>fail( msg = 'Certificate should have been deleted' ).
      CATCH /aws1/cx_iotresourcenotfoundex.
        " Expected exception - certificate was deleted successfully
    ENDTRY.
  ENDMETHOD.

  METHOD create_topic_rule.
    DATA(lv_uuid) = get_uuid( ).
    DATA(lv_rule_name) = |code_ex_rule_{ lv_uuid }|.

    " Verify prerequisites exist
    IF av_topic_arn IS INITIAL OR av_role_arn IS INITIAL.
      cl_abap_unit_assert=>fail( msg = 'Prerequisites (SNS topic or IAM role) not created in class_setup' ).
    ENDIF.

    " Test create_topic_rule operation
    TRY.
        ao_iot_actions->create_topic_rule(
          iv_rule_name = lv_rule_name
          iv_topic = 'device/+/data'
          iv_sns_action_arn = av_topic_arn
          iv_role_arn = av_role_arn ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_create_error).
        cl_abap_unit_assert=>fail( msg = |Failed to create topic rule: { lo_create_error->get_text( ) }| ).
    ENDTRY.

    " Verify creation
    TRY.
        DATA(lo_rule) = ao_iot->gettopicrule( iv_rulename = lv_rule_name ).
        cl_abap_unit_assert=>assert_not_initial(
          act = lo_rule->get_rule( )
          msg = |Topic rule { lv_rule_name } was not created| ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_get_error).
        ao_iot->deletetopicrule( iv_rulename = lv_rule_name ).
        cl_abap_unit_assert=>fail( msg = |Failed to verify topic rule: { lo_get_error->get_text( ) }| ).
    ENDTRY.

    " Clean up
    TRY.
        ao_iot->deletetopicrule( iv_rulename = lv_rule_name ).
      CATCH /aws1/cx_rt_generic.
        " Ignore cleanup errors
    ENDTRY.
  ENDMETHOD.

  METHOD list_topic_rules.
    DATA(lv_uuid) = get_uuid( ).
    DATA(lv_rule_name) = |code_ex_list_rule_{ lv_uuid }|.

    " Verify prerequisites exist
    IF av_topic_arn IS INITIAL OR av_role_arn IS INITIAL.
      cl_abap_unit_assert=>fail( msg = 'Prerequisites (SNS topic or IAM role) not created in class_setup' ).
    ENDIF.

    " Create a topic rule for listing
    DATA(lv_sql) = |SELECT * FROM 'device/+/data'|.
    DATA(lo_sns_action) = NEW /aws1/cl_iotsnsaction(
      iv_targetarn = av_topic_arn
      iv_rolearn = av_role_arn ).
    DATA lt_actions TYPE /aws1/cl_iotaction=>tt_actionlist.
    DATA(lo_action) = NEW /aws1/cl_iotaction( io_sns = lo_sns_action ).
    APPEND lo_action TO lt_actions.
    DATA(lo_payload) = NEW /aws1/cl_iottopicrulepayload(
      iv_sql = lv_sql
      it_actions = lt_actions ).

    TRY.
        ao_iot->createtopicrule(
          iv_rulename = lv_rule_name
          io_topicrulepayload = lo_payload ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_create_error).
        cl_abap_unit_assert=>fail( msg = |Failed to create topic rule for test: { lo_create_error->get_text( ) }| ).
    ENDTRY.

    " Test list_topic_rules operation
    DATA(lo_result) = ao_iot_actions->list_topic_rules( ).

    " Verify at least one rule exists
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_rules( )
      msg = 'Topic rules list should not be empty' ).

    " Clean up
    TRY.
        ao_iot->deletetopicrule( iv_rulename = lv_rule_name ).
      CATCH /aws1/cx_rt_generic.
        " Ignore cleanup errors
    ENDTRY.
  ENDMETHOD.

  METHOD search_index.
    " First ensure indexing is enabled
    TRY.
        DATA(lo_thing_index_config) = NEW /aws1/cl_iotthingindexingconf(
          iv_thingindexingmode = 'REGISTRY' ).
        ao_iot->updateindexingconfiguration( io_thingindexingconf = lo_thing_index_config ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_config_error).
        " Index might already be configured, continue
    ENDTRY.

    " Wait for indexing configuration to propagate
    DATA lv_max_wait_time TYPE i VALUE 30.
    DATA lv_elapsed_time TYPE i VALUE 0.
    DATA lv_index_ready TYPE abap_bool VALUE abap_false.

    WHILE lv_elapsed_time < lv_max_wait_time AND lv_index_ready = abap_false.
      WAIT UP TO 3 SECONDS.
      lv_elapsed_time = lv_elapsed_time + 3.
      TRY.
          " Try to get indexing configuration to verify it's ready
          DATA(lo_config) = ao_iot->getindexingconfiguration( ).
          IF lo_config->get_thingindexingconf( )->get_thingindexingmode( ) = 'REGISTRY'.
            lv_index_ready = abap_true.
          ENDIF.
        CATCH /aws1/cx_rt_generic.
          " Config not ready yet, continue waiting
      ENDTRY.
    ENDWHILE.

    " Create a thing to search for
    DATA(lv_uuid) = get_uuid( ).
    DATA(lv_thing_name) = |code-ex-search-{ lv_uuid }|.
    TRY.
        ao_iot->creatething( iv_thingname = lv_thing_name ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_thing_error).
        cl_abap_unit_assert=>fail( msg = |Failed to create thing for search test: { lo_thing_error->get_text( ) }| ).
    ENDTRY.

    " Wait for thing to be indexed
    WAIT UP TO 10 SECONDS.

    " Test search_index operation - search for all things
    TRY.
        DATA(lo_result) = ao_iot_actions->search_index( iv_query = '*' ).
        " Should return results or empty list, both are valid
        DATA(lt_things) = lo_result->get_things( ).
      CATCH /aws1/cx_iotindexnotreadyex.
        " Index not ready yet - fail the test as we waited
        ao_iot->deletething( iv_thingname = lv_thing_name ).
        cl_abap_unit_assert=>fail( msg = 'IoT index not ready after waiting' ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_search_error).
        ao_iot->deletething( iv_thingname = lv_thing_name ).
        cl_abap_unit_assert=>fail( msg = |Search index failed: { lo_search_error->get_text( ) }| ).
    ENDTRY.

    " Clean up
    TRY.
        ao_iot->deletething( iv_thingname = lv_thing_name ).
      CATCH /aws1/cx_rt_generic.
        " Ignore cleanup errors
    ENDTRY.
  ENDMETHOD.

  METHOD update_index_config.
    " Test update_indexing_configuration operation
    TRY.
        ao_iot_actions->update_index_config( ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_update_error).
        cl_abap_unit_assert=>fail( msg = |Failed to update indexing configuration: { lo_update_error->get_text( ) }| ).
    ENDTRY.

    " Wait for configuration to propagate
    WAIT UP TO 5 SECONDS.

    " Verify configuration update
    TRY.
        DATA(lo_config) = ao_iot->getindexingconfiguration( ).
        DATA(lv_mode) = lo_config->get_thingindexingconf( )->get_thingindexingmode( ).

        cl_abap_unit_assert=>assert_equals(
          exp = 'REGISTRY'
          act = lv_mode
          msg = 'Thing indexing mode should be REGISTRY' ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_get_error).
        cl_abap_unit_assert=>fail( msg = |Failed to verify indexing configuration: { lo_get_error->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.

  METHOD delete_thing.
    DATA(lv_uuid) = get_uuid( ).
    DATA(lv_thing_name) = |code-ex-del-thing-{ lv_uuid }|.

    " Create thing
    TRY.
        ao_iot->creatething( iv_thingname = lv_thing_name ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_create_error).
        cl_abap_unit_assert=>fail( msg = |Failed to create thing for delete test: { lo_create_error->get_text( ) }| ).
    ENDTRY.

    " Test delete_thing operation
    TRY.
        ao_iot_actions->delete_thing( lv_thing_name ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_delete_error).
        " Clean up before failing
        TRY.
            ao_iot->deletething( iv_thingname = lv_thing_name ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
        cl_abap_unit_assert=>fail( msg = |Failed to delete thing: { lo_delete_error->get_text( ) }| ).
    ENDTRY.

    " Verify deletion
    TRY.
        ao_iot->describething( iv_thingname = lv_thing_name ).
        cl_abap_unit_assert=>fail( msg = 'Thing should have been deleted' ).
      CATCH /aws1/cx_iotresourcenotfoundex.
        " Expected exception - thing was deleted successfully
    ENDTRY.
  ENDMETHOD.

  METHOD delete_topic_rule.
    DATA(lv_uuid) = get_uuid( ).
    DATA(lv_rule_name) = |code_ex_del_rule_{ lv_uuid }|.

    " Verify prerequisites exist
    IF av_topic_arn IS INITIAL OR av_role_arn IS INITIAL.
      cl_abap_unit_assert=>fail( msg = 'Prerequisites (SNS topic or IAM role) not created in class_setup' ).
    ENDIF.

    " Create topic rule
    DATA(lv_sql) = |SELECT * FROM 'device/+/data'|.
    DATA(lo_sns_action) = NEW /aws1/cl_iotsnsaction(
      iv_targetarn = av_topic_arn
      iv_rolearn = av_role_arn ).
    DATA lt_actions TYPE /aws1/cl_iotaction=>tt_actionlist.
    DATA(lo_action) = NEW /aws1/cl_iotaction( io_sns = lo_sns_action ).
    APPEND lo_action TO lt_actions.
    DATA(lo_payload) = NEW /aws1/cl_iottopicrulepayload(
      iv_sql = lv_sql
      it_actions = lt_actions ).

    TRY.
        ao_iot->createtopicrule(
          iv_rulename = lv_rule_name
          io_topicrulepayload = lo_payload ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_create_error).
        cl_abap_unit_assert=>fail( msg = |Failed to create topic rule for delete test: { lo_create_error->get_text( ) }| ).
    ENDTRY.

    " Test delete_topic_rule operation
    TRY.
        ao_iot_actions->delete_topic_rule( lv_rule_name ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_delete_error).
        " Clean up before failing
        TRY.
            ao_iot->deletetopicrule( iv_rulename = lv_rule_name ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
        cl_abap_unit_assert=>fail( msg = |Failed to delete topic rule: { lo_delete_error->get_text( ) }| ).
    ENDTRY.

    " Verify deletion - try to get the rule
    TRY.
        ao_iot->gettopicrule( iv_rulename = lv_rule_name ).
        cl_abap_unit_assert=>fail( msg = 'Topic rule should have been deleted' ).
      CATCH /aws1/cx_rt_generic.
        " Expected - rule was deleted successfully
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
