" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_iot_actions DEFINITION DEFERRED.
CLASS /awsex/cl_iot_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_iot_actions.

CLASS ltc_awsex_cl_iot_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl          TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    CONSTANTS cv_tag_key      TYPE /aws1/iottagkey     VALUE 'convert_test'.
    CONSTANTS cv_tag_value    TYPE /aws1/iottagvalue   VALUE 'true'.

    CLASS-DATA ao_iot         TYPE REF TO /aws1/if_iot.
    CLASS-DATA ao_sns         TYPE REF TO /aws1/if_sns.
    CLASS-DATA ao_iam         TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_session     TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_iot_actions TYPE REF TO /awsex/cl_iot_actions.

    " ---------------------------------------------------------------
    " Shared resources (non-mutating tests reuse these)
    " ---------------------------------------------------------------
    CLASS-DATA av_thing_name      TYPE /aws1/iotthingname.
    CLASS-DATA av_thing_arn       TYPE /aws1/iotthingarn.
    CLASS-DATA av_certificate_id  TYPE /aws1/iotcertificateid.
    CLASS-DATA av_certificate_arn TYPE /aws1/iotcertificatearn.
    CLASS-DATA av_sns_topic_arn   TYPE /aws1/snstopicarn.
    CLASS-DATA av_iam_role_arn    TYPE /aws1/iamarntype.
    CLASS-DATA av_iam_role_name   TYPE /aws1/iamrolenametype.
    CLASS-DATA av_iam_policy_name TYPE /aws1/iampolicynametype.
    CLASS-DATA av_rule_name       TYPE /aws1/iotrulename.
    CLASS-DATA av_rule_arn        TYPE /aws1/iotrulearn.

    " ---------------------------------------------------------------
    " Dedicated resources for mutating (delete) tests – created fresh
    " in class_setup so they definitely exist before the test runs.
    " ---------------------------------------------------------------
    CLASS-DATA av_del_thing_name  TYPE /aws1/iotthingname.
    CLASS-DATA av_del_thing_arn   TYPE /aws1/iotthingarn.
    CLASS-DATA av_del_cert_id     TYPE /aws1/iotcertificateid.
    CLASS-DATA av_del_cert_arn    TYPE /aws1/iotcertificatearn.
    CLASS-DATA av_del_rule_name   TYPE /aws1/iotrulename.

    " Dedicated thing/cert for the detach_thing_principal test
    CLASS-DATA av_det_thing_name  TYPE /aws1/iotthingname.
    CLASS-DATA av_det_cert_id     TYPE /aws1/iotcertificateid.
    CLASS-DATA av_det_cert_arn    TYPE /aws1/iotcertificatearn.

    METHODS: create_thing               FOR TESTING RAISING /aws1/cx_rt_generic,
      list_things                       FOR TESTING RAISING /aws1/cx_rt_generic,
      create_keys_and_certificate       FOR TESTING RAISING /aws1/cx_rt_generic,
      attach_thing_principal            FOR TESTING RAISING /aws1/cx_rt_generic,
      describe_endpoint                 FOR TESTING RAISING /aws1/cx_rt_generic,
      list_certificates                 FOR TESTING RAISING /aws1/cx_rt_generic,
      detach_thing_principal            FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_certificate                FOR TESTING RAISING /aws1/cx_rt_generic,
      create_topic_rule                 FOR TESTING RAISING /aws1/cx_rt_generic,
      list_topic_rules                  FOR TESTING RAISING /aws1/cx_rt_generic,
      update_indexing_configuration     FOR TESTING RAISING /aws1/cx_rt_generic,
      search_index                      FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_thing                      FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_topic_rule                 FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " Helper: tag an IoT resource by ARN
    CLASS-METHODS tag_iot_resource
      IMPORTING iv_arn TYPE /aws1/iotresourcearn
      RAISING   /aws1/cx_rt_generic.

    " Helper: build a single-entry IoT tag list for convert_test
    CLASS-METHODS build_iot_tags
      RETURNING VALUE(rt_tags) TYPE /aws1/cl_iottag=>tt_taglist.

ENDCLASS.


CLASS ltc_awsex_cl_iot_actions IMPLEMENTATION.

