" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_iot_actions DEFINITION DEFERRED.
CLASS /awsex/cl_iot_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_iot_actions.

CLASS ltc_awsex_cl_iot_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl           TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    CONSTANTS cv_convert_test  TYPE string              VALUE 'convert_test'.
    CONSTANTS cv_iot_trust_ply TYPE string              VALUE
      '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":' &&
      '{"Service":"iot.amazonaws.com"},"Action":"sts:AssumeRole"}]}'.
    CONSTANTS cv_sns_publish_ply TYPE string VALUE
      '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",' &&
      '"Action":"sns:Publish","Resource":"*"}]}'.
    CONSTANTS cv_iot_inline_ply TYPE string VALUE 'sap-abap-iot-sns-policy'.

    " AWS service clients
    CLASS-DATA ao_iot     TYPE REF TO /aws1/if_iot.
    CLASS-DATA ao_iam     TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_sns     TYPE REF TO /aws1/if_sns.
    CLASS-DATA ao_session TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_iot_actions TYPE REF TO /awsex/cl_iot_actions.

    " ── Shared read-only resources (created once, used by many tests) ──────
    CLASS-DATA av_thing_name     TYPE /aws1/iotthingname.
    CLASS-DATA av_thing_arn      TYPE /aws1/iotthingarn.
    CLASS-DATA av_cert_id        TYPE /aws1/iotcertificateid.
    CLASS-DATA av_cert_arn       TYPE /aws1/iotcertificatearn.
    CLASS-DATA av_rule_name      TYPE /aws1/iotrulename.
    CLASS-DATA av_sns_topic_arn  TYPE /aws1/snstopicarn.
    CLASS-DATA av_iam_role_name  TYPE /aws1/iamrolenametype.
    CLASS-DATA av_iam_role_arn   TYPE /aws1/iamarntype.

    " ── Dedicated resources consumed by destructive tests ───────────────────
    CLASS-DATA av_del_thing_name TYPE /aws1/iotthingname.
    CLASS-DATA av_del_cert_id    TYPE /aws1/iotcertificateid.
    CLASS-DATA av_del_cert_arn   TYPE /aws1/iotcertificatearn.
    CLASS-DATA av_del_rule_name  TYPE /aws1/iotrulename.

    " ── Test methods ────────────────────────────────────────────────────────
    METHODS: create_thing                  FOR TESTING RAISING /aws1/cx_rt_generic,
             list_things                   FOR TESTING RAISING /aws1/cx_rt_generic,
             create_keys_and_certificate   FOR TESTING RAISING /aws1/cx_rt_generic,
             attach_thing_principal        FOR TESTING RAISING /aws1/cx_rt_generic,
             describe_endpoint             FOR TESTING RAISING /aws1/cx_rt_generic,
             list_certificates             FOR TESTING RAISING /aws1/cx_rt_generic,
             detach_thing_principal        FOR TESTING RAISING /aws1/cx_rt_generic,
             delete_certificate            FOR TESTING RAISING /aws1/cx_rt_generic,
             create_topic_rule             FOR TESTING RAISING /aws1/cx_rt_generic,
             list_topic_rules              FOR TESTING RAISING /aws1/cx_rt_generic,
             search_index                  FOR TESTING RAISING /aws1/cx_rt_generic,
             update_indexing_configuration FOR TESTING RAISING /aws1/cx_rt_generic,
             delete_thing                  FOR TESTING RAISING /aws1/cx_rt_generic,
             delete_topic_rule             FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " Helper: tag an IoT resource (best-effort, does not fail setup on error)
    CLASS-METHODS tag_iot_resource
      IMPORTING iv_arn TYPE /aws1/iotresourcearn
      RAISING   /aws1/cx_rt_generic.

    " Helper: poll until AWS_Things index is ACTIVE
    CLASS-METHODS wait_for_index_active
      IMPORTING iv_max_wait_sec TYPE i DEFAULT 120
      RAISING   /aws1/cx_rt_generic.

ENDCLASS.


