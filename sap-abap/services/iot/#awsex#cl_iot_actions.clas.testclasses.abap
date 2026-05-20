" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_iot_actions DEFINITION DEFERRED.
CLASS /awsex/cl_iot_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_iot_actions.

CLASS ltc_awsex_cl_iot_actions DEFINITION FOR TESTING
  DURATION LONG
  RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " ── Service clients ─────────────────────────────────────────────────────
    CLASS-DATA ao_iot         TYPE REF TO /aws1/if_iot.
    CLASS-DATA ao_iop         TYPE REF TO /aws1/if_iop.
    CLASS-DATA ao_iam         TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_sns         TYPE REF TO /aws1/if_sns.
    CLASS-DATA ao_session     TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_iot_actions TYPE REF TO /awsex/cl_iot_actions.

    " ── Shared long-lived resources (created in class_setup) ────────────────
    " Main "read" thing used by list/attach/detach tests
    CLASS-DATA av_thing_name     TYPE /aws1/iotthingname.
    CLASS-DATA av_thing_arn      TYPE /aws1/iotthingarn.
    " Shadow thing used by update/get shadow tests
    CLASS-DATA av_shadow_thing   TYPE /aws1/iotthingname.
    " Certificate shared by attach/detach tests
    CLASS-DATA av_cert_id        TYPE /aws1/iotcertificateid.
    CLASS-DATA av_cert_arn       TYPE /aws1/iotcertificatearn.
    " Topic rule for list_topic_rules test
    CLASS-DATA av_rule_name      TYPE /aws1/iotrulename.
    " Real SNS topic ARN for topic rule action target
    CLASS-DATA av_sns_topic_arn  TYPE /aws1/iotarn.
    " Real IAM role with iot.amazonaws.com trust + sns:Publish inline policy
    CLASS-DATA av_role_arn       TYPE /aws1/iotarn.
    CLASS-DATA av_role_name      TYPE /aws1/iamrolenametype.

    " ── Dedicated per-test mutation resources ───────────────────────────────
    CLASS-DATA av_del_thing_name TYPE /aws1/iotthingname.
    CLASS-DATA av_del_cert_id    TYPE /aws1/iotcertificateid.
    CLASS-DATA av_del_cert_arn   TYPE /aws1/iotcertificatearn.
    CLASS-DATA av_del_rule_name  TYPE /aws1/iotrulename.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " ── Helper ──────────────────────────────────────────────────────────────
    CLASS-METHODS tag_thing
      IMPORTING iv_thing_arn TYPE /aws1/iotresourcearn.

    " ── Test methods ────────────────────────────────────────────────────────
    METHODS create_thing                  FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_things                   FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS create_keys_and_certificate   FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS attach_thing_principal        FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS describe_endpoint             FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_certificates             FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS detach_thing_principal        FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_certificate            FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS create_topic_rule             FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_topic_rules              FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_indexing_configuration FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS search_index                  FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_thing                  FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_topic_rule             FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_thing_shadow           FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS get_thing_shadow              FOR TESTING RAISING /aws1/cx_rt_generic.

ENDCLASS.


