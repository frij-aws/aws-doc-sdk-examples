" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_iot_actions DEFINITION DEFERRED.
CLASS /awsex/cl_iot_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_iot_actions.

CLASS ltc_awsex_cl_iot_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " Service clients
    CLASS-DATA ao_iot     TYPE REF TO /aws1/if_iot.
    CLASS-DATA ao_iam     TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_sns     TYPE REF TO /aws1/if_sns.
    CLASS-DATA ao_session TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_actions TYPE REF TO /awsex/cl_iot_actions.

    " Shared resources created in class_setup — kept for list/read tests.
    CLASS-DATA av_thing_name  TYPE /aws1/iotthingname.
    CLASS-DATA av_thing_arn   TYPE /aws1/iotthingarn.
    CLASS-DATA av_cert_id     TYPE /aws1/iotcertificateid.
    CLASS-DATA av_cert_arn    TYPE /aws1/iotcertificatearn.
    CLASS-DATA av_rule_name   TYPE /aws1/iotrulename.
    CLASS-DATA av_sns_arn     TYPE /aws1/iotawsarn.
    CLASS-DATA av_role_arn    TYPE /aws1/iotawsarn.
    CLASS-DATA av_iam_role    TYPE /aws1/iamrolenametype.
    CLASS-DATA av_uuid        TYPE string.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " Poll until DescribeThing succeeds — ensures thing is visible in the registry.
    CLASS-METHODS wait_for_thing
      IMPORTING iv_thing_name TYPE /aws1/iotthingname
      RAISING   /aws1/cx_rt_generic.

    " Poll until DescribeIndex shows the AWS_Things index is ACTIVE.
    CLASS-METHODS wait_for_index_active
      RAISING /aws1/cx_rt_generic.

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
    METHODS delete_topic_rule             FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_thing                  FOR TESTING RAISING /aws1/cx_rt_generic.

ENDCLASS.


CLASS ltc_awsex_cl_iot_actions IMPLEMENTATION.