CLASS ltc_awsex_cl_iot_actions IMPLEMENTATION.

  METHOD class_setup.
    DATA(lv_rand)    = /awsex/cl_utils=>get_random_string( ).
    DATA lv_account  TYPE string.
    DATA lv_region   TYPE string.

    ao_session    = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    ao_iot        = /aws1/cl_iot_factory=>create( ao_session ).
    ao_iam        = /aws1/cl_iam_factory=>create( ao_session ).
    ao_sns        = /aws1/cl_sns_factory=>create( ao_session ).
    ao_iot_actions = NEW /awsex/cl_iot_actions( ).

    lv_account = ao_session->get_account_id( ).
    lv_region  = ao_session->get_region( ).

    " ────────────────────────────────────────────────────────────────────────
    " 1. Create IAM role that IoT topic rules can assume to publish to SNS
    " ────────────────────────────────────────────────────────────────────────
    av_iam_role_name = |sap-abap-iot-role-{ lv_rand }|.
    DATA(lo_role_result) = ao_iam->createrole(
      iv_rolename                 = av_iam_role_name
      iv_assumerolepolicydocument = cv_iot_trust_ply
      iv_description              = 'SAP ABAP IoT example test role'
      it_tags                     = VALUE /aws1/cl_iamtag=>tt_taglisttype(
        ( NEW /aws1/cl_iamtag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_role_result
      msg = 'IAM role creation failed in class_setup' ).

    av_iam_role_arn = lo_role_result->get_role( )->get_arn( ).

    " Attach inline policy so the role can publish to SNS
    ao_iam->putrolepolicy(
      iv_rolename      = av_iam_role_name
      iv_policyname    = cv_iot_inline_ply
      iv_policydocument = cv_sns_publish_ply ).

    " IAM propagation delay
    WAIT UP TO 10 SECONDS.

    " ────────────────────────────────────────────────────────────────────────
    " 2. Create SNS topic (tagged convert_test)
    " ────────────────────────────────────────────────────────────────────────
    DATA(lo_sns_result) = ao_sns->createtopic(
      iv_name   = |sap-abap-iot-topic-{ lv_rand }|
      it_tags   = VALUE /aws1/cl_snstag=>tt_taglist(
        ( NEW /aws1/cl_snstag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_sns_result
      msg = 'SNS topic creation failed in class_setup' ).
    av_sns_topic_arn = lo_sns_result->get_topicarn( ).

    " ────────────────────────────────────────────────────────────────────────
    " 3. Create shared IoT thing + tag it
    " ────────────────────────────────────────────────────────────────────────
    av_thing_name = |sap-abap-iot-thing-{ lv_rand }|.
    DATA(lo_thing) = ao_iot->creatething( iv_thingname = av_thing_name ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_thing
      msg = 'IoT thing creation failed in class_setup' ).
    av_thing_arn = lo_thing->get_thingarn( ).
    tag_iot_resource( av_thing_arn ).

    " ────────────────────────────────────────────────────────────────────────
    " 4. Create shared certificate and attach to shared thing
    " ────────────────────────────────────────────────────────────────────────
    DATA(lo_cert) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_cert
      msg = 'Shared certificate creation failed in class_setup' ).
    av_cert_id  = lo_cert->get_certificateid( ).
    av_cert_arn = lo_cert->get_certificatearn( ).

    ao_iot->attachthingprincipal(
      iv_thingname = av_thing_name
      iv_principal = av_cert_arn ).

    " ────────────────────────────────────────────────────────────────────────
    " 5. Create shared topic rule (SNS action) + tag it
    " ────────────────────────────────────────────────────────────────────────
    av_rule_name = |sap_abap_iot_rule_{ lv_rand }|.
    DATA lt_rule_actions TYPE /aws1/cl_iotaction=>tt_actionlist.
    APPEND NEW /aws1/cl_iotaction(
      io_sns = NEW /aws1/cl_iotsnsaction(
        iv_targetarn = av_sns_topic_arn
        iv_rolearn   = av_iam_role_arn )
    ) TO lt_rule_actions.

    ao_iot->createtopicrule(
      iv_rulename         = av_rule_name
      io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
        iv_sql     = |SELECT * FROM 'sap/abap/iot/test'|
        it_actions = lt_rule_actions ) ).

    " Tag the rule by its ARN
    DATA(lv_rule_arn) =
      |arn:aws:iot:{ lv_region }:{ lv_account }:rule/{ av_rule_name }|.
    tag_iot_resource( lv_rule_arn ).

    " ────────────────────────────────────────────────────────────────────────
    " 6. Enable thing indexing so search_index works
    " ────────────────────────────────────────────────────────────────────────
    ao_iot->updateindexingconfiguration(
      io_thingindexingconf = NEW /aws1/cl_iotthingindexingconf(
        iv_thingindexingmode = 'REGISTRY' ) ).

    " ────────────────────────────────────────────────────────────────────────
    " 7. Dedicated thing for delete_thing test
    " ────────────────────────────────────────────────────────────────────────
    DATA(lv_rand2) = /awsex/cl_utils=>get_random_string( ).
    av_del_thing_name = |sap-abap-iot-del-{ lv_rand2 }|.
    DATA(lo_del_thing) = ao_iot->creatething( iv_thingname = av_del_thing_name ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_del_thing
      msg = 'Dedicated delete-thing creation failed in class_setup' ).
    tag_iot_resource( lo_del_thing->get_thingarn( ) ).

    " ────────────────────────────────────────────────────────────────────────
    " 8. Dedicated certificate for delete_certificate test
    " ────────────────────────────────────────────────────────────────────────
    DATA(lo_del_cert) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_del_cert
      msg = 'Dedicated delete-cert creation failed in class_setup' ).
    av_del_cert_id  = lo_del_cert->get_certificateid( ).
    av_del_cert_arn = lo_del_cert->get_certificatearn( ).

    " ────────────────────────────────────────────────────────────────────────
    " 9. Dedicated topic rule for delete_topic_rule test
    " ────────────────────────────────────────────────────────────────────────
    DATA(lv_rand3) = /awsex/cl_utils=>get_random_string( ).
    av_del_rule_name = |sap_abap_iot_del_{ lv_rand3 }|.
    DATA lt_del_actions TYPE /aws1/cl_iotaction=>tt_actionlist.
    APPEND NEW /aws1/cl_iotaction(
      io_sns = NEW /aws1/cl_iotsnsaction(
        iv_targetarn = av_sns_topic_arn
        iv_rolearn   = av_iam_role_arn )
    ) TO lt_del_actions.

    ao_iot->createtopicrule(
      iv_rulename         = av_del_rule_name
      io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
        iv_sql     = |SELECT * FROM 'sap/abap/iot/del'|
        it_actions = lt_del_actions ) ).

    tag_iot_resource(
      |arn:aws:iot:{ lv_region }:{ lv_account }:rule/{ av_del_rule_name }| ).

  ENDMETHOD.


  METHOD class_teardown.
    " Each cleanup is in its own TRY/CATCH so one failure doesn't block others.

    " ── Detach shared cert and delete it ────────────────────────────────────
    IF av_cert_arn IS NOT INITIAL AND av_thing_name IS NOT INITIAL.
      TRY.
          ao_iot->detachthingprincipal(
            iv_thingname = av_thing_name
            iv_principal = av_cert_arn ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
    IF av_cert_id IS NOT INITIAL.
      TRY.
          ao_iot->updatecertificate(
            iv_certificateid = av_cert_id
            iv_newstatus     = 'INACTIVE' ).
          ao_iot->deletecertificate( iv_certificateid = av_cert_id ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " ── Delete shared thing ─────────────────────────────────────────────────
    IF av_thing_name IS NOT INITIAL.
      TRY.
          ao_iot->deletething( iv_thingname = av_thing_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " ── Delete dedicated delete-cert (test may have already deleted it) ─────
    IF av_del_cert_id IS NOT INITIAL.
      TRY.
          ao_iot->updatecertificate(
            iv_certificateid = av_del_cert_id
            iv_newstatus     = 'INACTIVE' ).
          ao_iot->deletecertificate( iv_certificateid = av_del_cert_id ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " ── Delete dedicated delete-thing (test may have already deleted it) ────
    IF av_del_thing_name IS NOT INITIAL.
      TRY.
          ao_iot->deletething( iv_thingname = av_del_thing_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " ── Delete shared topic rule ─────────────────────────────────────────────
    IF av_rule_name IS NOT INITIAL.
      TRY.
          ao_iot->deletetopicrule( iv_rulename = av_rule_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " ── Delete dedicated delete-rule (test may have already deleted it) ──────
    IF av_del_rule_name IS NOT INITIAL.
      TRY.
          ao_iot->deletetopicrule( iv_rulename = av_del_rule_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " ── Delete SNS topic ────────────────────────────────────────────────────
    IF av_sns_topic_arn IS NOT INITIAL.
      TRY.
          ao_sns->deletetopic( iv_topicarn = av_sns_topic_arn ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " ── Delete IAM inline policy then role ───────────────────────────────────
    IF av_iam_role_name IS NOT INITIAL.
      TRY.
          ao_iam->deleterolepolicy(
            iv_rolename   = av_iam_role_name
            iv_policyname = cv_iot_inline_ply ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
      TRY.
          ao_iam->deleterole( iv_rolename = av_iam_role_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
  ENDMETHOD.


  METHOD tag_iot_resource.
    ao_iot->tagresource(
      iv_resourcearn = iv_arn
      it_tags        = VALUE /aws1/cl_iottag=>tt_taglist(
        ( NEW /aws1/cl_iottag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).
  ENDMETHOD.


  METHOD wait_for_index_active.
    DATA lv_elapsed   TYPE i VALUE 0.
    DATA lv_ready     TYPE abap_bool VALUE abap_false.
    DATA lv_start     TYPE timestampl.
    DATA lv_now       TYPE timestampl.

    GET TIME STAMP FIELD lv_start.

    WHILE lv_ready = abap_false AND lv_elapsed < iv_max_wait_sec.
      TRY.
          DATA(lo_idx) = ao_iot->describeindex( iv_indexname = 'AWS_Things' ).
          IF lo_idx->get_indexstatus( ) = 'ACTIVE'.
            lv_ready = abap_true.
          ELSE.
            WAIT UP TO 10 SECONDS.
            GET TIME STAMP FIELD lv_now.
            lv_elapsed = lv_now - lv_start.
          ENDIF.
        CATCH /aws1/cx_rt_generic.
          WAIT UP TO 10 SECONDS.
          GET TIME STAMP FIELD lv_now.
          lv_elapsed = lv_now - lv_start.
      ENDTRY.
    ENDWHILE.

    IF lv_ready = abap_false.
      cl_abap_unit_assert=>fail(
        msg = |AWS_Things index did not become ACTIVE within { iv_max_wait_sec } seconds| ).
    ENDIF.
  ENDMETHOD.


  " ══════════════════════════════════════════════════════════════════════════
  " Test methods
  " ══════════════════════════════════════════════════════════════════════════

  METHOD create_thing.
    DATA(lv_rand)    = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_new_name) = |sap-abap-iot-new-{ lv_rand }|.

    DATA(oo_result) = ao_iot_actions->create_thing( iv_thing_name = lv_new_name ).

    cl_abap_unit_assert=>assert_bound(
      act = oo_result
      msg = |create_thing returned unbound result for { lv_new_name }| ).

    cl_abap_unit_assert=>assert_equals(
      exp = lv_new_name
      act = oo_result->get_thingname( )
      msg = |Thing name mismatch after create_thing| ).

    cl_abap_unit_assert=>assert_not_initial(
      act = oo_result->get_thingarn( )
      msg = |Thing ARN is empty after create_thing| ).

    " Tag the newly created thing
    tag_iot_resource( oo_result->get_thingarn( ) ).

    " Cleanup
    TRY.
        ao_iot->deletething( iv_thingname = lv_new_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  METHOD list_things.
    DATA(lt_things) = ao_iot_actions->list_things( ).

    " The shared thing created in class_setup MUST appear in the list
    DATA(lv_found) = abap_false.
    LOOP AT lt_things INTO DATA(lo_thing).
      IF lo_thing->get_thingname( ) = av_thing_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Thing { av_thing_name } not found in list_things result| ).
  ENDMETHOD.


  METHOD create_keys_and_certificate.
    DATA(oo_result) = ao_iot_actions->create_keys_and_certificate( ).

    cl_abap_unit_assert=>assert_bound(
      act = oo_result
      msg = 'create_keys_and_certificate returned unbound result' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = oo_result->get_certificateid( )
      msg = 'Certificate ID is empty after create_keys_and_certificate' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = oo_result->get_certificatearn( )
      msg = 'Certificate ARN is empty after create_keys_and_certificate' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = oo_result->get_certificatepem( )
      msg = 'Certificate PEM is empty after create_keys_and_certificate' ).

    " Cleanup the certificate created by this test
    DATA(lv_new_cert_id) = oo_result->get_certificateid( ).
    TRY.
        ao_iot->updatecertificate(
          iv_certificateid = lv_new_cert_id
          iv_newstatus     = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = lv_new_cert_id ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  METHOD attach_thing_principal.
    " Use fresh, dedicated resources so this test is independent
    DATA(lv_rand)          = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_attach_thing)  = |sap-abap-iot-att-{ lv_rand }|.

    DATA(lo_new_thing) = ao_iot->creatething( iv_thingname = lv_attach_thing ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_new_thing
      msg = |Thing creation failed in attach_thing_principal| ).
    tag_iot_resource( lo_new_thing->get_thingarn( ) ).

    DATA(lo_new_cert) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_new_cert
      msg = |Certificate creation failed in attach_thing_principal| ).
    DATA(lv_cert_id)  = lo_new_cert->get_certificateid( ).
    DATA(lv_cert_arn) = lo_new_cert->get_certificatearn( ).

    " ── Call the action under test ──────────────────────────────────────────
    ao_iot_actions->attach_thing_principal(
      iv_thing_name = lv_attach_thing
      iv_principal  = lv_cert_arn ).

    " ── Verify the principal is now attached ────────────────────────────────
    DATA(lo_principals) = ao_iot->listthingprincipals( iv_thingname = lv_attach_thing ).
    DATA(lv_found) = abap_false.
    LOOP AT lo_principals->get_principals( ) INTO DATA(lo_p).
      IF lo_p->get_value( ) = lv_cert_arn.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Certificate { lv_cert_arn } not found as principal of { lv_attach_thing }| ).

    " Cleanup
    TRY.
        ao_iot->detachthingprincipal(
          iv_thingname = lv_attach_thing
          iv_principal = lv_cert_arn ).
        ao_iot->updatecertificate(
          iv_certificateid = lv_cert_id
          iv_newstatus     = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = lv_cert_id ).
        ao_iot->deletething( iv_thingname = lv_attach_thing ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  METHOD describe_endpoint.
    DATA(lv_endpoint) = ao_iot_actions->describe_endpoint(
      iv_endpoint_type = 'iot:Data-ATS' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_endpoint
      msg = 'describe_endpoint returned an empty endpoint address' ).

    " A valid Data-ATS endpoint always contains amazonaws.com
    cl_abap_unit_assert=>assert_differs(
      act = find( val = lv_endpoint sub = 'amazonaws.com' )
      exp = -1
      msg = |Endpoint does not look valid: { lv_endpoint }| ).
  ENDMETHOD.


  METHOD list_certificates.
    DATA(lt_certs) = ao_iot_actions->list_certificates( ).

    " The shared certificate created in class_setup MUST appear
    DATA(lv_found) = abap_false.
    LOOP AT lt_certs INTO DATA(lo_cert).
      IF lo_cert->get_certificateid( ) = av_cert_id.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Certificate { av_cert_id } not found in list_certificates result| ).
  ENDMETHOD.


  METHOD detach_thing_principal.
    " Use fresh, dedicated resources for this destructive test
    DATA(lv_rand)         = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_det_thing)    = |sap-abap-iot-det-{ lv_rand }|.

    DATA(lo_new_thing) = ao_iot->creatething( iv_thingname = lv_det_thing ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_new_thing
      msg = |Thing creation failed in detach_thing_principal| ).
    tag_iot_resource( lo_new_thing->get_thingarn( ) ).

    DATA(lo_new_cert) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_new_cert
      msg = |Certificate creation failed in detach_thing_principal| ).
    DATA(lv_cert_id)  = lo_new_cert->get_certificateid( ).
    DATA(lv_cert_arn) = lo_new_cert->get_certificatearn( ).

    ao_iot->attachthingprincipal(
      iv_thingname = lv_det_thing
      iv_principal = lv_cert_arn ).

    " ── Call the action under test ──────────────────────────────────────────
    ao_iot_actions->detach_thing_principal(
      iv_thing_name = lv_det_thing
      iv_principal  = lv_cert_arn ).

    " ── Verify the principal is no longer attached ──────────────────────────
    DATA(lo_principals) = ao_iot->listthingprincipals( iv_thingname = lv_det_thing ).
    DATA(lv_found) = abap_false.
    LOOP AT lo_principals->get_principals( ) INTO DATA(lo_p).
      IF lo_p->get_value( ) = lv_cert_arn.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_false(
      act = lv_found
      msg = |Certificate { lv_cert_arn } should not be a principal of { lv_det_thing } after detach| ).

    " Cleanup
    TRY.
        ao_iot->updatecertificate(
          iv_certificateid = lv_cert_id
          iv_newstatus     = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = lv_cert_id ).
        ao_iot->deletething( iv_thingname = lv_det_thing ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  METHOD delete_certificate.
    " The dedicated cert was created (and NOT attached) in class_setup
    cl_abap_unit_assert=>assert_not_initial(
      act = av_del_cert_id
      msg = 'av_del_cert_id not set — class_setup may have failed' ).

    " ── Call the action under test ──────────────────────────────────────────
    ao_iot_actions->delete_certificate( iv_certificate_id = av_del_cert_id ).

    " ── Verify the certificate is gone ──────────────────────────────────────
    DATA(lt_certs) = ao_iot->listcertificates( )->get_certificates( ).
    DATA(lv_found) = abap_false.
    LOOP AT lt_certs INTO DATA(lo_cert).
      IF lo_cert->get_certificateid( ) = av_del_cert_id.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_false(
      act = lv_found
      msg = |Certificate { av_del_cert_id } should have been deleted| ).

    " Prevent class_teardown from attempting a second deletion
    CLEAR: av_del_cert_id, av_del_cert_arn.
  ENDMETHOD.


  METHOD create_topic_rule.
    DATA(lv_rand)     = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_new_rule) = |sap_abap_iot_new_{ lv_rand }|.

    " ── Call the action under test ──────────────────────────────────────────
    ao_iot_actions->create_topic_rule(
      iv_rule_name      = lv_new_rule
      iv_topic          = 'sap/abap/iot/newrule'
      iv_sns_action_arn = av_sns_topic_arn
      iv_role_arn       = av_iam_role_arn ).

    " ── Verify the rule appears in the listing ─────────────────────────────
    DATA(lt_rules) = ao_iot->listtopicrules( )->get_rules( ).
    DATA(lv_found) = abap_false.
    LOOP AT lt_rules INTO DATA(lo_rule).
      IF lo_rule->get_rulename( ) = lv_new_rule.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Topic rule { lv_new_rule } not found after create_topic_rule| ).

    " Cleanup
    TRY.
        ao_iot->deletetopicrule( iv_rulename = lv_new_rule ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  METHOD list_topic_rules.
    DATA(lt_rules) = ao_iot_actions->list_topic_rules( ).

    " The shared rule created in class_setup MUST appear
    DATA(lv_found) = abap_false.
    LOOP AT lt_rules INTO DATA(lo_rule).
      IF lo_rule->get_rulename( ) = av_rule_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Topic rule { av_rule_name } not found in list_topic_rules result| ).
  ENDMETHOD.


  METHOD search_index.
    " Ensure indexing mode is REGISTRY (class_setup already did this,
    " but the call is idempotent so we repeat for safety)
    TRY.
        ao_iot->updateindexingconfiguration(
          io_thingindexingconf = NEW /aws1/cl_iotthingindexingconf(
            iv_thingindexingmode = 'REGISTRY' ) ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Block until AWS_Things index is ACTIVE (fails the test if it times out)
    wait_for_index_active( iv_max_wait_sec = 120 ).

    " Wait an additional moment for the shared thing to be indexed
    WAIT UP TO 15 SECONDS.

    " ── Call the action under test ──────────────────────────────────────────
    DATA(lt_things) = ao_iot_actions->search_index(
      iv_query = |thingName:{ av_thing_name }| ).

    " ── The shared thing MUST appear in the results ─────────────────────────
    DATA(lv_found) = abap_false.
    LOOP AT lt_things INTO DATA(lo_thing).
      IF lo_thing->get_thingname( ) = av_thing_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Thing { av_thing_name } not found in search_index results| ).
  ENDMETHOD.


  METHOD update_indexing_configuration.
    " ── Call the action under test ──────────────────────────────────────────
    ao_iot_actions->update_indexing_configuration( ).

    " ── Verify the index exists and has a status ────────────────────────────
    DATA(lo_idx) = ao_iot->describeindex( iv_indexname = 'AWS_Things' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_idx->get_indexstatus( )
      msg = 'Index status is empty after update_indexing_configuration' ).

    " Valid statuses: ACTIVE, BUILDING, REBUILDING
    DATA(lv_status) = lo_idx->get_indexstatus( ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lv_status = 'ACTIVE'     OR
                     lv_status = 'BUILDING'   OR
                     lv_status = 'REBUILDING' )
      msg = |Unexpected index status after update: { lv_status }| ).
  ENDMETHOD.


  METHOD delete_thing.
    cl_abap_unit_assert=>assert_not_initial(
      act = av_del_thing_name
      msg = 'av_del_thing_name not set — class_setup may have failed' ).

    " ── Call the action under test ──────────────────────────────────────────
    ao_iot_actions->delete_thing( iv_thing_name = av_del_thing_name ).

    " ── Verify the thing is gone ────────────────────────────────────────────
    DATA(lt_things) = ao_iot->listthings( )->get_things( ).
    DATA(lv_found)  = abap_false.
    LOOP AT lt_things INTO DATA(lo_thing).
      IF lo_thing->get_thingname( ) = av_del_thing_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_false(
      act = lv_found
      msg = |Thing { av_del_thing_name } should have been deleted| ).

    " Prevent class_teardown from attempting a second deletion
    CLEAR av_del_thing_name.
  ENDMETHOD.


  METHOD delete_topic_rule.
    cl_abap_unit_assert=>assert_not_initial(
      act = av_del_rule_name
      msg = 'av_del_rule_name not set — class_setup may have failed' ).

    " ── Call the action under test ──────────────────────────────────────────
    ao_iot_actions->delete_topic_rule( iv_rule_name = av_del_rule_name ).

    " ── Verify the rule is gone ─────────────────────────────────────────────
    DATA(lt_rules) = ao_iot->listtopicrules( )->get_rules( ).
    DATA(lv_found) = abap_false.
    LOOP AT lt_rules INTO DATA(lo_rule).
      IF lo_rule->get_rulename( ) = av_del_rule_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_false(
      act = lv_found
      msg = |Topic rule { av_del_rule_name } should have been deleted| ).

    " Prevent class_teardown from attempting a second deletion
    CLEAR av_del_rule_name.
  ENDMETHOD.

ENDCLASS.