CLASS ltc_awsex_cl_iot_actions IMPLEMENTATION.

  " ═══════════════════════════════════════════════════════════════════════════
  METHOD class_setup.
  " ═══════════════════════════════════════════════════════════════════════════
    ao_session     = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_iot         = /aws1/cl_iot_factory=>create( ao_session ).
    ao_iop         = /aws1/cl_iop_factory=>create( ao_session ).
    ao_iam         = /aws1/cl_iam_factory=>create( ao_session ).
    ao_sns         = /aws1/cl_sns_factory=>create( ao_session ).
    ao_iot_actions = NEW /awsex/cl_iot_actions( ).

    " ── Unique suffix via ABAP util ─────────────────────────────────────────
    DATA(lv_sfx) = to_lower( /awsex/cl_utils=>get_random_string( ) ).
    DATA(lv_sfx8) = lv_sfx(8).

    DATA(lv_account) = ao_session->get_account_id( ).
    DATA(lv_region)  = ao_session->get_region( ).

    " ── Resource names ──────────────────────────────────────────────────────
    av_thing_name     = |iot-tst-thing-{ lv_sfx8 }|.
    av_shadow_thing   = |iot-tst-shadow-{ lv_sfx8 }|.
    av_del_thing_name = |iot-tst-del-thing-{ lv_sfx8 }|.
    av_rule_name      = |iotTstRule{ lv_sfx8 }|.
    av_del_rule_name  = |iotTstDelRule{ lv_sfx8 }|.
    av_role_name      = |iot-tst-role-{ lv_sfx8 }|.

    " ── 1. Create IAM role (iot.amazonaws.com trust + SNS publish policy) ───
    DATA(lv_trust) = |{"Version":"2012-10-17","Statement":[{"Effect":"Allow",| &&
      |"Principal":{"Service":"iot.amazonaws.com"},"Action":"sts:AssumeRole"}]}|.

    TRY.
        DATA(lo_role_rsp) = ao_iam->createrole(
          iv_rolename                 = av_role_name
          iv_assumerolepolicydocument = lv_trust
          it_tags = VALUE /aws1/cl_iamtag=>tt_taglisttype(
            ( NEW /aws1/cl_iamtag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).
        av_role_arn = lo_role_rsp->get_role( )->get_arn( ).
      CATCH /aws1/cx_iamentityalrdyexex.
        DATA(lo_get_role) = ao_iam->getrole( iv_rolename = av_role_name ).
        av_role_arn = lo_get_role->get_role( )->get_arn( ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex1).
        cl_abap_unit_assert=>fail(
          msg = |Failed to create IAM role: { lo_ex1->get_text( ) }| ).
    ENDTRY.

    " Attach an inline policy that allows publishing to any SNS topic
    DATA(lv_sns_policy) = |{"Version":"2012-10-17","Statement":[{"Effect":"Allow",| &&
      |"Action":"sns:Publish","Resource":"*"}]}|.
    TRY.
        ao_iam->putrolepolicy(
          iv_rolename     = av_role_name
          iv_policyname   = |iot-tst-sns-{ lv_sfx8 }|
          iv_policydocument = lv_sns_policy ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex_iam).
        cl_abap_unit_assert=>fail(
          msg = |Failed to attach inline policy to role: { lo_ex_iam->get_text( ) }| ).
    ENDTRY.

    " Wait for IAM propagation
    WAIT UP TO 10 SECONDS.

    " ── 2. Create SNS topic (action target for topic rules) ─────────────────
    DATA(lv_sns_name) = |iot-tst-sns-{ lv_sfx8 }|.
    TRY.
        DATA(lo_sns_rsp) = ao_sns->createtopic(
          iv_name = lv_sns_name
          it_tags = VALUE /aws1/cl_snstag=>tt_taglist(
            ( NEW /aws1/cl_snstag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).
        av_sns_topic_arn = lo_sns_rsp->get_topicarn( ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex2).
        cl_abap_unit_assert=>fail(
          msg = |Failed to create SNS topic: { lo_ex2->get_text( ) }| ).
    ENDTRY.

    " ── 3. Create shared "read" thing ───────────────────────────────────────
    TRY.
        DATA(lo_thing_rsp) = ao_iot->creatething( iv_thingname = av_thing_name ).
        av_thing_arn = lo_thing_rsp->get_thingarn( ).
      CATCH /aws1/cx_iotresrcalrdyexistsex.
        DATA(lo_desc) = ao_iot->describething( iv_thingname = av_thing_name ).
        av_thing_arn = lo_desc->get_thingarn( ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex3).
        cl_abap_unit_assert=>fail(
          msg = |Failed to create thing { av_thing_name }: { lo_ex3->get_text( ) }| ).
    ENDTRY.
    tag_thing( av_thing_arn ).

    " ── 4. Create shadow test thing ─────────────────────────────────────────
    TRY.
        DATA(lo_shadow_rsp) = ao_iot->creatething( iv_thingname = av_shadow_thing ).
        tag_thing( lo_shadow_rsp->get_thingarn( ) ).
      CATCH /aws1/cx_iotresrcalrdyexistsex.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex4).
        cl_abap_unit_assert=>fail(
          msg = |Failed to create shadow thing: { lo_ex4->get_text( ) }| ).
    ENDTRY.

    " ── 5. Create dedicated thing for delete_thing test ─────────────────────
    TRY.
        DATA(lo_del_thing) = ao_iot->creatething( iv_thingname = av_del_thing_name ).
        tag_thing( lo_del_thing->get_thingarn( ) ).
      CATCH /aws1/cx_iotresrcalrdyexistsex.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex5).
        cl_abap_unit_assert=>fail(
          msg = |Failed to create del-thing: { lo_ex5->get_text( ) }| ).
    ENDTRY.

    " ── 6. Create certificate shared by attach/detach tests ─────────────────
    TRY.
        DATA(lo_cert_rsp) = ao_iot->createkeysandcertificate( abap_true ).
        av_cert_id  = lo_cert_rsp->get_certificateid( ).
        av_cert_arn = lo_cert_rsp->get_certificatearn( ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex6).
        cl_abap_unit_assert=>fail(
          msg = |Failed to create certificate: { lo_ex6->get_text( ) }| ).
    ENDTRY.

    " ── 7. Create dedicated certificate for delete_certificate test ──────────
    TRY.
        DATA(lo_del_cert) = ao_iot->createkeysandcertificate( abap_true ).
        av_del_cert_id  = lo_del_cert->get_certificateid( ).
        av_del_cert_arn = lo_del_cert->get_certificatearn( ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex7).
        cl_abap_unit_assert=>fail(
          msg = |Failed to create del-cert: { lo_ex7->get_text( ) }| ).
    ENDTRY.

    " ── 8. Create shared topic rule for list_topic_rules test ───────────────
    DATA lt_acts TYPE /aws1/cl_iotaction=>tt_actionlist.
    APPEND NEW /aws1/cl_iotaction(
      io_sns = NEW /aws1/cl_iotsnsaction(
        iv_targetarn     = av_sns_topic_arn
        iv_rolearn       = av_role_arn
        iv_messageformat = 'RAW' )
    ) TO lt_acts.
    TRY.
        ao_iot->createtopicrule(
          iv_rulename         = av_rule_name
          io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
            iv_sql     = |SELECT * FROM 'tst/topic/{ lv_sfx8 }'|
            it_actions = lt_acts ) ).
      CATCH /aws1/cx_iotresrcalrdyexistsex.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex8).
        cl_abap_unit_assert=>fail(
          msg = |Failed to create shared rule: { lo_ex8->get_text( ) }| ).
    ENDTRY.

    " ── 9. Create dedicated topic rule for delete_topic_rule test ───────────
    DATA lt_del_acts TYPE /aws1/cl_iotaction=>tt_actionlist.
    APPEND NEW /aws1/cl_iotaction(
      io_sns = NEW /aws1/cl_iotsnsaction(
        iv_targetarn     = av_sns_topic_arn
        iv_rolearn       = av_role_arn
        iv_messageformat = 'RAW' )
    ) TO lt_del_acts.
    TRY.
        ao_iot->createtopicrule(
          iv_rulename         = av_del_rule_name
          io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
            iv_sql     = |SELECT * FROM 'del/topic/{ lv_sfx8 }'|
            it_actions = lt_del_acts ) ).
      CATCH /aws1/cx_iotresrcalrdyexistsex.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex9).
        cl_abap_unit_assert=>fail(
          msg = |Failed to create del-rule: { lo_ex9->get_text( ) }| ).
    ENDTRY.

  ENDMETHOD.


  " ═══════════════════════════════════════════════════════════════════════════
  METHOD tag_thing.
  " ═══════════════════════════════════════════════════════════════════════════
    " IoT things cannot be tagged at creation time — tag them via tagresource.
    TRY.
        ao_iot->tagresource(
          iv_resourcearn = iv_thing_arn
          it_tags = VALUE /aws1/cl_iottag=>tt_taglist(
            ( NEW /aws1/cl_iottag(
                iv_key   = 'convert_test'
                iv_value = 'true' ) ) ) ).
      CATCH /aws1/cx_rt_generic.
        " Best-effort; do not fail setup if tagging is not permitted
    ENDTRY.
  ENDMETHOD.


  " ═══════════════════════════════════════════════════════════════════════════
  METHOD class_teardown.
  " ═══════════════════════════════════════════════════════════════════════════
    " Every cleanup is in its own TRY/CATCH so one failure does not block others.

    " ── Detach cert from shared thing then delete cert ───────────────────────
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
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iot->deletecertificate( iv_certificateid = av_cert_id ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ── Delete del-cert (may already be deleted by test) ────────────────────
    TRY.
        ao_iot->detachthingprincipal(
          iv_thingname = av_thing_name
          iv_principal = av_del_cert_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iot->updatecertificate(
          iv_certificateid = av_del_cert_id
          iv_newstatus     = 'INACTIVE' ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iot->deletecertificate( iv_certificateid = av_del_cert_id ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ── Delete things ────────────────────────────────────────────────────────
    TRY.
        ao_iot->deletething( iv_thingname = av_thing_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iot->deletething( iv_thingname = av_shadow_thing ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iot->deletething( iv_thingname = av_del_thing_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ── Delete topic rules ───────────────────────────────────────────────────
    TRY.
        ao_iot->deletetopicrule( iv_rulename = av_rule_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iot->deletetopicrule( iv_rulename = av_del_rule_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ── Delete SNS topic ─────────────────────────────────────────────────────
    TRY.
        ao_sns->deletetopic( iv_topicarn = av_sns_topic_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ── Delete all inline policies then the IAM role ────────────────────────
    " List and delete every inline policy to avoid 'cannot delete entity' error.
    TRY.
        DATA(lo_rp_list) = ao_iam->listrolepolicies( iv_rolename = av_role_name ).
        LOOP AT lo_rp_list->get_policynames( ) INTO DATA(lo_pname).
          TRY.
              ao_iam->deleterolepolicy(
                iv_rolename   = av_role_name
                iv_policyname = lo_pname->get_value( ) ).
            CATCH /aws1/cx_rt_generic.
          ENDTRY.
        ENDLOOP.
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iam->deleterole( iv_rolename = av_role_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

  ENDMETHOD.


  " ───────────────────────────────────────────────────────────────────────────
  METHOD create_thing.
  " ───────────────────────────────────────────────────────────────────────────
    " Use a fresh name to avoid conflicts with the shared thing.
    DATA(lv_sfx) = to_lower( /awsex/cl_utils=>get_random_string( ) ).
    DATA(lv_new_name) = CONV /aws1/iotthingname(
      |iot-tst-ct-{ lv_sfx(8) }| ).

    DATA(lo_result) = ao_iot_actions->create_thing(
      iv_thing_name = lv_new_name ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = |create_thing did not return a result object| ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_thingname( )
      exp = lv_new_name
      msg = |Returned thing name does not match requested name| ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_thingarn( )
      msg = |Thing ARN must not be empty| ).

    " Tag the newly created thing
    tag_thing( lo_result->get_thingarn( ) ).

    " Cleanup
    TRY.
        ao_iot->deletething( iv_thingname = lv_new_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  " ───────────────────────────────────────────────────────────────────────────
  METHOD list_things.
  " ───────────────────────────────────────────────────────────────────────────
    DATA(lt_things) = ao_iot_actions->list_things( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_things
      msg = |list_things returned an empty table| ).

    " The shared thing created in class_setup must appear in the list.
    DATA lv_found TYPE abap_bool VALUE abap_false.
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


  " ───────────────────────────────────────────────────────────────────────────
  METHOD create_keys_and_certificate.
  " ───────────────────────────────────────────────────────────────────────────
    DATA(lo_result) = ao_iot_actions->create_keys_and_certificate( ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = |create_keys_and_certificate returned no result| ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificateid( )
      msg = |Certificate ID must not be empty| ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificatearn( )
      msg = |Certificate ARN must not be empty| ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificatepem( )
      msg = |Certificate PEM must not be empty| ).

    " Cleanup the certificate created during this test.
    DATA(lv_id) = lo_result->get_certificateid( ).
    TRY.
        ao_iot->updatecertificate(
          iv_certificateid = lv_id
          iv_newstatus     = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = lv_id ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  " ───────────────────────────────────────────────────────────────────────────
  METHOD attach_thing_principal.
  " ───────────────────────────────────────────────────────────────────────────
    " The shared certificate may have been left attached by a previous run;
    " ensure it is detached first so the test is deterministic.
    TRY.
        ao_iot->detachthingprincipal(
          iv_thingname = av_thing_name
          iv_principal = av_cert_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    ao_iot_actions->attach_thing_principal(
      iv_thing_name = av_thing_name
      iv_principal  = av_cert_arn ).

    " Verify: the certificate ARN must appear in the list of thing principals.
    DATA(lo_list_rsp) = ao_iot->listthingprincipals(
      iv_thingname = av_thing_name ).

    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_list_rsp->get_principals( ) INTO DATA(lo_p).
      IF lo_p->get_value( ) = av_cert_arn.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Certificate { av_cert_arn } not in principals of { av_thing_name }| ).
  ENDMETHOD.


  " ───────────────────────────────────────────────────────────────────────────
  METHOD describe_endpoint.
  " ───────────────────────────────────────────────────────────────────────────
    DATA(lv_endpoint) = ao_iot_actions->describe_endpoint(
      iv_endpoint_type = 'iot:Data-ATS' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_endpoint
      msg = |describe_endpoint returned an empty address| ).

    " A valid ATS data endpoint hostname always contains 'iot'.
    cl_abap_unit_assert=>assert_true(
      act = boolc( lv_endpoint CS 'iot' )
      msg = |Endpoint does not look like an IoT address: { lv_endpoint }| ).
  ENDMETHOD.


  " ───────────────────────────────────────────────────────────────────────────
  METHOD list_certificates.
  " ───────────────────────────────────────────────────────────────────────────
    DATA(lt_certs) = ao_iot_actions->list_certificates( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_certs
      msg = |list_certificates returned an empty table| ).

    " The shared certificate from class_setup must be in the list.
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_certs INTO DATA(lo_cert).
      IF lo_cert->get_certificateid( ) = av_cert_id.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Certificate { av_cert_id } not found in list_certificates| ).
  ENDMETHOD.


  " ───────────────────────────────────────────────────────────────────────────
  METHOD detach_thing_principal.
  " ───────────────────────────────────────────────────────────────────────────
    " Ensure the cert is attached before trying to detach it.
    TRY.
        ao_iot->attachthingprincipal(
          iv_thingname = av_thing_name
          iv_principal = av_cert_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    ao_iot_actions->detach_thing_principal(
      iv_thing_name = av_thing_name
      iv_principal  = av_cert_arn ).

    " Verify: cert must NOT appear in the principals list after detach.
    DATA(lo_list_rsp) = ao_iot->listthingprincipals(
      iv_thingname = av_thing_name ).

    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_list_rsp->get_principals( ) INTO DATA(lo_p).
      IF lo_p->get_value( ) = av_cert_arn.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_false(
      act = lv_found
      msg = |Certificate { av_cert_arn } still attached after detach_thing_principal| ).
  ENDMETHOD.


  " ───────────────────────────────────────────────────────────────────────────
  METHOD delete_certificate.
  " ───────────────────────────────────────────────────────────────────────────
    " av_del_cert_id was created specifically for this test in class_setup.
    ao_iot_actions->delete_certificate(
      iv_certificate_id = av_del_cert_id ).

    " Verify: describe should raise ResourceNotFoundException.
    DATA lv_deleted TYPE abap_bool VALUE abap_false.
    TRY.
        ao_iot->describecertificate( iv_certificateid = av_del_cert_id ).
      CATCH /aws1/cx_iotresourcenotfoundex.
        lv_deleted = abap_true.
      CATCH /aws1/cx_rt_generic.
        lv_deleted = abap_true.
    ENDTRY.

    cl_abap_unit_assert=>assert_true(
      act = lv_deleted
      msg = |Certificate { av_del_cert_id } still exists after delete_certificate| ).
  ENDMETHOD.


  " ───────────────────────────────────────────────────────────────────────────
  METHOD create_topic_rule.
  " ───────────────────────────────────────────────────────────────────────────
    " Use a unique rule name so it does not conflict with the shared one.
    DATA(lv_sfx) = to_lower( /awsex/cl_utils=>get_random_string( ) ).
    DATA(lv_new_rule) = CONV /aws1/iotrulename(
      |iotTstCrt{ lv_sfx(8) }| ).

    ao_iot_actions->create_topic_rule(
      iv_rule_name      = lv_new_rule
      iv_topic          = |tst/crt/{ lv_sfx(8) }|
      iv_sns_action_arn = av_sns_topic_arn
      iv_role_arn       = av_role_arn ).

    " Verify: gettopicrule must return the rule object.
    DATA(lo_rule_rsp) = ao_iot->gettopicrule( iv_rulename = lv_new_rule ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_rule_rsp
      msg = |Topic rule { lv_new_rule } not found after create_topic_rule| ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_rule_rsp->get_rule( )->get_rulename( )
      exp = lv_new_rule
      msg = |Rule name mismatch| ).

    " Cleanup
    TRY.
        ao_iot->deletetopicrule( iv_rulename = lv_new_rule ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  " ───────────────────────────────────────────────────────────────────────────
  METHOD list_topic_rules.
  " ───────────────────────────────────────────────────────────────────────────
    DATA(lt_rules) = ao_iot_actions->list_topic_rules( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_rules
      msg = |list_topic_rules returned an empty table| ).

    " The shared rule created in class_setup must be present.
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_rules INTO DATA(lo_rule).
      IF lo_rule->get_rulename( ) = av_rule_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Rule { av_rule_name } not found in list_topic_rules| ).
  ENDMETHOD.


  " ───────────────────────────────────────────────────────────────────────────
  METHOD update_indexing_configuration.
  " ───────────────────────────────────────────────────────────────────────────
    ao_iot_actions->update_indexing_configuration( ).

    " Read the configuration back and confirm REGISTRY mode is set.
    DATA(lo_cfg) = ao_iot->getindexingconfiguration( ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_cfg->get_thingindexingconf( )
      msg = |getindexingconfiguration returned no thingIndexingConf| ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_cfg->get_thingindexingconf( )->get_thingindexingmode( )
      exp = 'REGISTRY'
      msg = |Thing indexing mode must be REGISTRY after update| ).
  ENDMETHOD.


  " ───────────────────────────────────────────────────────────────────────────
  METHOD search_index.
  " ───────────────────────────────────────────────────────────────────────────
    " Ensure REGISTRY indexing is enabled (idempotent).
    TRY.
        ao_iot->updateindexingconfiguration(
          io_thingindexingconf = NEW /aws1/cl_iotthingindexingconf(
            iv_thingindexingmode = 'REGISTRY' ) ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Poll until the index is ACTIVE — fail the test if it does not become
    " active within ~90 s (18 × 5 s); do NOT skip.
    DATA lv_idx_active TYPE abap_bool VALUE abap_false.
    DO 18 TIMES.
      TRY.
          DATA(lo_idx) = ao_iot->describeindex( iv_indexname = 'AWS_Things' ).
          IF lo_idx->get_indexstatus( ) = 'ACTIVE'.
            lv_idx_active = abap_true.
            EXIT.
          ENDIF.
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
      WAIT UP TO 5 SECONDS.
    ENDDO.

    cl_abap_unit_assert=>assert_true(
      act = lv_idx_active
      msg = |AWS_Things index did not become ACTIVE within 90 s| ).

    " Search for the shared thing by its exact name.
    DATA(lt_things) = ao_iot_actions->search_index(
      iv_query_string = |thingName:{ av_thing_name }| ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_things
      msg = |search_index returned no results for thingName:{ av_thing_name }| ).

    " Verify the expected thing is in the result.
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_things INTO DATA(lo_thing).
      IF lo_thing->get_thingname( ) = av_thing_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |{ av_thing_name } not found in search_index result| ).
  ENDMETHOD.


  " ───────────────────────────────────────────────────────────────────────────
  METHOD delete_thing.
  " ───────────────────────────────────────────────────────────────────────────
    " av_del_thing_name was created specifically for this test in class_setup.
    ao_iot_actions->delete_thing(
      iv_thing_name = av_del_thing_name ).

    " Verify: describething must raise ResourceNotFoundException.
    DATA lv_deleted TYPE abap_bool VALUE abap_false.
    TRY.
        ao_iot->describething( iv_thingname = av_del_thing_name ).
      CATCH /aws1/cx_iotresourcenotfoundex.
        lv_deleted = abap_true.
      CATCH /aws1/cx_rt_generic.
        lv_deleted = abap_true.
    ENDTRY.

    cl_abap_unit_assert=>assert_true(
      act = lv_deleted
      msg = |Thing { av_del_thing_name } still exists after delete_thing| ).
  ENDMETHOD.


  " ───────────────────────────────────────────────────────────────────────────
  METHOD delete_topic_rule.
  " ───────────────────────────────────────────────────────────────────────────
    " av_del_rule_name was created specifically for this test in class_setup.
    ao_iot_actions->delete_topic_rule(
      iv_rule_name = av_del_rule_name ).

    " Verify: gettopicrule must raise ResourceNotFoundException after deletion.
    DATA lv_deleted TYPE abap_bool VALUE abap_false.
    TRY.
        ao_iot->gettopicrule( iv_rulename = av_del_rule_name ).
      CATCH /aws1/cx_iotresourcenotfoundex.
        lv_deleted = abap_true.
    ENDTRY.

    cl_abap_unit_assert=>assert_true(
      act = lv_deleted
      msg = |Topic rule { av_del_rule_name } still exists after delete_topic_rule| ).
  ENDMETHOD.


  " ───────────────────────────────────────────────────────────────────────────
  METHOD update_thing_shadow.
  " ───────────────────────────────────────────────────────────────────────────
    DATA(lv_state) =
      |{"state":{"reported":{"temperature":22,"unit":"Celsius"}}}|.

    ao_iot_actions->update_thing_shadow(
      iv_thing_name   = av_shadow_thing
      iv_shadow_state = lv_state ).

    " Verify by reading the shadow back directly via the IOP client.
    DATA(lo_rsp) = ao_iop->getthingshadow( iv_thingname = av_shadow_thing ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_rsp
      msg = |Shadow payload not returned after update_thing_shadow| ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_rsp->get_payload( )
      msg = |Shadow payload must not be empty| ).

    DATA(lv_json) = cl_abap_codepage=>convert_from(
      source   = lo_rsp->get_payload( )
      codepage = 'UTF-8' ).

    cl_abap_unit_assert=>assert_true(
      act = boolc( lv_json CS 'temperature' )
      msg = |Shadow JSON missing expected field 'temperature': { lv_json }| ).
  ENDMETHOD.


  " ───────────────────────────────────────────────────────────────────────────
  METHOD get_thing_shadow.
  " ───────────────────────────────────────────────────────────────────────────
    " Pre-condition: write a known shadow so we can assert on its content.
    DATA(lv_state) =
      |{"state":{"reported":{"humidity":60,"unit":"percent"}}}|.
    DATA(lv_xs) = cl_abap_codepage=>convert_to(
      source   = lv_state
      codepage = 'UTF-8' ).
    ao_iop->updatethingshadow(
      iv_thingname = av_shadow_thing
      iv_payload   = lv_xs ).

    DATA(lv_json) = ao_iot_actions->get_thing_shadow(
      iv_thing_name = av_shadow_thing ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_json
      msg = |get_thing_shadow returned an empty string| ).

    cl_abap_unit_assert=>assert_true(
      act = boolc( lv_json CS 'humidity' )
      msg = |Shadow JSON missing expected field 'humidity': { lv_json }| ).
  ENDMETHOD.

ENDCLASS.
