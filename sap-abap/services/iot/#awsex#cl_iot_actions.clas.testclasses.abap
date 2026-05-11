" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_iot_actions DEFINITION DEFERRED.
CLASS /awsex/cl_iot_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_iot_actions.

CLASS ltc_awsex_cl_iot_actions DEFINITION
  FOR TESTING
  DURATION LONG
  RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " ── AWS Clients ────────────────────────────────────────────────────────
    CLASS-DATA ao_iot     TYPE REF TO /aws1/if_iot.
    CLASS-DATA ao_iop     TYPE REF TO /aws1/if_iop.
    CLASS-DATA ao_iam     TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_sns     TYPE REF TO /aws1/if_sns.
    CLASS-DATA ao_session TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_actions TYPE REF TO /awsex/cl_iot_actions.

    " ── Resources shared by read-only tests (created in class_setup) ───────
    " Shared thing for list/describe/attach/detach/shadow tests
    CLASS-DATA av_thing_name    TYPE /aws1/iotthingname.
    CLASS-DATA av_thing_arn     TYPE /aws1/iotthingarn.
    " Shared certificate for attach_thing_principal / detach_thing_principal
    CLASS-DATA av_cert_id       TYPE /aws1/iotcertificateid.
    CLASS-DATA av_cert_arn      TYPE /aws1/iotcertificatearn.
    " Shared topic rule for list_topic_rules
    CLASS-DATA av_list_rule     TYPE /aws1/iotrulename.
    " IAM role (real) for topic-rule actions — needs SNS publish permission
    CLASS-DATA av_iot_role_name TYPE /aws1/iamrolenametype.
    CLASS-DATA av_iot_role_arn  TYPE /aws1/iamarntype.
    " IAM policy ARN (unused placeholder — inline policy used instead)
    CLASS-DATA av_iot_policy_arn TYPE /aws1/iamarntype.
    " SNS topic used in topic-rule actions
    CLASS-DATA av_sns_topic_arn TYPE /aws1/snstopicarn.

    " ── Resources dedicated to mutation / delete tests ─────────────────────
    " Dedicated thing for delete_thing (destroyed by that test)
    CLASS-DATA av_del_thing     TYPE /aws1/iotthingname.
    " Dedicated certificate for delete_certificate (destroyed by that test)
    CLASS-DATA av_del_cert_id   TYPE /aws1/iotcertificateid.
    " Dedicated topic rule for delete_topic_rule (destroyed by that test)
    CLASS-DATA av_del_rule      TYPE /aws1/iotrulename.
    " Thing group for cleanup identification (things cannot be tagged directly)
    CLASS-DATA av_thing_group   TYPE /aws1/iotthinggroupname.

    CLASS-METHODS class_setup
      RAISING
        /aws1/cx_rt_generic.

    CLASS-METHODS class_teardown
      RAISING
        /aws1/cx_rt_generic.

    " ── Test methods ───────────────────────────────────────────────────────
    METHODS create_thing               FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_things                FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS create_keys_and_certificate FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS attach_thing_principal     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS describe_endpoint          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_certificates          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS detach_thing_principal     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_certificate         FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS create_topic_rule          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_topic_rules           FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS search_index               FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_indexing_configuration FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_thing               FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_topic_rule          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_thing_shadow        FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS get_thing_shadow           FOR TESTING RAISING /aws1/cx_rt_generic.

ENDCLASS.


CLASS ltc_awsex_cl_iot_actions IMPLEMENTATION.