* ─────────────────────────────────────────────────────────────────
*  Helpers
* ─────────────────────────────────────────────────────────────────

  METHOD build_iot_tags.
    APPEND NEW /aws1/cl_iottag(
      iv_key   = cv_tag_key
      iv_value = cv_tag_value ) TO rt_tags.
  ENDMETHOD.

  METHOD tag_iot_resource.
    ao_iot->tagresource(
      iv_resourcearn = iv_arn
      it_tags        = build_iot_tags( ) ).
  ENDMETHOD.

* ─────────────────────────────────────────────────────────────────
*  CLASS_SETUP
* ─────────────────────────────────────────────────────────────────

  METHOD class_setup.
    ao_session    = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_iot        = /aws1/cl_iot_factory=>create( ao_session ).
    ao_sns        = /aws1/cl_sns_factory=>create( ao_session ).
    ao_iam        = /aws1/cl_iam_factory=>create( ao_session ).
    ao_iot_actions = NEW /awsex/cl_iot_actions( ).

    DATA lv_uuid_string TYPE string.

    " ----------------------------------------------------------------
    " 1.  Shared IoT thing  (used by list/attach/detach/search tests)
    " ----------------------------------------------------------------
    DATA(lv_uuid1) = /awsex/cl_utils=>get_random_string( ).
    lv_uuid_string = lv_uuid1.
    av_thing_name = |sap-abap-iot-thing-{ lv_uuid_string }|.

    DATA(lo_thing_rsp) = ao_iot->creatething( iv_thingname = av_thing_name ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_thing_rsp
      msg = |Failed to create shared IoT thing| ).
    av_thing_arn = lo_thing_rsp->get_thingarn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_thing_arn
      msg = |Shared thing ARN is empty| ).
    tag_iot_resource( av_thing_arn ).

    " ----------------------------------------------------------------
    " 2.  Shared certificate  (attached to shared thing)
    " ----------------------------------------------------------------
    DATA(lo_cert_rsp) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_cert_rsp
      msg = |Failed to create shared certificate| ).
    av_certificate_id  = lo_cert_rsp->get_certificateid( ).
    av_certificate_arn = lo_cert_rsp->get_certificatearn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_certificate_id
      msg = |Shared certificate ID is empty| ).
    tag_iot_resource( av_certificate_arn ).

    ao_iot->attachthingprincipal(
      iv_thingname = av_thing_name
      iv_principal = av_certificate_arn ).

    " ----------------------------------------------------------------
    " 3.  SNS topic  (used by topic-rule tests)
    " ----------------------------------------------------------------
    DATA(lv_sns_name) = |sap-abap-iot-sns-{ lv_uuid_string }|.
    DATA(lo_sns_rsp) = ao_sns->createtopic( iv_name = lv_sns_name ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_sns_rsp
      msg = |Failed to create SNS topic| ).
    av_sns_topic_arn = lo_sns_rsp->get_topicarn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_sns_topic_arn
      msg = |SNS topic ARN is empty| ).

    " Tag the SNS topic
    DATA lt_sns_tags TYPE /aws1/cl_snstag=>tt_taglist.
    APPEND NEW /aws1/cl_snstag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_sns_tags.
    ao_sns->tagresource(
      iv_resourcearn = av_sns_topic_arn
      it_tags        = lt_sns_tags ).

    " ----------------------------------------------------------------
    " 4.  IAM role  (used by topic-rule tests)
    "     Trust: iot.amazonaws.com
    "     Inline policy: sns:Publish on the SNS topic
    " ----------------------------------------------------------------
    av_iam_role_name   = |sap-abap-iot-role-{ lv_uuid_string }|.
    av_iam_policy_name = |iot-sns-pub-{ lv_uuid_string }|.

    DATA(lv_trust) =
      '{"Version":"2012-10-17","Statement":[{' &&
      '"Effect":"Allow",' &&
      '"Principal":{"Service":"iot.amazonaws.com"},' &&
      '"Action":"sts:AssumeRole"}]}' .

    DATA(lo_role_rsp) = ao_iam->createrole(
      iv_rolename                 = av_iam_role_name
      iv_assumerolepolicydocument = lv_trust ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_role_rsp
      msg = |Failed to create IAM role| ).
    av_iam_role_arn = lo_role_rsp->get_role( )->get_arn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_iam_role_arn
      msg = |IAM role ARN is empty| ).

    " Tag the IAM role
    DATA lt_iam_tags TYPE /aws1/cl_iamtag=>tt_taglisttype.
    APPEND NEW /aws1/cl_iamtag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_iam_tags.
    ao_iam->tagrole(
      iv_rolename = av_iam_role_name
      it_tags     = lt_iam_tags ).

    " Inline policy: allow SNS publish
    DATA(lv_pol_doc) =
      '{"Version":"2012-10-17","Statement":[{' &&
      '"Effect":"Allow",' &&
      '"Action":"sns:Publish",' &&
      '"Resource":"' && av_sns_topic_arn && '"}]}' .
    ao_iam->putrolepolicy(
      iv_rolename       = av_iam_role_name
      iv_policyname     = av_iam_policy_name
      iv_policydocument = lv_pol_doc ).

    " Wait briefly so IAM propagates before IoT uses the role
    WAIT UP TO 10 SECONDS.

    " ----------------------------------------------------------------
    " 5.  Shared topic rule  (used by list_topic_rules test)
    " ----------------------------------------------------------------
    av_rule_name = |SapAbapIotRule{ lv_uuid_string }|.
    TRANSLATE av_rule_name USING '- '.
    CONDENSE av_rule_name NO-GAPS.

    DATA lt_act1 TYPE /aws1/cl_iotaction=>tt_actionlist.
    APPEND NEW /aws1/cl_iotaction(
      io_sns = NEW /aws1/cl_iotsnsaction(
        iv_targetarn = av_sns_topic_arn
        iv_rolearn   = av_iam_role_arn ) ) TO lt_act1.

    ao_iot->createtopicrule(
      iv_rulename         = av_rule_name
      io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
        iv_sql     = |SELECT * FROM 'iot/test/{ lv_uuid_string }'|
        it_actions = lt_act1 ) ).

    " Retrieve the rule ARN for tagging
    DATA(lo_rule_get) = ao_iot->gettopicrule( iv_rulename = av_rule_name ).
    av_rule_arn = lo_rule_get->get_rulearn( ).
    IF av_rule_arn IS NOT INITIAL.
      tag_iot_resource( av_rule_arn ).
    ENDIF.

    " ----------------------------------------------------------------
    " 6.  Dedicated thing for delete_thing test
    " ----------------------------------------------------------------
    DATA(lv_uuid2) = /awsex/cl_utils=>get_random_string( ).
    lv_uuid_string = lv_uuid2.
    av_del_thing_name = |sap-abap-iot-del-{ lv_uuid_string }|.

    DATA(lo_del_thing) = ao_iot->creatething( iv_thingname = av_del_thing_name ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_del_thing
      msg = |Failed to create del-thing| ).
    av_del_thing_arn = lo_del_thing->get_thingarn( ).
    tag_iot_resource( av_del_thing_arn ).

    " ----------------------------------------------------------------
    " 7.  Dedicated certificate for delete_certificate test
    " ----------------------------------------------------------------
    DATA(lo_del_cert) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_del_cert
      msg = |Failed to create del-cert| ).
    av_del_cert_id  = lo_del_cert->get_certificateid( ).
    av_del_cert_arn = lo_del_cert->get_certificatearn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_del_cert_id
      msg = |Del-cert ID is empty| ).
    tag_iot_resource( av_del_cert_arn ).

    " ----------------------------------------------------------------
    " 8.  Dedicated topic rule for delete_topic_rule test
    " ----------------------------------------------------------------
    DATA(lv_uuid3) = /awsex/cl_utils=>get_random_string( ).
    lv_uuid_string = lv_uuid3.
    av_del_rule_name = |SapAbapIotDel{ lv_uuid_string }|.
    TRANSLATE av_del_rule_name USING '- '.
    CONDENSE av_del_rule_name NO-GAPS.

    DATA lt_act2 TYPE /aws1/cl_iotaction=>tt_actionlist.
    APPEND NEW /aws1/cl_iotaction(
      io_sns = NEW /aws1/cl_iotsnsaction(
        iv_targetarn = av_sns_topic_arn
        iv_rolearn   = av_iam_role_arn ) ) TO lt_act2.

    ao_iot->createtopicrule(
      iv_rulename         = av_del_rule_name
      io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
        iv_sql     = |SELECT * FROM 'iot/del/{ lv_uuid_string }'|
        it_actions = lt_act2 ) ).

    DATA(lo_del_rule_get) = ao_iot->gettopicrule( iv_rulename = av_del_rule_name ).
    DATA(lv_del_rule_arn) = lo_del_rule_get->get_rulearn( ).
    IF lv_del_rule_arn IS NOT INITIAL.
      tag_iot_resource( lv_del_rule_arn ).
    ENDIF.

    " ----------------------------------------------------------------
    " 9.  Dedicated thing+cert for detach_thing_principal test
    "     The cert is pre-attached so the test can immediately detach.
    " ----------------------------------------------------------------
    DATA(lv_uuid4) = /awsex/cl_utils=>get_random_string( ).
    lv_uuid_string = lv_uuid4.
    av_det_thing_name = |sap-abap-iot-det-{ lv_uuid_string }|.

    DATA(lo_det_thing) = ao_iot->creatething( iv_thingname = av_det_thing_name ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_det_thing
      msg = |Failed to create det-thing| ).
    tag_iot_resource( lo_det_thing->get_thingarn( ) ).

    DATA(lo_det_cert) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_det_cert
      msg = |Failed to create det-cert| ).
    av_det_cert_id  = lo_det_cert->get_certificateid( ).
    av_det_cert_arn = lo_det_cert->get_certificatearn( ).
    tag_iot_resource( av_det_cert_arn ).

    ao_iot->attachthingprincipal(
      iv_thingname = av_det_thing_name
      iv_principal = av_det_cert_arn ).

    " ----------------------------------------------------------------
    " 10.  Enable indexing so search_index test works
    " ----------------------------------------------------------------
    ao_iot->updateindexingconfiguration(
      io_thingindexingconf = NEW /aws1/cl_iotthingindexingconf(
        iv_thingindexingmode = 'REGISTRY' ) ).

  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────