" ─────────────────────────────────────────────────────────────────────────────
" class_setup
"   Creates every shared resource that read/list tests rely on, tagged with
"   'convert_test' so any leaked resource can be found and cleaned up manually.
"   All mutation tests (attach, detach, delete_*) create their OWN resources.
" ─────────────────────────────────────────────────────────────────────────────
  METHOD class_setup.
    ao_session = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    ao_iot     = /aws1/cl_iot_factory=>create( ao_session ).
    ao_iam     = /aws1/cl_iam_factory=>create( ao_session ).
    ao_sns     = /aws1/cl_sns_factory=>create( ao_session ).
    ao_actions = NEW /awsex/cl_iot_actions( ).

    " ── Unique suffix ──────────────────────────────────────────────────────
    av_uuid = /awsex/cl_utils=>get_random_string( ).
    CONDENSE av_uuid NO-GAPS.
    av_uuid = to_lower( av_uuid ).

    DATA(lv_region)  = ao_session->get_region( ).
    DATA(lv_account) = ao_session->get_account_id( ).

    " ── IAM role that IoT can assume to publish to SNS ─────────────────────
    "   The topic-rule test and the shared setup rule both need a real role.
    DATA lv_trust TYPE string.
    lv_trust =
      '{' &&
        '"Version":"2012-10-17",' &&
        '"Statement":[{' &&
          '"Effect":"Allow",' &&
          '"Principal":{"Service":"iot.amazonaws.com"},' &&
          '"Action":"sts:AssumeRole"' &&
        '}]' &&
      '}'.

    av_iam_role = |sap-abap-iot-role-{ av_uuid }|.
    DATA(lo_role) = ao_iam->createrole(
      iv_rolename                 = av_iam_role
      iv_assumerolepolicydocument = lv_trust
      iv_description              = 'SAP ABAP IoT example test role'
      it_tags = VALUE /aws1/cl_iamtag=>tt_taglisttype(
        ( NEW /aws1/cl_iamtag( iv_key = 'convert_test' iv_value = 'true' ) )
      )
    ).
    av_role_arn = lo_role->get_role( )->get_arn( ).

    IF av_role_arn IS INITIAL.
      cl_abap_unit_assert=>fail( msg = 'class_setup: IAM role creation returned empty ARN' ).
    ENDIF.

    " Attach inline policy: allow sns:Publish on *
    DATA lv_pol_doc TYPE string.
    lv_pol_doc =
      '{' &&
        '"Version":"2012-10-17",' &&
        '"Statement":[{' &&
          '"Effect":"Allow",' &&
          '"Action":"sns:Publish",' &&
          '"Resource":"*"' &&
        '}]' &&
      '}'.
    ao_iam->putrolepolicy(
      iv_rolename     = av_iam_role
      iv_policyname   = 'AllowSNSPublish'
      iv_policydocument = lv_pol_doc
    ).

    " Allow a few seconds for IAM propagation before IoT uses the role.
    WAIT UP TO 10 SECONDS.

    " ── SNS topic that the topic rule will publish to ───────────────────────
    DATA(lv_sns_topic_name) = |sap-abap-iot-{ av_uuid }|.
    DATA(lo_sns_create) = ao_sns->createtopic(
      iv_name = lv_sns_topic_name
      it_tags = VALUE /aws1/cl_snstag=>tt_taglist(
        ( NEW /aws1/cl_snstag( iv_key = 'convert_test' iv_value = 'true' ) )
      )
    ).
    av_sns_arn = lo_sns_create->get_topicarn( ).
    IF av_sns_arn IS INITIAL.
      cl_abap_unit_assert=>fail( msg = 'class_setup: SNS topic creation returned empty ARN' ).
    ENDIF.

    " ── Shared IoT thing ────────────────────────────────────────────────────
    av_thing_name = |sap-abap-iot-{ av_uuid }|.
    DATA(lo_thing) = ao_iot->creatething( iv_thingname = av_thing_name ).
    IF lo_thing IS NOT BOUND OR lo_thing->get_thingarn( ) IS INITIAL.
      cl_abap_unit_assert=>fail( msg = 'class_setup: CreateThing returned empty ARN' ).
    ENDIF.
    av_thing_arn = lo_thing->get_thingarn( ).

    " Tag the thing via IoT TagResource
    ao_iot->tagresource(
      iv_resourcearn = av_thing_arn
      it_tags = VALUE /aws1/cl_iottag=>tt_taglist(
        ( NEW /aws1/cl_iottag( iv_key = 'convert_test' iv_value = 'true' ) )
      )
    ).

    wait_for_thing( av_thing_name ).

    " ── Shared certificate (active) ─────────────────────────────────────────
    DATA(lo_cert) = ao_iot->createkeysandcertificate( abap_true ).
    IF lo_cert IS NOT BOUND OR lo_cert->get_certificateid( ) IS INITIAL.
      cl_abap_unit_assert=>fail( msg = 'class_setup: CreateKeysAndCertificate failed' ).
    ENDIF.
    av_cert_id  = lo_cert->get_certificateid( ).
    av_cert_arn = lo_cert->get_certificatearn( ).

    " ── Shared topic rule pointing to the real SNS topic ────────────────────
    "   Rule names may only contain letters, numbers, and underscores.
    av_rule_name = |sapabapiot{ av_uuid }|.
    ao_iot->createtopicrule(
      iv_rulename = av_rule_name
      io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
        iv_sql     = |SELECT * FROM 'sap/abap/iot/{ av_uuid }'|
        it_actions = VALUE /aws1/cl_iotaction=>tt_actionlist(
          (
            NEW /aws1/cl_iotaction(
              io_sns = NEW /aws1/cl_iotsnsaction(
                iv_targetarn = av_sns_arn
                iv_rolearn   = av_role_arn
              )
            )
          )
        )
      )
    ).

    " Tag the topic rule via IoT TagResource — rule ARN format:
    "   arn:aws:iot:<region>:<account>:rule/<ruleName>
    DATA(lv_rule_arn) =
      |arn:aws:iot:{ lv_region }:{ lv_account }:rule/{ av_rule_name }|.
    ao_iot->tagresource(
      iv_resourcearn = lv_rule_arn
      it_tags = VALUE /aws1/cl_iottag=>tt_taglist(
        ( NEW /aws1/cl_iottag( iv_key = 'convert_test' iv_value = 'true' ) )
      )
    ).
  ENDMETHOD.