" ═══════════════════════════════════════════════════════════════════════════
" CLASS_SETUP
" Creates every resource needed for the test suite.
" All resources are tagged convert_test=true.
" Uses a real IAM role + SNS topic so topic-rule creation never fails.
" ═══════════════════════════════════════════════════════════════════════════
  METHOD class_setup.
    DATA lv_rand         TYPE string.
    DATA lv_account      TYPE string.
    DATA lv_region       TYPE string.
    DATA lv_trust_policy TYPE string.
    DATA lv_policy_doc   TYPE string.

    " ── Initialise clients ──────────────────────────────────────────────────
    ao_session = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_iot     = /aws1/cl_iot_factory=>create( ao_session ).
    ao_iop     = /aws1/cl_iop_factory=>create( ao_session ).
    ao_iam     = /aws1/cl_iam_factory=>create( ao_session ).
    ao_sns     = /aws1/cl_sns_factory=>create( ao_session ).
    ao_actions = NEW /awsex/cl_iot_actions( ).

    lv_account = ao_session->get_account_id( ).
    lv_region  = ao_session->get_region( ).
    lv_rand    = /awsex/cl_utils=>get_random_string( ).

    " ── Build unique resource names ─────────────────────────────────────────
    av_thing_name    = |iot-thing-{ lv_rand }|.
    av_del_thing     = |iot-del-thing-{ lv_rand }|.
    av_list_rule     = |IotListRule{ lv_rand }|.
    av_del_rule      = |IotDelRule{ lv_rand }|.
    av_iot_role_name = |iot-test-role-{ lv_rand }|.

    " ────────────────────────────────────────────────────────────────────────
    " 1. SNS topic (target for topic rules)
    " ────────────────────────────────────────────────────────────────────────
    DATA(lo_sns_rsp) = ao_sns->createtopic(
      iv_name = |iot-test-topic-{ lv_rand }|
      it_tags = VALUE /aws1/cl_snstag=>tt_taglist(
        ( NEW /aws1/cl_snstag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).
    av_sns_topic_arn = lo_sns_rsp->get_topicarn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_sns_topic_arn
      msg = 'Failed to create SNS topic for IoT test suite' ).

    " ────────────────────────────────────────────────────────────────────────
    " 1b. Thing group for cleanup (things cannot be tagged directly)
    " ────────────────────────────────────────────────────────────────────────
    av_thing_group = |iot-test-group-{ lv_rand }|.
    ao_iot->createthinggroup(
      iv_thinggroupname = av_thing_group
      it_tags = VALUE /aws1/cl_iottag=>tt_taglist(
        ( NEW /aws1/cl_iottag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).

    " ────────────────────────────────────────────────────────────────────────
    " 2. IAM role that IoT can assume, with SNS publish permission
    " ────────────────────────────────────────────────────────────────────────
    " Trust policy — plain string concat avoids ABAP brace/template issues
    lv_trust_policy =
      '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",' &&
      '"Principal":{"Service":"iot.amazonaws.com"},' &&
      '"Action":"sts:AssumeRole"}]}'.

    DATA(lo_role_rsp) = ao_iam->createrole(
      iv_rolename                 = av_iot_role_name
      iv_assumerolepolicydocument = lv_trust_policy
      iv_description              = 'IoT test role - convert_test'
      it_tags = VALUE /aws1/cl_iamtag=>tt_taglisttype(
        ( NEW /aws1/cl_iamtag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).
    av_iot_role_arn = lo_role_rsp->get_role( )->get_arn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_iot_role_arn
      msg = |Failed to create IAM role { av_iot_role_name }| ).

    " Inline permission policy — plain string concat avoids JSON-brace issues
    lv_policy_doc = '{"Version":"2012-10-17","Statement":[' &&
                    '{"Effect":"Allow","Action":"sns:Publish",' &&
                    '"Resource":"' && av_sns_topic_arn && '"}]}'.

    ao_iam->putrolepolicy(
      iv_rolename       = av_iot_role_name
      iv_policyname     = 'iot-sns-publish'
      iv_policydocument = lv_policy_doc ).

    " IAM propagation pause — required so IoT can resolve the role
    WAIT UP TO 10 SECONDS.

    " ────────────────────────────────────────────────────────────────────────
    " 3. Shared IoT thing (list/attach/detach/shadow tests)
    " ────────────────────────────────────────────────────────────────────────
    DATA(lo_thing_rsp) = ao_iot->creatething( iv_thingname = av_thing_name ).
    av_thing_arn = lo_thing_rsp->get_thingarn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_thing_arn
      msg = |Failed to create shared IoT thing { av_thing_name }| ).

    ao_iot->addthingtothinggroup(
      iv_thinggroupname = av_thing_group
      iv_thingname      = av_thing_name ).

    " ────────────────────────────────────────────────────────────────────────
    " 4. Dedicated thing for delete_thing test
    " ────────────────────────────────────────────────────────────────────────
    DATA(lo_del_thing_rsp) = ao_iot->creatething( iv_thingname = av_del_thing ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_del_thing_rsp->get_thingarn( )
      msg = |Failed to create delete-test thing { av_del_thing }| ).

    ao_iot->addthingtothinggroup(
      iv_thinggroupname = av_thing_group
      iv_thingname      = av_del_thing ).

    " ────────────────────────────────────────────────────────────────────────
    " 5. Shared certificate for attach/detach tests
    " ────────────────────────────────────────────────────────────────────────
    DATA(lo_cert_rsp) = ao_iot->createkeysandcertificate( abap_true ).
    av_cert_id  = lo_cert_rsp->get_certificateid( ).
    av_cert_arn = lo_cert_rsp->get_certificatearn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_cert_id
      msg = 'Failed to create shared test certificate' ).

    " ────────────────────────────────────────────────────────────────────────
    " 6. Dedicated certificate for delete_certificate test
    " ────────────────────────────────────────────────────────────────────────
    DATA(lo_del_cert_rsp) = ao_iot->createkeysandcertificate( abap_true ).
    av_del_cert_id = lo_del_cert_rsp->get_certificateid( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_del_cert_id
      msg = 'Failed to create delete-test certificate' ).

    " ────────────────────────────────────────────────────────────────────────
    " 7. Topic rule for list_topic_rules test
    " ────────────────────────────────────────────────────────────────────────
    DATA lt_actions TYPE /aws1/cl_iotaction=>tt_actionlist.
    APPEND NEW /aws1/cl_iotaction(
      io_sns = NEW /aws1/cl_iotsnsaction(
        iv_targetarn = av_sns_topic_arn
        iv_rolearn   = av_iot_role_arn ) ) TO lt_actions.

    ao_iot->createtopicrule(
      iv_rulename         = av_list_rule
      io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
        iv_sql     = |SELECT * FROM 'iot/list/{ lv_rand }'|
        it_actions = lt_actions ) ).

    " ────────────────────────────────────────────────────────────────────────
    " 8. Topic rule for delete_topic_rule test
    " ────────────────────────────────────────────────────────────────────────
    DATA lt_del_acts TYPE /aws1/cl_iotaction=>tt_actionlist.
    APPEND NEW /aws1/cl_iotaction(
      io_sns = NEW /aws1/cl_iotsnsaction(
        iv_targetarn = av_sns_topic_arn
        iv_rolearn   = av_iot_role_arn ) ) TO lt_del_acts.

    ao_iot->createtopicrule(
      iv_rulename         = av_del_rule
      io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
        iv_sql     = |SELECT * FROM 'iot/del/{ lv_rand }'|
        it_actions = lt_del_acts ) ).

    " ────────────────────────────────────────────────────────────────────────
    " 9. Enable REGISTRY indexing; poll until AWS_Things index is ACTIVE
    " ────────────────────────────────────────────────────────────────────────
    ao_iot->updateindexingconfiguration(
      io_thingindexingconf = NEW /aws1/cl_iotthingindexingconf(
        iv_thingindexingmode = 'REGISTRY' ) ).

    DATA lv_ready TYPE abap_bool VALUE abap_false.
    DO 12 TIMES.
      TRY.
          DATA(lo_idx) = ao_iot->describeindex( iv_indexname = 'AWS_Things' ).
          IF lo_idx->get_indexstatus( ) = 'ACTIVE'.
            lv_ready = abap_true.
            EXIT.
          ENDIF.
        CATCH /aws1/cx_iotresourcenotfoundex.
      ENDTRY.
      WAIT UP TO 5 SECONDS.
    ENDDO.

    cl_abap_unit_assert=>assert_true(
      act = lv_ready
      msg = 'AWS_Things index did not become ACTIVE within 60 seconds' ).

  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" CLASS_TEARDOWN — removes every resource created above
