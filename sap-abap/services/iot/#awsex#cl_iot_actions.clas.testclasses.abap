" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_iot_actions DEFINITION DEFERRED.
CLASS /awsex/cl_iot_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_iot_actions.

CLASS ltc_awsex_cl_iot_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " Service clients
    CLASS-DATA ao_session     TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_iot         TYPE REF TO /aws1/if_iot.
    CLASS-DATA ao_iop         TYPE REF TO /aws1/if_iop.
    CLASS-DATA ao_iam         TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_sns         TYPE REF TO /aws1/if_sns.
    CLASS-DATA ao_iot_actions TYPE REF TO /awsex/cl_iot_actions.

    " -------------------------------------------------------------------
    " Shared read-only resources (created once, never mutated by tests)
    " -------------------------------------------------------------------
    " IoT thing used by: list_things, attach/detach, update/get shadow
    CLASS-DATA av_thing_name     TYPE /aws1/iotthingname.
    CLASS-DATA av_thing_arn      TYPE /aws1/iotthingarn.

    " Certificate used by: attach_thing_principal, detach_thing_principal,
    "                      list_certificates
    CLASS-DATA av_cert_id        TYPE /aws1/iotcertificateid.
    CLASS-DATA av_cert_arn       TYPE /aws1/iotcertificatearn.

    " IAM role with iot.amazonaws.com trust + IoT-to-SNS publish policy
    CLASS-DATA av_role_arn       TYPE /aws1/iotrolearn.
    CLASS-DATA av_role_name      TYPE /aws1/iamrolenametype.

    " SNS topic for the topic-rule action target
    CLASS-DATA av_sns_topic_arn  TYPE /aws1/iotsnstopicarn.
    CLASS-DATA av_sns_topic_name TYPE /aws1/snstopicname.

    " Topic rule used by: list_topic_rules
    CLASS-DATA av_rule_name      TYPE /aws1/iotrulename.

    " -------------------------------------------------------------------
    " Dedicated resources consumed by destructive tests
    " -------------------------------------------------------------------
    " delete_thing test
    CLASS-DATA av_del_thing_name TYPE /aws1/iotthingname.

    " delete_certificate test – own cert, never attached to shared thing
    CLASS-DATA av_del_cert_id    TYPE /aws1/iotcertificateid.
    CLASS-DATA av_del_cert_arn   TYPE /aws1/iotcertificatearn.

    " delete_topic_rule test
    CLASS-DATA av_del_rule_name  TYPE /aws1/iotrulename.

    " -------------------------------------------------------------------
    " Test methods
    " -------------------------------------------------------------------
    METHODS create_thing               FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_things                FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS create_keys_and_cert       FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS attach_thing_principal     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS describe_endpoint          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_certificates          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS detach_thing_principal     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_certificate         FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS create_topic_rule          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_topic_rules           FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_indexing_conf       FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS search_index               FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_thing               FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_topic_rule          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_thing_shadow        FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS get_thing_shadow           FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " Helper: tag an IoT resource by ARN
    CLASS-METHODS tag_iot_resource
      IMPORTING
        iv_resource_arn TYPE /aws1/iotresourcearn
      RAISING
        /aws1/cx_rt_generic.

    " Helper: build a standard topic-rule payload pointing to av_sns_topic_arn
    CLASS-METHODS make_rule_payload
      IMPORTING
        iv_topic   TYPE /aws1/iottopic
      RETURNING
        VALUE(oo_payload) TYPE REF TO /aws1/cl_iottopicrulepayload.

ENDCLASS.

CLASS ltc_awsex_cl_iot_actions IMPLEMENTATION.