" ─────────────────────────────────────────────────────────────────────────────
" class_teardown — best-effort, each step is isolated
" ─────────────────────────────────────────────────────────────────────────────
  METHOD class_teardown.
    " Detach certificate from shared thing (may already be detached)
    IF av_thing_name IS NOT INITIAL AND av_cert_arn IS NOT INITIAL.
      TRY.
          ao_iot->detachthingprincipal(
            iv_thingname = av_thing_name
            iv_principal = av_cert_arn
          ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " Deactivate + delete shared certificate
    IF av_cert_id IS NOT INITIAL.
      TRY.
          ao_iot->updatecertificate(
            iv_certificateid = av_cert_id
            iv_newstatus     = 'INACTIVE'
          ).
          ao_iot->deletecertificate( iv_certificateid = av_cert_id ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " Delete shared topic rule
    IF av_rule_name IS NOT INITIAL.
      TRY.
          ao_iot->deletetopicrule( iv_rulename = av_rule_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " Delete shared IoT thing
    IF av_thing_name IS NOT INITIAL.
      TRY.
          ao_iot->deletething( iv_thingname = av_thing_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " Delete shared SNS topic
    IF av_sns_arn IS NOT INITIAL.
      TRY.
          ao_sns->deletetopic( iv_topicarn = av_sns_arn ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " Delete inline policy then delete IAM role
    IF av_iam_role IS NOT INITIAL.
      TRY.
          ao_iam->deleterolepolicy(
            iv_rolename   = av_iam_role
            iv_policyname = 'AllowSNSPublish'
          ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
      TRY.
          ao_iam->deleterole( iv_rolename = av_iam_role ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
  ENDMETHOD.


" ─────────────────────────────────────────────────────────────────────────────
" Helpers
" ─────────────────────────────────────────────────────────────────────────────
  METHOD wait_for_thing.
    DATA lv_attempts TYPE i VALUE 0.
    WHILE lv_attempts < 20.
      TRY.
          DATA(lo_desc) = ao_iot->describething( iv_thingname = iv_thing_name ).
          IF lo_desc IS BOUND AND lo_desc->get_thingname( ) IS NOT INITIAL.
            RETURN.
          ENDIF.
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
      WAIT UP TO 3 SECONDS.
      lv_attempts = lv_attempts + 1.
    ENDWHILE.
    cl_abap_unit_assert=>fail( msg = |Thing { iv_thing_name } did not become available| ).
  ENDMETHOD.


  METHOD wait_for_index_active.
    " Ensure indexing is enabled
    TRY.
        ao_iot->updateindexingconfiguration(
          io_thingindexingconf = NEW /aws1/cl_iotthingindexingconf(
            iv_thingindexingmode = 'REGISTRY'
          )
        ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    DATA lv_attempts TYPE i VALUE 0.
    WHILE lv_attempts < 30.
      TRY.
          DATA(lo_idx) = ao_iot->describeindex( iv_indexname = 'AWS_Things' ).
          IF lo_idx->get_indexstatus( ) = 'ACTIVE'.
            RETURN.
          ENDIF.
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
      WAIT UP TO 5 SECONDS.
      lv_attempts = lv_attempts + 1.
    ENDWHILE.
    cl_abap_unit_assert=>fail( msg = 'AWS_Things index did not become ACTIVE in time' ).
  ENDMETHOD.


" ─────────────────────────────────────────────────────────────────────────────
" Test methods — one per action-class method
" ─────────────────────────────────────────────────────────────────────────────

  METHOD create_thing.
    " Uses a dedicated name to avoid collision with the shared thing.
    DATA lv_name TYPE /aws1/iotthingname.
    lv_name = |sap-abap-iot-cr-{ av_uuid }|.

    DATA(lo_result) = ao_actions->create_thing( lv_name ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_thingarn( )
      msg = 'create_thing: ARN must not be initial'
    ).
    cl_abap_unit_assert=>assert_equals(
      exp = lv_name
      act = lo_result->get_thingname( )
      msg = 'create_thing: returned name must match'
    ).

    " Tag and clean up
    TRY.
        ao_iot->tagresource(
          iv_resourcearn = lo_result->get_thingarn( )
          it_tags = VALUE /aws1/cl_iottag=>tt_taglist(
            ( NEW /aws1/cl_iottag( iv_key = 'convert_test' iv_value = 'true' ) )
          )
        ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iot->deletething( iv_thingname = lv_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  METHOD list_things.
    DATA(lo_result) = ao_actions->list_things( ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_things: result must be bound'
    ).

    " The shared thing from class_setup must appear.
    DATA lv_found TYPE abap_bool.
    LOOP AT lo_result->get_things( ) INTO DATA(lo_thing).
      IF lo_thing->get_thingname( ) = av_thing_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_things: shared thing { av_thing_name } must appear in result|
    ).
  ENDMETHOD.


  METHOD create_keys_and_certificate.
    DATA(lo_result) = ao_actions->create_keys_and_certificate( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificateid( )
      msg = 'create_keys_and_certificate: certificate ID must not be initial'
    ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificatearn( )
      msg = 'create_keys_and_certificate: certificate ARN must not be initial'
    ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificatepem( )
      msg = 'create_keys_and_certificate: certificate PEM must not be initial'
    ).

    " Clean up the certificate created by this test.
    DATA(lv_id) = lo_result->get_certificateid( ).
    TRY.
        ao_iot->updatecertificate(
          iv_certificateid = lv_id
          iv_newstatus     = 'INACTIVE'
        ).
        ao_iot->deletecertificate( iv_certificateid = lv_id ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  METHOD attach_thing_principal.
    " Uses a fresh thing and certificate so this test is self-contained.
    DATA lv_thing TYPE /aws1/iotthingname.
    lv_thing = |sap-abap-iot-att-{ av_uuid }|.

    DATA(lo_thing_r) = ao_iot->creatething( iv_thingname = lv_thing ).
    DATA(lv_thing_arn_local) = lo_thing_r->get_thingarn( ).
    ao_iot->tagresource(
      iv_resourcearn = lv_thing_arn_local
      it_tags = VALUE /aws1/cl_iottag=>tt_taglist(
        ( NEW /aws1/cl_iottag( iv_key = 'convert_test' iv_value = 'true' ) )
      )
    ).
    wait_for_thing( lv_thing ).

    DATA(lo_cert_r)  = ao_iot->createkeysandcertificate( abap_true ).
    DATA(lv_cid)     = lo_cert_r->get_certificateid( ).
    DATA(lv_carn)    = lo_cert_r->get_certificatearn( ).

    " Execute the action under test.
    ao_actions->attach_thing_principal(
      iv_thing_name = lv_thing
      iv_principal  = lv_carn
    ).

    " Verify the principal now appears in ListThingPrincipals.
    DATA(lo_list) = ao_iot->listthingprincipals( iv_thingname = lv_thing ).
    DATA lv_found TYPE abap_bool.
    LOOP AT lo_list->get_principals( ) INTO DATA(lo_p).
      IF lo_p->get_value( ) = lv_carn.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |attach_thing_principal: certificate { lv_carn } must appear in ListThingPrincipals|
    ).

    " Clean up
    TRY.
        ao_iot->detachthingprincipal(
          iv_thingname = lv_thing
          iv_principal = lv_carn
        ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iot->updatecertificate( iv_certificateid = lv_cid iv_newstatus = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = lv_cid ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iot->deletething( iv_thingname = lv_thing ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  METHOD describe_endpoint.
    DATA(lv_address) = ao_actions->describe_endpoint( 'iot:Data-ATS' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_address
      msg = 'describe_endpoint: address must not be initial'
    ).
    " A Data-ATS endpoint always contains 'amazonaws.com'
    cl_abap_unit_assert=>assert_differs(
      exp = -1
      act = find( val = lv_address sub = 'amazonaws.com' )
      msg = 'describe_endpoint: address must contain ''amazonaws.com'''
    ).
  ENDMETHOD.


  METHOD list_certificates.
    DATA(lo_result) = ao_actions->list_certificates( ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_certificates: result must be bound'
    ).

    " The shared certificate from class_setup must appear.
    DATA lv_found TYPE abap_bool.
    LOOP AT lo_result->get_certificates( ) INTO DATA(lo_cert).
      IF lo_cert->get_certificateid( ) = av_cert_id.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_certificates: shared certificate { av_cert_id } must appear|
    ).
  ENDMETHOD.


  METHOD detach_thing_principal.
    " Use a dedicated thing + certificate so this test is isolated.
    DATA lv_thing TYPE /aws1/iotthingname.
    lv_thing = |sap-abap-iot-det-{ av_uuid }|.

    DATA(lo_thing_r) = ao_iot->creatething( iv_thingname = lv_thing ).
    ao_iot->tagresource(
      iv_resourcearn = lo_thing_r->get_thingarn( )
      it_tags = VALUE /aws1/cl_iottag=>tt_taglist(
        ( NEW /aws1/cl_iottag( iv_key = 'convert_test' iv_value = 'true' ) )
      )
    ).
    wait_for_thing( lv_thing ).

    DATA(lo_cert_r) = ao_iot->createkeysandcertificate( abap_true ).
    DATA(lv_cid)    = lo_cert_r->get_certificateid( ).
    DATA(lv_carn)   = lo_cert_r->get_certificatearn( ).

    " Attach first so we have something to detach.
    ao_iot->attachthingprincipal(
      iv_thingname = lv_thing
      iv_principal = lv_carn
    ).

    " Execute the action under test.
    ao_actions->detach_thing_principal(
      iv_thing_name = lv_thing
      iv_principal  = lv_carn
    ).

    " Verify the principal is gone from ListThingPrincipals.
    DATA(lo_list) = ao_iot->listthingprincipals( iv_thingname = lv_thing ).
    DATA lv_found TYPE abap_bool.
    LOOP AT lo_list->get_principals( ) INTO DATA(lo_p).
      IF lo_p->get_value( ) = lv_carn.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_false(
      act = lv_found
      msg = |detach_thing_principal: certificate { lv_carn } must NOT appear after detach|
    ).

    " Clean up
    TRY.
        ao_iot->updatecertificate( iv_certificateid = lv_cid iv_newstatus = 'INACTIVE' ).
        ao_iot->deletecertificate( iv_certificateid = lv_cid ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iot->deletething( iv_thingname = lv_thing ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  METHOD delete_certificate.
    " Create a fresh certificate exclusively for deletion.
    DATA(lo_cert) = ao_iot->createkeysandcertificate( abap_true ).
    DATA(lv_del_id) = lo_cert->get_certificateid( ).

    ao_actions->delete_certificate( lv_del_id ).

    " Verify: DescribeCertificate must raise ResourceNotFoundException.
    TRY.
        ao_iot->describecertificate( iv_certificateid = lv_del_id ).
        cl_abap_unit_assert=>fail(
          msg = 'delete_certificate: DescribeCertificate must fail after deletion'
        ).
      CATCH /aws1/cx_iotresourcenotfoundex.
        " Expected — certificate was successfully deleted.
    ENDTRY.
  ENDMETHOD.


  METHOD create_topic_rule.
    " Use a dedicated rule name, SNS topic, and IAM role for this test.
    DATA lv_rule     TYPE /aws1/iotrulename.
    DATA lv_topic    TYPE /aws1/snstopicname.
    DATA lv_sns_arn2 TYPE /aws1/iotawsarn.

    lv_rule  = |sapabapiotcr{ av_uuid }|.
    lv_topic = |sap-abap-iot-cr-{ av_uuid }|.

    " Create a dedicated SNS topic and tag it.
    DATA(lo_sns_r) = ao_sns->createtopic(
      iv_name = lv_topic
      it_tags = VALUE /aws1/cl_snstag=>tt_taglist(
        ( NEW /aws1/cl_snstag( iv_key = 'convert_test' iv_value = 'true' ) )
      )
    ).
    lv_sns_arn2 = lo_sns_r->get_topicarn( ).

    " Execute the action under test — use the shared IAM role (already has sns:Publish).
    ao_actions->create_topic_rule(
      iv_rule_name      = lv_rule
      iv_topic          = |sap/abap/iot/cr/{ av_uuid }|
      iv_sns_action_arn = lv_sns_arn2
      iv_role_arn       = av_role_arn
    ).

    " Tag the rule
    DATA(lv_region)  = ao_session->get_region( ).
    DATA(lv_account) = ao_session->get_account_id( ).
    TRY.
        ao_iot->tagresource(
          iv_resourcearn = |arn:aws:iot:{ lv_region }:{ lv_account }:rule/{ lv_rule }|
          it_tags = VALUE /aws1/cl_iottag=>tt_taglist(
            ( NEW /aws1/cl_iottag( iv_key = 'convert_test' iv_value = 'true' ) )
          )
        ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Verify the rule exists via GetTopicRule.
    DATA(lo_rule_detail) = ao_iot->gettopicrule( iv_rulename = lv_rule ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_rule_detail->get_rulearn( )
      msg = 'create_topic_rule: rule ARN must not be initial after creation'
    ).
    cl_abap_unit_assert=>assert_equals(
      exp = lv_rule
      act = lo_rule_detail->get_rule( )->get_rulename( )
      msg = 'create_topic_rule: rule name must match'
    ).

    " Clean up
    TRY.
        ao_iot->deletetopicrule( iv_rulename = lv_rule ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_sns->deletetopic( iv_topicarn = lv_sns_arn2 ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  METHOD list_topic_rules.
    DATA(lo_result) = ao_actions->list_topic_rules( ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_topic_rules: result must be bound'
    ).

    " The shared rule from class_setup must appear.
    DATA lv_found TYPE abap_bool.
    LOOP AT lo_result->get_rules( ) INTO DATA(lo_rule).
      IF lo_rule->get_rulename( ) = av_rule_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_topic_rules: shared rule { av_rule_name } must appear in result|
    ).
  ENDMETHOD.


  METHOD update_indexing_configuration.
    ao_actions->update_indexing_configuration( ).

    " Verify by reading back the configuration.
    DATA(lo_config) = ao_iot->getindexingconfiguration( ).
    DATA(lo_thing_conf) = lo_config->get_thingindexingconf( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_thing_conf->get_thingindexingmode( )
      msg = 'update_indexing_configuration: mode must not be initial'
    ).
    cl_abap_unit_assert=>assert_equals(
      exp = 'REGISTRY'
      act = lo_thing_conf->get_thingindexingmode( )
      msg = 'update_indexing_configuration: mode must be REGISTRY'
    ).
  ENDMETHOD.


  METHOD search_index.
    " Ensure the index is ACTIVE before searching.
    wait_for_index_active( ).

    DATA(lo_result) = ao_actions->search_index(
      " iv_query = 'thingName:sap-abap-iot-*'
      iv_query = |thingName:{ av_thing_name }|
    ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'search_index: result must be bound'
    ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lines( lo_result->get_things( ) )
      msg = |search_index: must find at least the shared thing { av_thing_name }|
    ).

    " Verify the shared thing appears in the results.
    DATA lv_found TYPE abap_bool.
    LOOP AT lo_result->get_things( ) INTO DATA(lo_thing).
      IF lo_thing->get_thingname( ) = av_thing_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |search_index: shared thing { av_thing_name } must appear in results|
    ).
  ENDMETHOD.


  METHOD delete_topic_rule.
    " Create a dedicated rule for this deletion test.
    DATA lv_del_rule TYPE /aws1/iotrulename.
    lv_del_rule = |sapabapiotdl{ av_uuid }|.

    ao_iot->createtopicrule(
      iv_rulename = lv_del_rule
      io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
        iv_sql     = |SELECT * FROM 'sap/abap/iot/del/{ av_uuid }'|
        it_actions = VALUE /aws1/cl_iotaction=>tt_actionlist(
          (
            NEW /aws1/cl_iotaction(
              io_sns = NEW /aws1/cl_iotsnsaction(
                iv_targetarn = av_sns_arn
                iv_rolearn   = av_role_arn
              )
            )
          )
        )
      )
    ).

    " Tag the dedicated rule
    DATA(lv_region)  = ao_session->get_region( ).
    DATA(lv_account) = ao_session->get_account_id( ).
    TRY.
        ao_iot->tagresource(
          iv_resourcearn = |arn:aws:iot:{ lv_region }:{ lv_account }:rule/{ lv_del_rule }|
          it_tags = VALUE /aws1/cl_iottag=>tt_taglist(
            ( NEW /aws1/cl_iottag( iv_key = 'convert_test' iv_value = 'true' ) )
          )
        ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Execute the action under test.
    ao_actions->delete_topic_rule( lv_del_rule ).

    " Verify: GetTopicRule must raise a service-level error for the deleted rule.
    TRY.
        ao_iot->gettopicrule( iv_rulename = lv_del_rule ).
        cl_abap_unit_assert=>fail(
          msg = 'delete_topic_rule: GetTopicRule must fail after rule deletion'
        ).
      CATCH /aws1/cx_rt_generic.
        " Expected — rule was successfully deleted.
    ENDTRY.
  ENDMETHOD.


  METHOD delete_thing.
    " Create a dedicated thing for this deletion test.
    DATA lv_del_thing TYPE /aws1/iotthingname.
    lv_del_thing = |sap-abap-iot-dl-{ av_uuid }|.

    DATA(lo_del_thing_r) = ao_iot->creatething( iv_thingname = lv_del_thing ).
    ao_iot->tagresource(
      iv_resourcearn = lo_del_thing_r->get_thingarn( )
      it_tags = VALUE /aws1/cl_iottag=>tt_taglist(
        ( NEW /aws1/cl_iottag( iv_key = 'convert_test' iv_value = 'true' ) )
      )
    ).
    wait_for_thing( lv_del_thing ).

    " Execute the action under test.
    ao_actions->delete_thing( lv_del_thing ).

    " Verify: DescribeThing must raise ResourceNotFoundException.
    TRY.
        ao_iot->describething( iv_thingname = lv_del_thing ).
        cl_abap_unit_assert=>fail(
          msg = 'delete_thing: DescribeThing must fail after thing deletion'
        ).
      CATCH /aws1/cx_iotresourcenotfoundex.
        " Expected — thing was successfully deleted.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