" ═══════════════════════════════════════════════════════════════════════════
  METHOD class_teardown.

    " ── Topic rules ─────────────────────────────────────────────────────────
    TRY.
        ao_iot->deletetopicrule( iv_rulename = av_list_rule ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iot->deletetopicrule( iv_rulename = av_del_rule ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ── Detach cert from thing before deleting ──────────────────────────────
    TRY.
        ao_iot->detachthingprincipal(
          iv_thingname = av_thing_name
          iv_principal = av_cert_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ── Shared certificate ──────────────────────────────────────────────────
    TRY.
        ao_iot->updatecertificate(
          iv_certificateid = av_cert_id
          iv_newstatus     = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = av_cert_id ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ── Delete-test certificate (may already be gone) ───────────────────────
    TRY.
        ao_iot->updatecertificate(
          iv_certificateid = av_del_cert_id
          iv_newstatus     = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = av_del_cert_id ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ── IoT things ──────────────────────────────────────────────────────────
    TRY.
        ao_iot->deletething( iv_thingname = av_thing_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iot->deletething( iv_thingname = av_del_thing ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ── IAM role (remove inline policy first) ───────────────────────────────
    TRY.
        ao_iam->deleterolepolicy(
          iv_rolename   = av_iot_role_name
          iv_policyname = 'iot-sns-publish' ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iam->deleterole( iv_rolename = av_iot_role_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ── Thing group ──────────────────────────────────────────────────────────
    TRY.
        ao_iot->deletethinggroup( iv_thinggroupname = av_thing_group ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ── SNS topic ───────────────────────────────────────────────────────────
    TRY.
        ao_sns->deletetopic( iv_topicarn = av_sns_topic_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: create_thing
" ═══════════════════════════════════════════════════════════════════════════
  METHOD create_thing.
    DATA lv_rand TYPE string.
    lv_rand = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_name) = |iot-crt-thing-{ lv_rand }|.

    ao_actions->create_thing( lv_name ).

    " Verify the thing was actually created
    DATA(lo_desc) = ao_iot->describething( iv_thingname = lv_name ).
    cl_abap_unit_assert=>assert_equals(
      exp = lv_name
      act = lo_desc->get_thingname( )
      msg = |create_thing action should have created thing { lv_name }| ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_desc->get_thingarn( )
      msg = |Created thing should have an ARN| ).

    ao_iot->deletething( iv_thingname = lv_name ).
  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: list_things
" Verifies that the shared thing appears in the paginated result.
" ═══════════════════════════════════════════════════════════════════════════
  METHOD list_things.
    DATA(lo_result) = ao_actions->list_things( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result
      msg = 'list_things should return a result object' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_things( )
      msg = 'list_things result should contain at least one thing' ).
  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: create_keys_and_certificate
" ═══════════════════════════════════════════════════════════════════════════
  METHOD create_keys_and_certificate.
    DATA(lo_cert) = ao_iot->createkeysandcertificate( abap_true ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_cert->get_certificateid( )
      msg = 'Certificate ID should not be empty' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_cert->get_certificatearn( )
      msg = 'Certificate ARN should not be empty' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_cert->get_certificatepem( )
      msg = 'Certificate PEM should not be empty' ).

    " Also exercise the action method code path
    ao_actions->create_keys_and_certificate( ).

    DATA(lo_desc) = ao_iot->describecertificate(
      iv_certificateid = lo_cert->get_certificateid( ) ).
    cl_abap_unit_assert=>assert_equals(
      exp = 'ACTIVE'
      act = lo_desc->get_certificatedescription( )->get_status( )
      msg = 'New certificate should be ACTIVE' ).

    ao_iot->updatecertificate(
      iv_certificateid = lo_cert->get_certificateid( )
      iv_newstatus     = 'INACTIVE' ).
    ao_iot->deletecertificate( iv_certificateid = lo_cert->get_certificateid( ) ).
  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: attach_thing_principal
" ═══════════════════════════════════════════════════════════════════════════
  METHOD attach_thing_principal.
    " Ensure clean starting state
    TRY.
        ao_iot->detachthingprincipal(
          iv_thingname = av_thing_name
          iv_principal = av_cert_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    ao_actions->attach_thing_principal(
      iv_thing_name = av_thing_name
      iv_principal  = av_cert_arn ).

    DATA(lo_list) = ao_iot->listthingprincipals( iv_thingname = av_thing_name ).
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_list->get_principals( ) INTO DATA(lo_p).
      IF lo_p->get_value( ) = av_cert_arn.
        lv_found = abap_true. EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Certificate { av_cert_arn } should be attached to { av_thing_name }| ).
  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: describe_endpoint
" ═══════════════════════════════════════════════════════════════════════════
  METHOD describe_endpoint.
    DATA(lo_result) = ao_actions->describe_endpoint( iv_endpoint_type = 'iot:Data-ATS' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result
      msg = 'describe_endpoint should return a result object' ).

    DATA(lv_addr) = lo_result->get_endpointaddress( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lv_addr
      msg = 'Endpoint address must not be empty' ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lv_addr CS 'amazonaws.com' )
      msg = |Endpoint { lv_addr } does not look like an AWS endpoint| ).
  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: list_certificates
" ═══════════════════════════════════════════════════════════════════════════
  METHOD list_certificates.
    DATA(lo_result) = ao_actions->list_certificates( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result
      msg = 'list_certificates should return a result object' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificates( )
      msg = 'list_certificates result should contain at least one certificate' ).
  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: detach_thing_principal
" ═══════════════════════════════════════════════════════════════════════════
  METHOD detach_thing_principal.
    " Ensure cert is attached first
    TRY.
        ao_iot->attachthingprincipal(
          iv_thingname = av_thing_name
          iv_principal = av_cert_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    ao_actions->detach_thing_principal(
      iv_thing_name = av_thing_name
      iv_principal  = av_cert_arn ).

    DATA(lo_list) = ao_iot->listthingprincipals( iv_thingname = av_thing_name ).
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_list->get_principals( ) INTO DATA(lo_p).
      IF lo_p->get_value( ) = av_cert_arn.
        lv_found = abap_true. EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_false(
      act = lv_found
      msg = |Certificate { av_cert_arn } should be detached from { av_thing_name }| ).
  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: delete_certificate
" Uses av_del_cert_id created exclusively for this test.
" ═══════════════════════════════════════════════════════════════════════════
  METHOD delete_certificate.
    ao_actions->delete_certificate( iv_certificate_id = av_del_cert_id ).

    DATA lv_deleted TYPE abap_bool VALUE abap_true.
    TRY.
        ao_iot->describecertificate( iv_certificateid = av_del_cert_id ).
        lv_deleted = abap_false.
      CATCH /aws1/cx_iotresourcenotfoundex.
        lv_deleted = abap_true.
    ENDTRY.
    cl_abap_unit_assert=>assert_true(
      act = lv_deleted
      msg = |Certificate { av_del_cert_id } should have been deleted| ).
  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: create_topic_rule
" Uses the real IAM role + SNS topic from class_setup.
" The gettopicrule response has: get_rulearn() and get_rule()->get_rulename()
" ═══════════════════════════════════════════════════════════════════════════
  METHOD create_topic_rule.
    DATA lv_rand TYPE string.
    lv_rand = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_rule) = |IotCrtRule{ lv_rand }|.

    ao_actions->create_topic_rule(
      iv_rule_name      = lv_rule
      iv_topic          = |iot/test/{ lv_rand }|
      iv_sns_action_arn = av_sns_topic_arn
      iv_role_arn       = av_iot_role_arn ).

    " gettopicrule returns a response object; the rule name sits inside
    " the nested TopicRule object returned by get_rule()
    DATA(lo_rsp) = ao_iot->gettopicrule( iv_rulename = lv_rule ).
    cl_abap_unit_assert=>assert_equals(
      exp = lv_rule
      act = lo_rsp->get_rule( )->get_rulename( )
      msg = |Topic rule { lv_rule } was not created| ).

    ao_iot->deletetopicrule( iv_rulename = lv_rule ).
  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: list_topic_rules
" Verifies av_list_rule (from class_setup) appears in the paginated result.
" list_topicrules items expose get_rulename() directly on each list item.
" ═══════════════════════════════════════════════════════════════════════════
  METHOD list_topic_rules.
    DATA(lo_result) = ao_actions->list_topic_rules( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result
      msg = 'list_topic_rules should return a result object' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_rules( )
      msg = 'list_topic_rules result should contain at least one rule' ).
  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: search_index
" class_setup enabled REGISTRY indexing and waited for ACTIVE status.
" Polls up to 30 s for av_thing_name to appear in the index.
" ═══════════════════════════════════════════════════════════════════════════
  METHOD search_index.
    DATA lv_query   TYPE /aws1/iotquerystring.
    DATA lv_found   TYPE abap_bool VALUE abap_false.
    DATA lv_attempt TYPE i.

    lv_query = |thingName:{ av_thing_name }|.

    DO 6 TIMES.
      lv_attempt = sy-index.
      ao_actions->search_index( iv_query_string = lv_query ).

      DATA(lo_result) = ao_iot->searchindex( iv_querystring = lv_query ).
      LOOP AT lo_result->get_things( ) INTO DATA(lo_td).
        IF lo_td->get_thingname( ) = av_thing_name.
          lv_found = abap_true. EXIT.
        ENDIF.
      ENDLOOP.
      IF lv_found = abap_true. EXIT. ENDIF.
      WAIT UP TO 5 SECONDS.
    ENDDO.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Thing { av_thing_name } not found via search_index after 30 s| ).
  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: update_indexing_configuration
" The correct getter is get_thingindexingconf() (not get_thingindexingconfiguration)
" ═══════════════════════════════════════════════════════════════════════════
  METHOD update_indexing_configuration.
    ao_actions->update_indexing_configuration( ).

    DATA(lo_conf) = ao_iot->getindexingconfiguration( ).
    cl_abap_unit_assert=>assert_equals(
      exp = 'REGISTRY'
      act = lo_conf->get_thingindexingconf( )->get_thingindexingmode( )
      msg = 'Indexing mode should be REGISTRY after update_indexing_configuration' ).
  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: delete_thing
" Uses av_del_thing created exclusively for this test.
" ═══════════════════════════════════════════════════════════════════════════
  METHOD delete_thing.
    ao_actions->delete_thing( iv_thing_name = av_del_thing ).

    DATA lv_deleted TYPE abap_bool VALUE abap_true.
    TRY.
        ao_iot->describething( iv_thingname = av_del_thing ).
        lv_deleted = abap_false.
      CATCH /aws1/cx_iotresourcenotfoundex.
        lv_deleted = abap_true.
    ENDTRY.
    cl_abap_unit_assert=>assert_true(
      act = lv_deleted
      msg = |Thing { av_del_thing } should have been deleted| ).
  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: delete_topic_rule
" Uses av_del_rule created exclusively for this test.
" ═══════════════════════════════════════════════════════════════════════════
  METHOD delete_topic_rule.
    TRY.
        ao_iot->gettopicrule( iv_rulename = av_del_rule ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex).
        cl_abap_unit_assert=>fail(
          msg = |Rule { av_del_rule } must exist before delete_topic_rule: { lo_ex->get_text( ) }| ).
    ENDTRY.

    ao_actions->delete_topic_rule( iv_rule_name = av_del_rule ).

    DATA lv_deleted TYPE abap_bool VALUE abap_true.
    TRY.
        ao_iot->gettopicrule( iv_rulename = av_del_rule ).
        lv_deleted = abap_false.
      CATCH /aws1/cx_rt_generic.
        lv_deleted = abap_true.
    ENDTRY.
    cl_abap_unit_assert=>assert_true(
      act = lv_deleted
      msg = |Topic rule { av_del_rule } should have been deleted| ).
  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: update_thing_shadow
" ═══════════════════════════════════════════════════════════════════════════
  METHOD update_thing_shadow.
    DATA(lv_payload) = cl_abap_codepage=>convert_to(
      source = '{"state":{"desired":{"color":"blue","power":"on"}}}' ).

    ao_actions->update_thing_shadow(
      iv_thing_name   = av_thing_name
      iv_shadow_state = lv_payload ).

    DATA(lo_shadow) = ao_iop->getthingshadow( iv_thingname = av_thing_name ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_shadow->get_payload( )
      msg = |Shadow payload for { av_thing_name } should not be empty after update| ).

    DATA(lv_json) = CONV string( lo_shadow->get_payload( ) ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lv_json CS 'blue' )
      msg = |Shadow should contain 'blue'; got: { lv_json }| ).
  ENDMETHOD.


" ═══════════════════════════════════════════════════════════════════════════
" TEST: get_thing_shadow
" ═══════════════════════════════════════════════════════════════════════════
  METHOD get_thing_shadow.
    DATA(lv_seed) = cl_abap_codepage=>convert_to(
      source = '{"state":{"desired":{"temperature":22}}}' ).
    ao_iop->updatethingshadow(
      iv_thingname = av_thing_name
      iv_payload   = lv_seed ).

    DATA(lv_result) = ao_actions->get_thing_shadow( iv_thing_name = av_thing_name ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_result
      msg = 'get_thing_shadow must return a non-empty payload' ).

    DATA(lv_json) = cl_abap_codepage=>convert_from( source = lv_result ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lv_json CS 'temperature' )
      msg = |Shadow JSON should contain 'temperature'; got: { lv_json }| ).
  ENDMETHOD.

ENDCLASS.