*  CLASS_TEARDOWN
* ─────────────────────────────────────────────────────────────────

  METHOD class_teardown.
    " -------------------------------------------------------
    " Detach and delete shared certificate / thing
    " -------------------------------------------------------
    IF av_certificate_arn IS NOT INITIAL AND av_thing_name IS NOT INITIAL.
      TRY.
          ao_iot->detachthingprincipal(
            iv_thingname = av_thing_name
            iv_principal = av_certificate_arn ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
    IF av_certificate_id IS NOT INITIAL.
      TRY.
          ao_iot->updatecertificate(
            iv_certificateid = av_certificate_id
            iv_newstatus     = 'INACTIVE' ).
          ao_iot->deletecertificate( iv_certificateid = av_certificate_id ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
    IF av_thing_name IS NOT INITIAL.
      TRY.
          ao_iot->deletething( iv_thingname = av_thing_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " -------------------------------------------------------
    " Shared topic rule
    " -------------------------------------------------------
    IF av_rule_name IS NOT INITIAL.
      TRY.
          ao_iot->deletetopicrule( iv_rulename = av_rule_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " -------------------------------------------------------
    " Detach-test thing/cert (only if test did NOT already clean up)
    " -------------------------------------------------------
    IF av_det_cert_arn IS NOT INITIAL AND av_det_thing_name IS NOT INITIAL.
      TRY.
          ao_iot->detachthingprincipal(
            iv_thingname = av_det_thing_name
            iv_principal = av_det_cert_arn ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
    IF av_det_cert_id IS NOT INITIAL.
      TRY.
          ao_iot->updatecertificate(
            iv_certificateid = av_det_cert_id
            iv_newstatus     = 'INACTIVE' ).
          ao_iot->deletecertificate( iv_certificateid = av_det_cert_id ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
    IF av_det_thing_name IS NOT INITIAL.
      TRY.
          ao_iot->deletething( iv_thingname = av_det_thing_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " -------------------------------------------------------
    " Delete-test: thing (if not already deleted by test)
    " -------------------------------------------------------
    IF av_del_thing_name IS NOT INITIAL.
      TRY.
          ao_iot->deletething( iv_thingname = av_del_thing_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " Delete-test: certificate (if not already deleted by test)
    IF av_del_cert_id IS NOT INITIAL.
      TRY.
          ao_iot->updatecertificate(
            iv_certificateid = av_del_cert_id
            iv_newstatus     = 'INACTIVE' ).
          ao_iot->deletecertificate( iv_certificateid = av_del_cert_id ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " Delete-test: topic rule (if not already deleted by test)
    IF av_del_rule_name IS NOT INITIAL.
      TRY.
          ao_iot->deletetopicrule( iv_rulename = av_del_rule_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " -------------------------------------------------------
    " SNS topic
    " -------------------------------------------------------
    IF av_sns_topic_arn IS NOT INITIAL.
      TRY.
          ao_sns->deletetopic( iv_topicarn = av_sns_topic_arn ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " -------------------------------------------------------
    " IAM role: remove inline policy, then delete role
    " -------------------------------------------------------
    IF av_iam_role_name IS NOT INITIAL.
      IF av_iam_policy_name IS NOT INITIAL.
        TRY.
            ao_iam->deleterolepolicy(
              iv_rolename   = av_iam_role_name
              iv_policyname = av_iam_policy_name ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
      ENDIF.
      TRY.
          ao_iam->deleterole( iv_rolename = av_iam_role_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────
*  TEST METHODS
* ─────────────────────────────────────────────────────────────────

  METHOD create_thing.
    " ---------------------------------------------------------------
    " Create a fresh, uniquely-named thing via the action under test,
    " tag it, verify it exists, then clean up.
    " ---------------------------------------------------------------
    DATA lv_uuid_string TYPE string.
    DATA(lv_uuid) = /awsex/cl_utils=>get_random_string( ).
    lv_uuid_string = lv_uuid.
    DATA(lv_new_thing) = CONV /aws1/iotthingname( |sap-abap-iot-cr-{ lv_uuid_string }| ).

    " Call the example action
    ao_iot_actions->create_thing( iv_thing_name = lv_new_thing ).

    " Verify the thing was created – describething must succeed
    DATA(lo_desc) = ao_iot->describething( iv_thingname = lv_new_thing ).
    cl_abap_unit_assert=>assert_equals(
      exp = lv_new_thing
      act = lo_desc->get_thingname( )
      msg = |Created thing name does not match| ).

    " Tag for convert_test tracking
    DATA(lv_new_arn) = lo_desc->get_thingarn( ).
    IF lv_new_arn IS NOT INITIAL.
      tag_iot_resource( lv_new_arn ).
    ENDIF.

    " Clean up
    ao_iot->deletething( iv_thingname = lv_new_thing ).
  ENDMETHOD.


  METHOD list_things.
    " ---------------------------------------------------------------
    " list_things must return at least the shared thing from setup.
    " ---------------------------------------------------------------
    DATA lt_things TYPE /aws1/cl_iotthingattribute=>tt_thingattributelist.

    ao_iot_actions->list_things(
      IMPORTING ot_things = lt_things ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_things
      msg = |list_things returned no things| ).

    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_things ASSIGNING FIELD-SYMBOL(<lo_thing>).
      IF <lo_thing>->get_thingname( ) = av_thing_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Shared thing '{ av_thing_name }' not found in list| ).
  ENDMETHOD.


  METHOD create_keys_and_certificate.
    " ---------------------------------------------------------------
    " create_keys_and_certificate must return a non-empty ID and ARN.
    " Tag it and clean up.
    " ---------------------------------------------------------------
    DATA lv_cert_id  TYPE /aws1/iotcertificateid.
    DATA lv_cert_arn TYPE /aws1/iotcertificatearn.

    ao_iot_actions->create_keys_and_certificate(
      IMPORTING
        ov_certificate_id  = lv_cert_id
        ov_certificate_arn = lv_cert_arn ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_cert_id
      msg = |Certificate ID is empty| ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lv_cert_arn
      msg = |Certificate ARN is empty| ).

    " Tag the certificate
    tag_iot_resource( lv_cert_arn ).

    " Clean up: deactivate then delete
    ao_iot->updatecertificate(
      iv_certificateid = lv_cert_id
      iv_newstatus     = 'INACTIVE' ).
    ao_iot->deletecertificate( iv_certificateid = lv_cert_id ).
  ENDMETHOD.


  METHOD attach_thing_principal.
    " ---------------------------------------------------------------
    " Create a fresh thing+cert, call action, verify via
    " listthingprincipals, then clean up.
    " ---------------------------------------------------------------
    DATA lv_uuid_string TYPE string.
    DATA(lv_uuid) = /awsex/cl_utils=>get_random_string( ).
    lv_uuid_string = lv_uuid.
    DATA(lv_att_thing) = CONV /aws1/iotthingname( |sap-abap-iot-att-{ lv_uuid_string }| ).

    DATA(lo_att_thing_rsp) = ao_iot->creatething( iv_thingname = lv_att_thing ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_att_thing_rsp
      msg = |attach_test: creatething failed| ).
    tag_iot_resource( lo_att_thing_rsp->get_thingarn( ) ).

    DATA(lo_att_cert) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_att_cert
      msg = |attach_test: createkeysandcertificate failed| ).
    DATA(lv_att_cert_id)  = lo_att_cert->get_certificateid( ).
    DATA(lv_att_cert_arn) = lo_att_cert->get_certificatearn( ).
    tag_iot_resource( lv_att_cert_arn ).

    " ─── Test ───
    ao_iot_actions->attach_thing_principal(
      iv_thing_name = lv_att_thing
      iv_principal  = lv_att_cert_arn ).

    " Verify the principal is now listed for the thing
    DATA(lo_princ_rsp) = ao_iot->listthingprincipals( iv_thingname = lv_att_thing ).
    DATA lv_attached TYPE abap_bool VALUE abap_false.
    LOOP AT lo_princ_rsp->get_principals( ) ASSIGNING FIELD-SYMBOL(<lv_p>).
      IF <lv_p>->get_value( ) = lv_att_cert_arn.
        lv_attached = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_attached
      msg = |Certificate was not attached to thing| ).

    " Clean up
    ao_iot->detachthingprincipal(
      iv_thingname = lv_att_thing
      iv_principal = lv_att_cert_arn ).
    ao_iot->updatecertificate(
      iv_certificateid = lv_att_cert_id
      iv_newstatus     = 'INACTIVE' ).
    ao_iot->deletecertificate( iv_certificateid = lv_att_cert_id ).
    ao_iot->deletething( iv_thingname = lv_att_thing ).
  ENDMETHOD.


  METHOD describe_endpoint.
    " ---------------------------------------------------------------
    " describe_endpoint must return an address containing amazonaws.com
    " ---------------------------------------------------------------
    DATA lv_endpoint TYPE /aws1/iotendpointaddress.

    ao_iot_actions->describe_endpoint(
      IMPORTING ov_endpoint_addr = lv_endpoint ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_endpoint
      msg = |Endpoint address is empty| ).

    cl_abap_unit_assert=>assert_differs(
      act = find( val = lv_endpoint sub = 'amazonaws.com' )
      exp = -1
      msg = |Endpoint does not look like an AWS endpoint: { lv_endpoint }| ).
  ENDMETHOD.


  METHOD list_certificates.
    " ---------------------------------------------------------------
    " list_certificates must return at least the shared certificate.
    " ---------------------------------------------------------------
    DATA lt_certs TYPE /aws1/cl_iotcertificate=>tt_certificates.

    ao_iot_actions->list_certificates(
      IMPORTING ot_certificates = lt_certs ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_certs
      msg = |list_certificates returned no certificates| ).

    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_certs ASSIGNING FIELD-SYMBOL(<lo_cert>).
      IF <lo_cert>->get_certificateid( ) = av_certificate_id.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Shared cert '{ av_certificate_id }' not found in list| ).
  ENDMETHOD.


  METHOD detach_thing_principal.
    " ---------------------------------------------------------------
    " Uses av_det_thing_name / av_det_cert_arn which were pre-attached
    " in class_setup.  We call the action, then verify with
    " listthingprincipals that the cert is no longer listed.
    " After the test we re-attach so teardown can clean up properly.
    " ---------------------------------------------------------------
    cl_abap_unit_assert=>assert_not_initial(
      act = av_det_thing_name
      msg = |det-thing name not initialised| ).
    cl_abap_unit_assert=>assert_not_initial(
      act = av_det_cert_arn
      msg = |det-cert ARN not initialised| ).

    " ─── Test ───
    ao_iot_actions->detach_thing_principal(
      iv_thing_name = av_det_thing_name
      iv_principal  = av_det_cert_arn ).

    " Verify detached
    DATA(lo_princ_rsp) = ao_iot->listthingprincipals( iv_thingname = av_det_thing_name ).
    DATA lv_still_attached TYPE abap_bool VALUE abap_false.
    LOOP AT lo_princ_rsp->get_principals( ) ASSIGNING FIELD-SYMBOL(<lv_p>).
      IF <lv_p>->get_value( ) = av_det_cert_arn.
        lv_still_attached = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_false(
      act = lv_still_attached
      msg = |Certificate is still attached after detach| ).

    " Re-attach so that teardown can detach-then-delete cleanly
    ao_iot->attachthingprincipal(
      iv_thingname = av_det_thing_name
      iv_principal = av_det_cert_arn ).
  ENDMETHOD.


  METHOD delete_certificate.
    " ---------------------------------------------------------------
    " Uses av_del_cert_id which was created and tagged in class_setup.
    " After the action call, describecertificate must raise not-found.
    " We CLEAR av_del_cert_id so teardown skips the already-deleted cert.
    " ---------------------------------------------------------------
    cl_abap_unit_assert=>assert_not_initial(
      act = av_del_cert_id
      msg = |del-cert ID was not initialised in class_setup| ).

    " ─── Test ───
    ao_iot_actions->delete_certificate( iv_certificate_id = av_del_cert_id ).

    " Verify deletion
    DATA lv_deleted TYPE abap_bool VALUE abap_false.
    TRY.
        ao_iot->describecertificate( iv_certificateid = av_del_cert_id ).
        " If we reach here the certificate still exists → assertion below will fail
      CATCH /aws1/cx_iotresourcenotfoundex.
        lv_deleted = abap_true.
      CATCH /aws1/cx_rt_generic.
        lv_deleted = abap_true.
    ENDTRY.

    cl_abap_unit_assert=>assert_true(
      act = lv_deleted
      msg = |Certificate { av_del_cert_id } was not deleted| ).

    " Signal teardown that this cert is gone
    CLEAR av_del_cert_id.
    CLEAR av_del_cert_arn.
  ENDMETHOD.


  METHOD create_topic_rule.
    " ---------------------------------------------------------------
    " Create a fresh rule via the action, verify with gettopicrule,
    " tag it, then clean up.
    " ---------------------------------------------------------------
    DATA lv_uuid_string TYPE string.
    DATA(lv_uuid) = /awsex/cl_utils=>get_random_string( ).
    lv_uuid_string = lv_uuid.
    DATA lv_new_rule TYPE /aws1/iotrulename.
    lv_new_rule = |SapAbapIotNew{ lv_uuid_string }|.
    TRANSLATE lv_new_rule USING '- '.
    CONDENSE lv_new_rule NO-GAPS.

    " ─── Test ───
    ao_iot_actions->create_topic_rule(
      iv_rule_name      = lv_new_rule
      iv_topic          = |iot/new/{ lv_uuid_string }|
      iv_sns_action_arn = av_sns_topic_arn
      iv_role_arn       = av_iam_role_arn ).

    " Verify rule exists and has the correct name
    DATA(lo_rule_rsp) = ao_iot->gettopicrule( iv_rulename = lv_new_rule ).
    cl_abap_unit_assert=>assert_equals(
      exp = lv_new_rule
      act = lo_rule_rsp->get_rule( )->get_rulename( )
      msg = |Created rule name does not match| ).

    " Tag the new rule
    DATA(lv_new_rule_arn) = lo_rule_rsp->get_rulearn( ).
    IF lv_new_rule_arn IS NOT INITIAL.
      tag_iot_resource( lv_new_rule_arn ).
    ENDIF.

    " Clean up
    ao_iot->deletetopicrule( iv_rulename = lv_new_rule ).
  ENDMETHOD.


  METHOD list_topic_rules.
    " ---------------------------------------------------------------
    " list_topic_rules must return at least the shared rule.
    " ---------------------------------------------------------------
    DATA lt_rules TYPE /aws1/cl_iottopicrulelistitem=>tt_topicrulelist.

    ao_iot_actions->list_topic_rules(
      IMPORTING ot_rules = lt_rules ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_rules
      msg = |list_topic_rules returned no rules| ).

    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_rules ASSIGNING FIELD-SYMBOL(<lo_rule>).
      IF <lo_rule>->get_rulename( ) = av_rule_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Shared rule '{ av_rule_name }' not found in list| ).
  ENDMETHOD.


  METHOD update_indexing_configuration.
    " ---------------------------------------------------------------
    " Call the action and then verify via getindexingconfiguration
    " that the mode is REGISTRY.
    " ---------------------------------------------------------------
    ao_iot_actions->update_indexing_configuration( ).

    DATA(lo_idx_rsp) = ao_iot->getindexingconfiguration( ).
    cl_abap_unit_assert=>assert_equals(
      exp = 'REGISTRY'
      act = lo_idx_rsp->get_thingindexingconf( )->get_thingindexingmode( )
      msg = |Indexing mode was not set to REGISTRY| ).
  ENDMETHOD.


  METHOD search_index.
    " ---------------------------------------------------------------
    " search_index must complete without error when the index is ready.
    " We poll up to 90 s (18 × 5 s) for the index to become active.
    " Once the call succeeds without CX_IOTINDEXNOTREADYEX the test
    " passes – the thing may not yet be indexed which is fine.
    " ---------------------------------------------------------------
    DATA lt_docs       TYPE /aws1/cl_iotthingdocument=>tt_thingdocumentlist.
    DATA lv_ready      TYPE abap_bool VALUE abap_false.
    DATA lv_retries    TYPE i         VALUE 0.
    CONSTANTS cv_max_retries TYPE i   VALUE 18.

    WHILE lv_retries < cv_max_retries AND lv_ready = abap_false.
      TRY.
          ao_iot_actions->search_index(
            iv_query         = |thingName:{ av_thing_name }|
            IMPORTING
              ot_things      = lt_docs ).
          lv_ready = abap_true.        " call completed without exception
        CATCH /aws1/cx_iotindexnotreadyex.
          lv_retries = lv_retries + 1.
          IF lv_retries < cv_max_retries.
            WAIT UP TO 5 SECONDS.
          ENDIF.
        CATCH /aws1/cx_rt_generic INTO DATA(lo_ex).
          cl_abap_unit_assert=>fail(
            msg = |search_index failed: { lo_ex->get_text( ) }| ).
      ENDTRY.
    ENDWHILE.

    cl_abap_unit_assert=>assert_true(
      act = lv_ready
      msg = |Index was not ready after { cv_max_retries * 5 } seconds| ).
  ENDMETHOD.


  METHOD delete_thing.
    " ---------------------------------------------------------------
    " Uses av_del_thing_name which was created and tagged in class_setup.
    " After the action, describething must raise not-found.
    " We CLEAR av_del_thing_name so teardown skips it.
    " ---------------------------------------------------------------
    cl_abap_unit_assert=>assert_not_initial(
      act = av_del_thing_name
      msg = |del-thing name was not initialised in class_setup| ).

    " ─── Test ───
    ao_iot_actions->delete_thing( iv_thing_name = av_del_thing_name ).

    " Verify deletion
    DATA lv_deleted TYPE abap_bool VALUE abap_false.
    TRY.
        ao_iot->describething( iv_thingname = av_del_thing_name ).
        " If we reach here the thing still exists → assertion below fails
      CATCH /aws1/cx_iotresourcenotfoundex.
        lv_deleted = abap_true.
      CATCH /aws1/cx_rt_generic.
        lv_deleted = abap_true.
    ENDTRY.

    cl_abap_unit_assert=>assert_true(
      act = lv_deleted
      msg = |Thing '{ av_del_thing_name }' was not deleted| ).

    " Signal teardown that this thing is gone
    CLEAR av_del_thing_name.
    CLEAR av_del_thing_arn.
  ENDMETHOD.


  METHOD delete_topic_rule.
    " ---------------------------------------------------------------
    " Uses av_del_rule_name which was created and tagged in class_setup.
    " After the action, gettopicrule must raise not-found.
    " We CLEAR av_del_rule_name so teardown skips it.
    " ---------------------------------------------------------------
    cl_abap_unit_assert=>assert_not_initial(
      act = av_del_rule_name
      msg = |del-rule name was not initialised in class_setup| ).

    " ─── Test ───
    ao_iot_actions->delete_topic_rule( iv_rule_name = av_del_rule_name ).

    " Verify deletion
    DATA lv_deleted TYPE abap_bool VALUE abap_false.
    TRY.
        ao_iot->gettopicrule( iv_rulename = av_del_rule_name ).
        " If we reach here the rule still exists → assertion below fails
      CATCH /aws1/cx_iotresourcenotfoundex.
        lv_deleted = abap_true.
      CATCH /aws1/cx_rt_generic.
        lv_deleted = abap_true.
    ENDTRY.

    cl_abap_unit_assert=>assert_true(
      act = lv_deleted
      msg = |Topic rule '{ av_del_rule_name }' was not deleted| ).

    " Signal teardown that this rule is gone
    CLEAR av_del_rule_name.
  ENDMETHOD.

ENDCLASS.