* ======================================================================
* class_setup – create ALL resources needed by the test suite
* ======================================================================
  METHOD class_setup.
    DATA lv_uuid         TYPE string.
    DATA lv_account      TYPE string.
    DATA lv_region       TYPE string.
    DATA lv_trust_policy TYPE string.
    DATA lv_iot_policy   TYPE string.

    ao_session     = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_iot         = /aws1/cl_iot_factory=>create( ao_session ).
    ao_iop         = /aws1/cl_iop_factory=>create( ao_session ).
    ao_iam         = /aws1/cl_iam_factory=>create( ao_session ).
    ao_sns         = /aws1/cl_sns_factory=>create( ao_session ).
    ao_iot_actions = NEW /awsex/cl_iot_actions( ).

    lv_account = ao_session->get_account_id( ).
    lv_region  = ao_session->get_region( ).
    lv_uuid    = /awsex/cl_utils=>get_random_string( ).

    " ----------------------------------------------------------------
    " Resource names  (keep rule names alphanumeric-only, ≤128 chars)
    " ----------------------------------------------------------------
    av_thing_name    = |sap-abap-iot-thing-{ lv_uuid }|.
    av_del_thing_name = |sap-abap-iot-del-{ lv_uuid }|.
    av_role_name     = |sap-abap-iot-role-{ lv_uuid }|.
    av_sns_topic_name = |sap-abap-iot-topic-{ lv_uuid }|.
    av_rule_name     = |sapabapiotrule{ lv_uuid }|.
    av_del_rule_name = |sapabapiotdel{ lv_uuid }|.

    " ----------------------------------------------------------------
    " 1.  IAM role  (iot.amazonaws.com trust + SNS publish inline policy)
    " ----------------------------------------------------------------
    lv_trust_policy =
      '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",' &&
      '"Principal":{"Service":"iot.amazonaws.com"},' &&
      '"Action":"sts:AssumeRole"}]}'.

    lv_iot_policy =
      '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",' &&
      '"Action":"sns:Publish","Resource":"*"}]}'.

    DATA(lo_role_rsp) = ao_iam->createrole(
      iv_rolename                 = av_role_name
      iv_assumerolepolicydocument = lv_trust_policy
      iv_description              = 'SAP ABAP IoT convert_test role'
      it_tags = VALUE /aws1/cl_iamtag=>tt_taglisttype(
        ( NEW /aws1/cl_iamtag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).

    av_role_arn = lo_role_rsp->get_role( )->get_arn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_role_arn
      msg = 'Failed to create IAM role for IoT tests' ).

    " Attach inline policy so the rule can publish to SNS
    ao_iam->putrolepolicy(
      iv_rolename      = av_role_name
      iv_policyname    = 'sap-abap-iot-sns-publish'
      iv_policydocument = lv_iot_policy ).

    " IAM propagation delay
    WAIT UP TO 10 SECONDS.

    " ----------------------------------------------------------------
    " 2.  SNS topic  (tagged, used as topic-rule action target)
    " ----------------------------------------------------------------
    DATA(lo_sns_rsp) = ao_sns->createtopic(
      iv_name = av_sns_topic_name
      it_tags = VALUE /aws1/cl_snstag=>tt_taglist(
        ( NEW /aws1/cl_snstag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).
    av_sns_topic_arn = lo_sns_rsp->get_topicarn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_sns_topic_arn
      msg = 'Failed to create SNS topic for IoT tests' ).

    " ----------------------------------------------------------------
    " 3.  Shared IoT thing  (tagged)
    " ----------------------------------------------------------------
    DATA(lo_thing_rsp) = ao_iot->creatething( iv_thingname = av_thing_name ).
    av_thing_arn = lo_thing_rsp->get_thingarn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_thing_arn
      msg = |Failed to create IoT thing { av_thing_name }| ).

    tag_iot_resource( av_thing_arn ).

    " ----------------------------------------------------------------
    " 4.  Shared certificate  (tagged via resource ARN)
    " ----------------------------------------------------------------
    DATA(lo_cert_rsp) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
    av_cert_id  = lo_cert_rsp->get_certificateid( ).
    av_cert_arn = lo_cert_rsp->get_certificatearn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_cert_id
      msg = 'Failed to create shared certificate' ).

    tag_iot_resource( av_cert_arn ).

    " Attach cert to shared thing – used by attach/detach tests
    ao_iot->attachthingprincipal(
      iv_thingname = av_thing_name
      iv_principal = av_cert_arn ).

    " ----------------------------------------------------------------
    " 5.  Dedicated delete-cert  (its own cert, NOT attached to any thing)
    " ----------------------------------------------------------------
    DATA(lo_del_cert) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
    av_del_cert_id  = lo_del_cert->get_certificateid( ).
    av_del_cert_arn = lo_del_cert->get_certificatearn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_del_cert_id
      msg = 'Failed to create delete-cert' ).
    tag_iot_resource( av_del_cert_arn ).

    " ----------------------------------------------------------------
    " 6.  Dedicated delete-thing  (tagged, no cert attached)
    " ----------------------------------------------------------------
    DATA(lo_del_thing) = ao_iot->creatething( iv_thingname = av_del_thing_name ).
    tag_iot_resource( lo_del_thing->get_thingarn( ) ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_del_thing->get_thingarn( )
      msg = |Failed to create delete-thing { av_del_thing_name }| ).

    " ----------------------------------------------------------------
    " 7.  Shared topic rule used by list_topic_rules test
    " ----------------------------------------------------------------
    ao_iot->createtopicrule(
      iv_rulename         = av_rule_name
      io_topicrulepayload = make_rule_payload( 'shared/topic' ) ).

    " ----------------------------------------------------------------
    " 8.  Dedicated delete-rule  (for delete_topic_rule test)
    " ----------------------------------------------------------------
    ao_iot->createtopicrule(
      iv_rulename         = av_del_rule_name
      io_topicrulepayload = make_rule_payload( 'delete/topic' ) ).

    " ----------------------------------------------------------------
    " 9.  Enable REGISTRY indexing so search_index works
    " ----------------------------------------------------------------
    ao_iot->updateindexingconfiguration(
      io_thingindexingconf = NEW /aws1/cl_iotthingindexingconf(
        iv_thingindexingmode = 'REGISTRY' ) ).

    " ----------------------------------------------------------------
    " 10. Seed shadow on shared thing (iop)
    " ----------------------------------------------------------------
    ao_iop->updatethingshadow(
      iv_thingname = av_thing_name
      iv_payload   = '{"state":{"reported":{"convert_test":true}}}' ).

  ENDMETHOD.

* ======================================================================
* class_teardown – clean up every resource created in class_setup
* ======================================================================
  METHOD class_teardown.

    " ---- topic rules (shared + delete-rule if not already deleted) ----
    TRY.
        ao_iot->deletetopicrule( iv_rulename = av_rule_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iot->deletetopicrule( iv_rulename = av_del_rule_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ---- shared cert: detach, deactivate, delete -----
    TRY.
        ao_iot->detachthingprincipal(
          iv_thingname = av_thing_name
          iv_principal = av_cert_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iot->updatecertificate(
          iv_certificateid = av_cert_id
          iv_newstatus     = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = av_cert_id ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ---- del-cert (may already be deleted by the test) ----
    TRY.
        ao_iot->updatecertificate(
          iv_certificateid = av_del_cert_id
          iv_newstatus     = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = av_del_cert_id ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ---- shared thing ----
    TRY.
        ao_iot->deletething( iv_thingname = av_thing_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ---- del-thing (may already be deleted by the test) ----
    TRY.
        ao_iot->deletething( iv_thingname = av_del_thing_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ---- SNS topic ----
    TRY.
        ao_sns->deletetopic( iv_topicarn = av_sns_topic_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ---- IAM role: delete inline policy first, then role ----
    TRY.
        ao_iam->deleterolepolicy(
          iv_rolename  = av_role_name
          iv_policyname = 'sap-abap-iot-sns-publish' ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iam->deleterole( iv_rolename = av_role_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

  ENDMETHOD.

* ======================================================================
* Helpers
* ======================================================================
  METHOD tag_iot_resource.
    DATA lt_tags TYPE /aws1/cl_iottag=>tt_taglist.
    APPEND NEW /aws1/cl_iottag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_tags.
    ao_iot->tagresource(
      iv_resourcearn = iv_resource_arn
      it_tags        = lt_tags ).
  ENDMETHOD.

  METHOD make_rule_payload.
    DATA(lo_sns_action) = NEW /aws1/cl_iotsnsaction(
      iv_targetarn = av_sns_topic_arn
      iv_rolearn   = av_role_arn ).
    DATA(lo_action) = NEW /aws1/cl_iotaction( io_sns = lo_sns_action ).
    DATA lt_actions TYPE /aws1/cl_iotaction=>tt_actionlist.
    APPEND lo_action TO lt_actions.
    oo_payload = NEW /aws1/cl_iottopicrulepayload(
      iv_sql     = |SELECT * FROM '{ iv_topic }'|
      it_actions = lt_actions ).
  ENDMETHOD.

* ======================================================================
* Test: create_thing
* ======================================================================
  METHOD create_thing.
    " Fresh thing per test – no dependency on shared resources
    DATA(lv_name) = |sap-abap-iot-cre-{ /awsex/cl_utils=>get_random_string( ) }|.

    DATA lo_result TYPE REF TO /aws1/cl_iotcreatethingrsp.
    ao_iot_actions->create_thing(
      EXPORTING iv_thing_name = lv_name
      IMPORTING oo_result     = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'create_thing: result must be bound' ).
    cl_abap_unit_assert=>assert_equals(
      exp = lv_name
      act = lo_result->get_thingname( )
      msg = 'create_thing: thing name mismatch' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_thingarn( )
      msg = 'create_thing: ARN must not be empty' ).

    " Tag & clean up
    tag_iot_resource( lo_result->get_thingarn( ) ).
    ao_iot->deletething( iv_thingname = lv_name ).
  ENDMETHOD.

* ======================================================================
* Test: list_things
* ======================================================================
  METHOD list_things.
    DATA lo_result TYPE REF TO /aws1/cl_iotlistthingsresponse.
    ao_iot_actions->list_things( IMPORTING oo_result = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_things: result must be bound' ).

    " The shared thing created in class_setup must appear in the list
    DATA(lv_found) = abap_false.
    LOOP AT lo_result->get_things( ) INTO DATA(lo_thing).
      IF lo_thing->get_thingname( ) = av_thing_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_things: shared thing { av_thing_name } not found| ).
  ENDMETHOD.

* ======================================================================
* Test: create_keys_and_certificate
* ======================================================================
  METHOD create_keys_and_cert.
    DATA lo_result TYPE REF TO /aws1/cl_iotcrekeysandcertrsp.
    ao_iot_actions->create_keys_and_certificate(
      IMPORTING oo_result = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'create_keys_and_cert: result must be bound' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificateid( )
      msg = 'create_keys_and_cert: certificate ID must not be empty' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificatearn( )
      msg = 'create_keys_and_cert: certificate ARN must not be empty' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificatepem( )
      msg = 'create_keys_and_cert: PEM must not be empty' ).

    " Tag & clean up the freshly created certificate
    DATA(lv_new_id) = lo_result->get_certificateid( ).
    tag_iot_resource( lo_result->get_certificatearn( ) ).
    ao_iot->updatecertificate(
      iv_certificateid = lv_new_id
      iv_newstatus     = 'INACTIVE' ).
    ao_iot->deletecertificate( iv_certificateid = lv_new_id ).
  ENDMETHOD.

* ======================================================================
* Test: attach_thing_principal
* Uses shared thing + shared cert.  Detaches first to make the test
* deterministic, then calls the action, then verifies & restores.
* ======================================================================
  METHOD attach_thing_principal.
    " Ensure cert is detached before the test
    TRY.
        ao_iot->detachthingprincipal(
          iv_thingname = av_thing_name
          iv_principal = av_cert_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    ao_iot_actions->attach_thing_principal(
      iv_thing_name = av_thing_name
      iv_principal  = av_cert_arn ).

    " Verify: cert ARN must appear in the thing's principals list
    DATA(lo_princ_rsp) = ao_iot->listthingprincipals(
      iv_thingname = av_thing_name ).
    DATA(lv_found) = abap_false.
    LOOP AT lo_princ_rsp->get_principals( ) INTO DATA(lo_p).
      IF lo_p->get_value( ) = av_cert_arn.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |attach_thing_principal: cert { av_cert_arn } not found in principals| ).
  ENDMETHOD.

* ======================================================================
* Test: describe_endpoint
* ======================================================================
  METHOD describe_endpoint.
    DATA lv_addr TYPE /aws1/iotendpointaddress.
    ao_iot_actions->describe_endpoint(
      IMPORTING ov_endpoint_addr = lv_addr ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_addr
      msg = 'describe_endpoint: address must not be empty' ).
    " Address should contain "amazonaws.com"
    cl_abap_unit_assert=>assert_char_cp(
      act = lv_addr
      exp = '*amazonaws.com*'
      msg = 'describe_endpoint: address should be an AWS endpoint' ).
  ENDMETHOD.

* ======================================================================
* Test: list_certificates
* ======================================================================
  METHOD list_certificates.
    DATA lo_result TYPE REF TO /aws1/cl_iotlistcertsresponse.
    ao_iot_actions->list_certificates( IMPORTING oo_result = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_certificates: result must be bound' ).

    " The shared cert created in class_setup must appear
    DATA(lv_found) = abap_false.
    LOOP AT lo_result->get_certificates( ) INTO DATA(lo_cert).
      IF lo_cert->get_certificateid( ) = av_cert_id.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_certificates: cert { av_cert_id } not found| ).
  ENDMETHOD.

* ======================================================================
* Test: detach_thing_principal
* Ensures attached first, calls the action, verifies, then re-attaches
* so class_teardown can clean up properly.
* ======================================================================
  METHOD detach_thing_principal.
    " Guarantee cert is attached before the test
    TRY.
        ao_iot->attachthingprincipal(
          iv_thingname = av_thing_name
          iv_principal = av_cert_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    ao_iot_actions->detach_thing_principal(
      iv_thing_name = av_thing_name
      iv_principal  = av_cert_arn ).

    " Verify: cert ARN must NO LONGER appear in the thing's principals list
    DATA(lo_princ_rsp) = ao_iot->listthingprincipals(
      iv_thingname = av_thing_name ).
    DATA(lv_found) = abap_false.
    LOOP AT lo_princ_rsp->get_principals( ) INTO DATA(lo_p).
      IF lo_p->get_value( ) = av_cert_arn.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_false(
      act = lv_found
      msg = |detach_thing_principal: cert { av_cert_arn } still attached| ).

    " Re-attach so class_teardown's detach+delete succeeds
    ao_iot->attachthingprincipal(
      iv_thingname = av_thing_name
      iv_principal = av_cert_arn ).
  ENDMETHOD.

* ======================================================================
* Test: delete_certificate
* Uses the dedicated av_del_cert_id that was created in class_setup
* (never attached to any thing, so no detach needed).
* ======================================================================
  METHOD delete_certificate.
    ao_iot_actions->delete_certificate(
      iv_certificate_id = av_del_cert_id ).

    " Verify: the cert must no longer appear in list
    DATA(lo_list) = ao_iot->listcertificates( ).
    DATA(lv_found) = abap_false.
    LOOP AT lo_list->get_certificates( ) INTO DATA(lo_cert).
      IF lo_cert->get_certificateid( ) = av_del_cert_id.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_false(
      act = lv_found
      msg = |delete_certificate: cert { av_del_cert_id } still found after deletion| ).
  ENDMETHOD.

* ======================================================================
* Test: create_topic_rule
* Creates a fresh rule, verifies, then cleans it up.
* ======================================================================
  METHOD create_topic_rule.
    DATA(lv_rule) = |sapabapiotcre{ /awsex/cl_utils=>get_random_string( ) }|.

    ao_iot_actions->create_topic_rule(
      iv_rule_name      = lv_rule
      iv_topic          = 'test/abap/create'
      iv_sns_action_arn = av_sns_topic_arn
      iv_role_arn       = av_role_arn ).

    " Verify: rule must appear in list
    DATA(lo_list) = ao_iot->listtopicrules( ).
    DATA(lv_found) = abap_false.
    LOOP AT lo_list->get_rules( ) INTO DATA(lo_rule).
      IF lo_rule->get_rulename( ) = lv_rule.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |create_topic_rule: rule { lv_rule } not found after creation| ).

    " Clean up
    ao_iot->deletetopicrule( iv_rulename = lv_rule ).
  ENDMETHOD.

* ======================================================================
* Test: list_topic_rules
* ======================================================================
  METHOD list_topic_rules.
    DATA lo_result TYPE REF TO /aws1/cl_iotlisttopicrulesrsp.
    ao_iot_actions->list_topic_rules( IMPORTING oo_result = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_topic_rules: result must be bound' ).

    " The shared rule created in class_setup must appear
    DATA(lv_found) = abap_false.
    LOOP AT lo_result->get_rules( ) INTO DATA(lo_rule).
      IF lo_rule->get_rulename( ) = av_rule_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_topic_rules: shared rule { av_rule_name } not found| ).
  ENDMETHOD.

* ======================================================================
* Test: update_indexing_configuration
* Sets the indexing mode to REGISTRY and verifies the change.
* ======================================================================
  METHOD update_indexing_conf.
    ao_iot_actions->update_indexing_configuration( ).

    DATA(lo_conf) = ao_iot->getindexingconfiguration( ).
    cl_abap_unit_assert=>assert_equals(
      exp = 'REGISTRY'
      act = lo_conf->get_thingindexingconf( )->get_thingindexingmode( )
      msg = 'update_indexing_conf: indexing mode must be REGISTRY' ).
  ENDMETHOD.

* ======================================================================
* Test: search_index
* Depends on REGISTRY indexing being active (enabled in class_setup).
* Polls until the shared thing is found in the index or the timeout
* (120 s) is reached.  Fails the test rather than silently skipping.
* ======================================================================
  METHOD search_index.
    DATA lo_result   TYPE REF TO /aws1/cl_iotsearchindexrsp.
    DATA lv_found    TYPE abap_bool VALUE abap_false.
    DATA lv_attempts TYPE i VALUE 0.

    " Poll for up to 120 seconds (index propagation can be slow)
    DO 24 TIMES.
      lv_attempts = lv_attempts + 1.
      TRY.
          ao_iot_actions->search_index(
            EXPORTING
              iv_query_string = |thingName:{ av_thing_name }|
            IMPORTING
              oo_result = lo_result ).

          IF lo_result IS BOUND.
            LOOP AT lo_result->get_things( ) INTO DATA(lo_doc).
              IF lo_doc->get_thingname( ) = av_thing_name.
                lv_found = abap_true.
                EXIT.
              ENDIF.
            ENDLOOP.
          ENDIF.
        CATCH /aws1/cx_iotindexnotreadyex.
          " Index not ready yet – keep waiting
        CATCH /aws1/cx_rt_generic.
          " Unexpected error – keep waiting
      ENDTRY.

      IF lv_found = abap_true.
        EXIT.
      ENDIF.
      WAIT UP TO 5 SECONDS.
    ENDDO.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |search_index: thing { av_thing_name } not found in index after { lv_attempts } attempts| ).
  ENDMETHOD.

* ======================================================================
* Test: delete_thing
* Uses the dedicated av_del_thing_name created in class_setup.
* ======================================================================
  METHOD delete_thing.
    ao_iot_actions->delete_thing( iv_thing_name = av_del_thing_name ).

    " Verify: describe should raise ResourceNotFound
    DATA(lv_deleted) = abap_false.
    TRY.
        ao_iot->describething( iv_thingname = av_del_thing_name ).
      CATCH /aws1/cx_iotresourcenotfoundex.
        lv_deleted = abap_true.
    ENDTRY.
    cl_abap_unit_assert=>assert_true(
      act = lv_deleted
      msg = |delete_thing: { av_del_thing_name } still exists after deletion| ).
  ENDMETHOD.

* ======================================================================
* Test: delete_topic_rule
* Uses the dedicated av_del_rule_name created in class_setup.
* ======================================================================
  METHOD delete_topic_rule.
    ao_iot_actions->delete_topic_rule( iv_rule_name = av_del_rule_name ).

    " Verify: rule must no longer appear in list
    DATA(lo_list) = ao_iot->listtopicrules( ).
    DATA(lv_found) = abap_false.
    LOOP AT lo_list->get_rules( ) INTO DATA(lo_rule).
      IF lo_rule->get_rulename( ) = av_del_rule_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_false(
      act = lv_found
      msg = |delete_topic_rule: rule { av_del_rule_name } still found after deletion| ).
  ENDMETHOD.

* ======================================================================
* Test: update_thing_shadow
* ======================================================================
  METHOD update_thing_shadow.
    DATA(lv_payload) = CONV /aws1/iopjsondocument(
      '{"state":{"reported":{"convert_test":true,"temp":22}}}' ).

    ao_iot_actions->update_thing_shadow(
      iv_thing_name   = av_thing_name
      iv_shadow_state = lv_payload ).

    " Verify by reading the shadow back directly
    DATA(lo_shadow) = ao_iop->getthingshadow( iv_thingname = av_thing_name ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_shadow
      msg = 'update_thing_shadow: shadow must be bound after update' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_shadow->get_payload( )
      msg = 'update_thing_shadow: shadow payload must not be empty' ).
  ENDMETHOD.

* ======================================================================
* Test: get_thing_shadow
* Shadow was seeded in class_setup, so it exists.
* ======================================================================
  METHOD get_thing_shadow.
    DATA lo_result TYPE REF TO /aws1/cl_iopgetthingshadowrsp.
    ao_iot_actions->get_thing_shadow(
      EXPORTING iv_thing_name = av_thing_name
      IMPORTING oo_result     = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'get_thing_shadow: result must be bound' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_payload( )
      msg = 'get_thing_shadow: payload must not be empty' ).
  ENDMETHOD.

ENDCLASS.
