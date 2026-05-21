" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_iot_actions DEFINITION DEFERRED.
CLASS /awsex/cl_iot_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_iot_actions.

CLASS ltc_awsex_cl_iot_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " Service clients
    CLASS-DATA ao_iot         TYPE REF TO /aws1/if_iot.
    CLASS-DATA ao_sns         TYPE REF TO /aws1/if_sns.
    CLASS-DATA ao_iam         TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_session     TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_iot_actions TYPE REF TO /awsex/cl_iot_actions.

    " Shared, non-mutating resources (kept alive for the whole test run)
    CLASS-DATA av_thing_name   TYPE /aws1/iotthingname.   " for list_things, search_index
    CLASS-DATA av_thing_arn    TYPE /aws1/iotthingarn.
    CLASS-DATA av_cert_id      TYPE /aws1/iotcertificateid.  " for list_certificates
    CLASS-DATA av_cert_arn     TYPE /aws1/iotcertificatearn.

    " Dedicated resources for mutating tests
    CLASS-DATA av_new_thing    TYPE /aws1/iotthingname.   " created by create_thing test itself
    CLASS-DATA av_attach_thing TYPE /aws1/iotthingname.   " for attach / detach principal
    CLASS-DATA av_del_thing    TYPE /aws1/iotthingname.   " consumed by delete_thing test
    CLASS-DATA av_del_cert_id  TYPE /aws1/iotcertificateid.  " consumed by delete_certificate test

    " IAM role for topic-rule actions
    CLASS-DATA av_role_name    TYPE /aws1/iamrolenametype.
    CLASS-DATA av_role_arn     TYPE /aws1/iamarntype.
    CLASS-DATA av_policy_name  TYPE /aws1/iampolicynametype.

    " SNS topic for topic-rule actions
    CLASS-DATA av_topic_arn    TYPE /aws1/snstopicarn.

    " Topic rules
    CLASS-DATA av_rule_name    TYPE /aws1/iotrulename.    " created by create_topic_rule test
    CLASS-DATA av_del_rule     TYPE /aws1/iotrulename.    " consumed by delete_topic_rule test
    CLASS-DATA av_probe_rule   TYPE /aws1/iotrulename.    " IAM-propagation probe; deleted in setup on success

    METHODS:
      create_thing                  FOR TESTING RAISING /aws1/cx_rt_generic,
      list_things                   FOR TESTING RAISING /aws1/cx_rt_generic,
      create_keys_and_certificate   FOR TESTING RAISING /aws1/cx_rt_generic,
      attach_thing_principal        FOR TESTING RAISING /aws1/cx_rt_generic,
      describe_endpoint             FOR TESTING RAISING /aws1/cx_rt_generic,
      list_certificates             FOR TESTING RAISING /aws1/cx_rt_generic,
      detach_thing_principal        FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_certificate            FOR TESTING RAISING /aws1/cx_rt_generic,
      create_topic_rule             FOR TESTING RAISING /aws1/cx_rt_generic,
      list_topic_rules              FOR TESTING RAISING /aws1/cx_rt_generic,
      update_indexing_configuration FOR TESTING RAISING /aws1/cx_rt_generic,
      search_index                  FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_thing                  FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_topic_rule             FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " Helper: tag an IoT resource (best-effort; ignores errors)
    CLASS-METHODS tag_iot_resource
      IMPORTING iv_arn TYPE /aws1/iotresourcearn.

    " Helper: deactivate + delete a certificate (best-effort)
    CLASS-METHODS cleanup_cert
      IMPORTING iv_cert_id TYPE /aws1/iotcertificateid.

    " Helper: rule-safe name from random string (alphanumeric + underscore only)
    CLASS-METHODS safe_rule_name
      IMPORTING iv_prefix       TYPE string
                iv_rand         TYPE string
      RETURNING VALUE(rv_name)  TYPE /aws1/iotrulename.

ENDCLASS.


CLASS ltc_awsex_cl_iot_actions IMPLEMENTATION.

  " ──────────────────────────────────────────────────────────────────────────
  " Helpers
  " ──────────────────────────────────────────────────────────────────────────

  METHOD tag_iot_resource.
    TRY.
        ao_iot->tagresource(
          iv_resourcearn = iv_arn
          it_tags        = VALUE /aws1/cl_iottag=>tt_taglist(
            ( NEW /aws1/cl_iottag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).
      CATCH /aws1/cx_rt_generic.
        " Best-effort; tagging failures must not abort setup.
    ENDTRY.
  ENDMETHOD.

  METHOD cleanup_cert.
    IF iv_cert_id IS INITIAL. RETURN. ENDIF.
    TRY.
        ao_iot->updatecertificate(
          iv_certificateid = iv_cert_id
          iv_newstatus     = 'INACTIVE' ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_iot->deletecertificate( iv_certificateid = iv_cert_id ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.

  METHOD safe_rule_name.
    " IoT rule names: letters, numbers, underscores only, max 128 chars.
    " GENERAL_GET_RANDOM_STRING returns 10 characters; use the full string.
    DATA(lv_raw) = iv_rand.
    TRANSLATE lv_raw USING '- _'.   " replace any hyphens with underscores
    rv_name = |{ iv_prefix }{ lv_raw }|.
  ENDMETHOD.


  " ──────────────────────────────────────────────────────────────────────────
  " class_setup  – create ALL shared resources; tag everything; fail hard if
  "                any required resource cannot be created.
  " ──────────────────────────────────────────────────────────────────────────

  METHOD class_setup.
    ao_session    = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    ao_iot        = /aws1/cl_iot_factory=>create( ao_session ).
    ao_sns        = /aws1/cl_sns_factory=>create( ao_session ).
    ao_iam        = /aws1/cl_iam_factory=>create( ao_session ).
    ao_iot_actions = NEW /awsex/cl_iot_actions( ).

    DATA(lv_rand)    = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_account) = ao_session->get_account_id( ).
    DATA(lv_region)  = ao_session->get_region( ).

    " ── 1. IAM role that IoT topic rules will assume ──────────────────────
    av_role_name   = |sap-abap-iot-role-{ lv_rand }|.
    av_policy_name = |sap-abap-iot-pol-{ lv_rand }|.

    DATA(lv_trust_doc) =
      '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",' &&
      '"Principal":{"Service":"iot.amazonaws.com"},' &&
      '"Action":"sts:AssumeRole"}]}'.

    DATA(lo_role_rsp) = ao_iam->createrole(
      iv_rolename                 = av_role_name
      iv_assumerolepolicydocument = lv_trust_doc
      it_tags = VALUE /aws1/cl_iamtag=>tt_taglisttype(
        ( NEW /aws1/cl_iamtag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).

    av_role_arn = lo_role_rsp->get_role( )->get_arn( ).

    IF av_role_arn IS INITIAL.
      cl_abap_unit_assert=>fail( 'class_setup: IAM role ARN is empty after creation' ).
    ENDIF.

    " Attach inline policy: allow SNS publish from IoT
    DATA(lv_policy_doc) =
      '{"Version":"2012-10-17","Statement":[' &&
      '{"Effect":"Allow","Action":["sns:Publish"],"Resource":"*"},' &&
      '{"Effect":"Allow","Action":["iot:Publish"],"Resource":"*"}' &&
      ']}' .

    ao_iam->putrolepolicy(
      iv_rolename      = av_role_name
      iv_policyname    = av_policy_name
      iv_policydocument = lv_policy_doc ).

    " ── 1b. Wait for IAM role to propagate before using it in IoT rules ───
    " IAM is eventually consistent. AWS IoT calls sts:AssumeRole when a topic
    " rule is created, so the role must be fully visible to STS before we
    " proceed. We poll by attempting a throwaway CreateTopicRule and retrying
    " on InvalidRequestException ("unable to assume role"). Max wait ~90 s.
    av_probe_rule = safe_rule_name(
      iv_prefix = 'SapAbapProbe'
      iv_rand   = lv_rand ).
    DATA lv_role_ready  TYPE abap_bool VALUE abap_false.
    DATA lv_iam_attempt TYPE i VALUE 0.

    WHILE lv_iam_attempt < 18 AND lv_role_ready = abap_false.
      TRY.
          ao_iot->createtopicrule(
            iv_rulename         = av_probe_rule
            io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
              iv_sql     = |SELECT * FROM 'sap/abap/probe'|
              it_actions = VALUE /aws1/cl_iotaction=>tt_actionlist(
                ( NEW /aws1/cl_iotaction(
                    io_sns = NEW /aws1/cl_iotsnsaction(
                      " Use a placeholder SNS ARN for the probe — the rule
                      " only needs to be accepted by IoT, not actually invoked.
                      iv_targetarn = |arn:aws:sns:{ lv_region }:{ lv_account }:probe|
                      iv_rolearn   = av_role_arn ) ) ) ) ) ).
          " Rule was accepted — role is propagated. Clean up the probe rule.
          lv_role_ready = abap_true.
          TRY.
              ao_iot->deletetopicrule( iv_rulename = av_probe_rule ).
              CLEAR av_probe_rule.
            CATCH /aws1/cx_rt_generic.
          ENDTRY.
        CATCH /aws1/cx_iotinvalidrequestex.
          " "Unable to assume role" — role not yet propagated. Wait and retry.
          lv_iam_attempt = lv_iam_attempt + 1.
          WAIT UP TO 5 SECONDS.
        CATCH /aws1/cx_iotresrcalrdyexistsex.
          " Probe rule already exists from a previous aborted run — treat as ready.
          lv_role_ready = abap_true.
          TRY.
              ao_iot->deletetopicrule( iv_rulename = av_probe_rule ).
              CLEAR av_probe_rule.
            CATCH /aws1/cx_rt_generic.
          ENDTRY.
        CATCH /aws1/cx_rt_generic INTO DATA(lo_probe_ex).
          " Any other error on the probe is unexpected — fail setup immediately.
          cl_abap_unit_assert=>fail(
            |class_setup: unexpected error waiting for IAM role to propagate: | &&
            lo_probe_ex->get_text( ) ).
      ENDTRY.
    ENDWHILE.

    IF lv_role_ready = abap_false.
      cl_abap_unit_assert=>fail(
        |class_setup: IAM role { av_role_arn } did not become assumable by IoT | &&
        |after { lv_iam_attempt * 5 } seconds| ).
    ENDIF.

    " ── 2. SNS topic (real ARN needed for topic-rule action) ───────────────
    DATA(lo_sns_rsp) = ao_sns->createtopic(
      iv_name  = |sap-abap-iot-topic-{ lv_rand }|
      it_tags  = VALUE /aws1/cl_snstag=>tt_taglist(
        ( NEW /aws1/cl_snstag( iv_key = 'convert_test' iv_value = 'true' ) ) ) ).

    av_topic_arn = lo_sns_rsp->get_topicarn( ).

    IF av_topic_arn IS INITIAL.
      cl_abap_unit_assert=>fail( 'class_setup: SNS topic ARN is empty after creation' ).
    ENDIF.

    " ── 3. Shared thing (for list_things / search_index) ──────────────────
    av_thing_name = |sap-abap-iot-{ lv_rand }|.

    DATA(lo_thing_rsp) = ao_iot->creatething( iv_thingname = av_thing_name ).
    av_thing_arn = lo_thing_rsp->get_thingarn( ).

    IF av_thing_arn IS INITIAL.
      cl_abap_unit_assert=>fail( |class_setup: could not create shared thing { av_thing_name }| ).
    ENDIF.
    tag_iot_resource( av_thing_arn ).

    " ── 4. Shared certificate (for list_certificates) ─────────────────────
    DATA(lo_cert_rsp) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
    av_cert_id  = lo_cert_rsp->get_certificateid( ).
    av_cert_arn = lo_cert_rsp->get_certificatearn( ).

    IF av_cert_id IS INITIAL.
      cl_abap_unit_assert=>fail( 'class_setup: shared certificate ID is empty' ).
    ENDIF.

    " ── 5. Dedicated thing for attach / detach principal tests ───────────
    av_attach_thing = |sap-abap-iot-att-{ lv_rand }|.

    DATA(lo_att_rsp) = ao_iot->creatething( iv_thingname = av_attach_thing ).
    tag_iot_resource( lo_att_rsp->get_thingarn( ) ).

    IF lo_att_rsp->get_thingarn( ) IS INITIAL.
      cl_abap_unit_assert=>fail( |class_setup: could not create attach-thing { av_attach_thing }| ).
    ENDIF.

    " ── 6. Dedicated thing for delete_thing test ──────────────────────────
    av_del_thing = |sap-abap-iot-del-{ lv_rand }|.

    DATA(lo_del_rsp) = ao_iot->creatething( iv_thingname = av_del_thing ).
    tag_iot_resource( lo_del_rsp->get_thingarn( ) ).

    IF lo_del_rsp->get_thingarn( ) IS INITIAL.
      cl_abap_unit_assert=>fail( |class_setup: could not create del-thing { av_del_thing }| ).
    ENDIF.

    " ── 7. Dedicated certificate for delete_certificate test ──────────────
    DATA(lo_delcert_rsp) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
    av_del_cert_id = lo_delcert_rsp->get_certificateid( ).

    IF av_del_cert_id IS INITIAL.
      cl_abap_unit_assert=>fail( 'class_setup: dedicated delete-certificate ID is empty' ).
    ENDIF.

    " ── 8. Topic rule names (alphanumeric+underscore, ≤ 128 chars) ────────
    " av_rule_name: created during create_topic_rule test, listed by list_topic_rules
    av_rule_name  = safe_rule_name( iv_prefix = 'SapAbapIotRule' iv_rand = lv_rand ).
    " av_del_rule:  created here (pre-built for delete_topic_rule test)
    av_del_rule   = safe_rule_name( iv_prefix = 'SapAbapIotDel' iv_rand = lv_rand ).

    " Pre-create the delete_topic_rule target so the test can focus on deletion
    ao_iot->createtopicrule(
      iv_rulename         = av_del_rule
      io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
        iv_sql     = |SELECT * FROM 'sap/abap/del/topic'|
        it_actions = VALUE /aws1/cl_iotaction=>tt_actionlist(
          ( NEW /aws1/cl_iotaction(
              io_sns = NEW /aws1/cl_iotsnsaction(
                iv_targetarn = av_topic_arn
                iv_rolearn   = av_role_arn ) ) ) ) ) ).
    " Tag topic rules via TagResource (rules support tagging via iv_tags header string
    " or TagResource API; use TagResource for the pre-created rule)
    TRY.
        DATA(lo_del_rule_desc) = ao_iot->gettopicrule( iv_rulename = av_del_rule ).
        tag_iot_resource( lo_del_rule_desc->get_rulearn( ) ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

  ENDMETHOD.


  " ──────────────────────────────────────────────────────────────────────────
  " class_teardown  – clean up all resources; each step in its own TRY/CATCH
  " ──────────────────────────────────────────────────────────────────────────

  METHOD class_teardown.
    " -- Topic rules --
    IF av_rule_name IS NOT INITIAL.
      TRY.
          ao_iot->deletetopicrule( iv_rulename = av_rule_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
    IF av_del_rule IS NOT INITIAL.
      TRY.
          ao_iot->deletetopicrule( iv_rulename = av_del_rule ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
    " Probe rule: non-empty only if setup was aborted before it could be deleted
    IF av_probe_rule IS NOT INITIAL.
      TRY.
          ao_iot->deletetopicrule( iv_rulename = av_probe_rule ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " -- Detach shared cert from attach-thing (in case tests left it attached) --
    IF av_cert_arn IS NOT INITIAL AND av_attach_thing IS NOT INITIAL.
      TRY.
          ao_iot->detachthingprincipal(
            iv_thingname = av_attach_thing
            iv_principal = av_cert_arn ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " -- Delete certificates --
    cleanup_cert( av_cert_id ).
    cleanup_cert( av_del_cert_id ).   " no-op if already deleted by test

    " -- Delete things --
    IF av_thing_name IS NOT INITIAL.
      TRY.
          ao_iot->deletething( iv_thingname = av_thing_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
    IF av_attach_thing IS NOT INITIAL.
      TRY.
          ao_iot->deletething( iv_thingname = av_attach_thing ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
    IF av_del_thing IS NOT INITIAL.
      TRY.
          ao_iot->deletething( iv_thingname = av_del_thing ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
    IF av_new_thing IS NOT INITIAL.
      TRY.
          ao_iot->deletething( iv_thingname = av_new_thing ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " -- SNS topic --
    IF av_topic_arn IS NOT INITIAL.
      TRY.
          ao_sns->deletetopic( av_topic_arn ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " -- IAM: delete inline policy then role --
    IF av_role_name IS NOT INITIAL AND av_policy_name IS NOT INITIAL.
      TRY.
          ao_iam->deleterolepolicy(
            iv_rolename  = av_role_name
            iv_policyname = av_policy_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
    IF av_role_name IS NOT INITIAL.
      TRY.
          ao_iam->deleterole( iv_rolename = av_role_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
  ENDMETHOD.


  " ──────────────────────────────────────────────────────────────────────────
  " Test methods
  " ──────────────────────────────────────────────────────────────────────────

  METHOD create_thing.
    " Create a brand-new thing using the action method and verify it exists.
    DATA(lv_rand)     = /awsex/cl_utils=>get_random_string( ).
    av_new_thing      = |sap-abap-iot-new-{ lv_rand }|.

    DATA(lo_result) = ao_iot_actions->create_thing( iv_thing_name = av_new_thing ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = |create_thing: result object is not bound| ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_thingname( )
      exp = av_new_thing
      msg = |create_thing: returned name '{ lo_result->get_thingname( ) }' != '{ av_new_thing }'| ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_thingarn( )
      msg = |create_thing: ARN is empty| ).

    " Confirm existence via DescribeThing
    DATA(lo_desc) = ao_iot->describething( iv_thingname = av_new_thing ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_desc->get_thingname( )
      exp = av_new_thing
      msg = |create_thing: DescribeThing returned wrong name| ).

    " Tag (best-effort)
    tag_iot_resource( lo_result->get_thingarn( ) ).
    " av_new_thing is tracked as a class attribute; class_teardown deletes it.
  ENDMETHOD.


  METHOD list_things.
    " The shared thing (av_thing_name) was created in class_setup.
    DATA(lo_result) = ao_iot_actions->list_things( ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = |list_things: result is not bound| ).

    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_result->get_things( ) INTO DATA(lo_thing).
      IF lo_thing->get_thingname( ) = av_thing_name.
        lv_found = abap_true.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_things: shared thing '{ av_thing_name }' not found in result| ).
  ENDMETHOD.


  METHOD create_keys_and_certificate.
    DATA(lo_result) = ao_iot_actions->create_keys_and_certificate( ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = |create_keys_and_certificate: result is not bound| ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificateid( )
      msg = |create_keys_and_certificate: certificate ID is empty| ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificatearn( )
      msg = |create_keys_and_certificate: certificate ARN is empty| ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificatepem( )
      msg = |create_keys_and_certificate: certificate PEM is empty| ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result->get_keypair( )
      msg = |create_keys_and_certificate: key pair is not bound| ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_keypair( )->get_publickey( )
      msg = |create_keys_and_certificate: public key is empty| ).

    " Clean up the certificate this test created
    cleanup_cert( lo_result->get_certificateid( ) ).
  ENDMETHOD.


  METHOD attach_thing_principal.
    " Use the dedicated attach-thing and the shared cert.
    ao_iot_actions->attach_thing_principal(
      iv_thing_name = av_attach_thing
      iv_principal  = av_cert_arn ).

    " Verify: cert must appear in the thing's principal list.
    DATA(lo_principals) = ao_iot->listthingprincipals( iv_thingname = av_attach_thing ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_principals
      msg = |attach_thing_principal: ListThingPrincipals result is not bound| ).

    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_principals->get_principals( ) INTO DATA(lo_p).
      IF lo_p->get_value( ) = av_cert_arn.
        lv_found = abap_true.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |attach_thing_principal: cert '{ av_cert_arn }' not found after attach| ).
  ENDMETHOD.


  METHOD describe_endpoint.
    DATA(lv_addr) = ao_iot_actions->describe_endpoint( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_addr
      msg = |describe_endpoint: returned address is empty| ).

    " A valid ATS data endpoint contains 'iot.' and 'amazonaws.com'
    cl_abap_unit_assert=>assert_differs(
      act = find( val = lv_addr sub = 'amazonaws.com' )
      exp = -1
      msg = |describe_endpoint: '{ lv_addr }' does not contain 'amazonaws.com'| ).

    cl_abap_unit_assert=>assert_differs(
      act = find( val = lv_addr sub = 'iot.' )
      exp = -1
      msg = |describe_endpoint: '{ lv_addr }' does not look like an IoT endpoint| ).
  ENDMETHOD.


  METHOD list_certificates.
    " The shared cert (av_cert_id) was created in class_setup.
    DATA(lo_result) = ao_iot_actions->list_certificates( ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = |list_certificates: result is not bound| ).

    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_result->get_certificates( ) INTO DATA(lo_cert).
      IF lo_cert->get_certificateid( ) = av_cert_id.
        lv_found = abap_true.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_certificates: shared cert '{ av_cert_id }' not found| ).
  ENDMETHOD.


  METHOD detach_thing_principal.
    " Ensure the cert is attached first (idempotent: may already be from attach test).
    TRY.
        ao_iot->attachthingprincipal(
          iv_thingname = av_attach_thing
          iv_principal = av_cert_arn ).
      CATCH /aws1/cx_rt_generic.
        " Already attached — fine.
    ENDTRY.

    ao_iot_actions->detach_thing_principal(
      iv_thing_name = av_attach_thing
      iv_principal  = av_cert_arn ).

    " Verify: cert must NOT appear in the thing's principal list any more.
    DATA(lo_principals) = ao_iot->listthingprincipals( iv_thingname = av_attach_thing ).

    DATA lv_still_attached TYPE abap_bool VALUE abap_false.
    LOOP AT lo_principals->get_principals( ) INTO DATA(lo_p).
      IF lo_p->get_value( ) = av_cert_arn.
        lv_still_attached = abap_true.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_false(
      act = lv_still_attached
      msg = |detach_thing_principal: cert '{ av_cert_arn }' still attached after detach| ).
  ENDMETHOD.


  METHOD delete_certificate.
    " Use the dedicated delete-certificate created in class_setup.
    ao_iot_actions->delete_certificate( iv_certificate_id = av_del_cert_id ).

    " Verify: DescribeCertificate must raise ResourceNotFound.
    DATA lv_gone TYPE abap_bool VALUE abap_false.
    TRY.
        ao_iot->describecertificate( iv_certificateid = av_del_cert_id ).
      CATCH /aws1/cx_iotresourcenotfoundex.
        lv_gone = abap_true.
      CATCH /aws1/cx_rt_generic.
        lv_gone = abap_true.
    ENDTRY.

    cl_abap_unit_assert=>assert_true(
      act = lv_gone
      msg = |delete_certificate: cert '{ av_del_cert_id }' still exists after deletion| ).

    CLEAR av_del_cert_id.   " Prevent double-delete in class_teardown.
  ENDMETHOD.


  METHOD create_topic_rule.
    " Create the rule using the real SNS topic ARN and the IAM role created in setup.
    ao_iot_actions->create_topic_rule(
      iv_rule_name      = av_rule_name
      iv_topic          = 'sap/abap/test/topic'
      iv_sns_action_arn = av_topic_arn
      iv_role_arn       = av_role_arn ).

    " Verify: GetTopicRule must return the rule.
    DATA(lo_rule) = ao_iot->gettopicrule( iv_rulename = av_rule_name ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_rule
      msg = |create_topic_rule: GetTopicRule result not bound| ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_rule->get_rulearn( )
      msg = |create_topic_rule: rule ARN is empty after creation| ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_rule->get_rule( )->get_rulename( )
      exp = av_rule_name
      msg = |create_topic_rule: rule name mismatch| ).

    " Tag the newly created rule
    tag_iot_resource( lo_rule->get_rulearn( ) ).
  ENDMETHOD.


  METHOD list_topic_rules.
    " The rule av_rule_name must have been created by create_topic_rule test.
    " If not yet present, create it now so this test can succeed independently.
    TRY.
        ao_iot->gettopicrule( iv_rulename = av_rule_name ).
      CATCH /aws1/cx_rt_generic.
        ao_iot->createtopicrule(
          iv_rulename         = av_rule_name
          io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
            iv_sql     = |SELECT * FROM 'sap/abap/test/topic'|
            it_actions = VALUE /aws1/cl_iotaction=>tt_actionlist(
              ( NEW /aws1/cl_iotaction(
                  io_sns = NEW /aws1/cl_iotsnsaction(
                    iv_targetarn = av_topic_arn
                    iv_rolearn   = av_role_arn ) ) ) ) ) ).
    ENDTRY.

    DATA(lo_result) = ao_iot_actions->list_topic_rules( ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = |list_topic_rules: result is not bound| ).

    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_result->get_rules( ) INTO DATA(lo_rule).
      IF lo_rule->get_rulename( ) = av_rule_name.
        lv_found = abap_true.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_topic_rules: rule '{ av_rule_name }' not found in result| ).
  ENDMETHOD.


  METHOD update_indexing_configuration.
    " Enable REGISTRY indexing mode; no exception = success.
    ao_iot_actions->update_indexing_configuration( ).

    " Read back and verify the mode is no longer OFF.
    DATA(lo_conf)    = ao_iot->getindexingconfiguration( ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_conf
      msg = |update_indexing_configuration: GetIndexingConfiguration returned nothing| ).

    DATA(lo_thing_conf) = lo_conf->get_thingindexingconf( ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_thing_conf
      msg = |update_indexing_configuration: thing indexing configuration is not bound| ).

    cl_abap_unit_assert=>assert_differs(
      act = lo_thing_conf->get_thingindexingmode( )
      exp = 'OFF'
      msg = |update_indexing_configuration: mode is still OFF after update| ).
  ENDMETHOD.


  METHOD search_index.
    " Indexing must be enabled (done by update_indexing_configuration test or setup).
    " Enable it now in case that test has not yet run.
    TRY.
        ao_iot->updateindexingconfiguration(
          io_thingindexingconf = NEW /aws1/cl_iotthingindexingconf(
            iv_thingindexingmode = 'REGISTRY' ) ).
      CATCH /aws1/cx_rt_generic.
        " May already be enabled.
    ENDTRY.

    " Poll until the shared thing appears in index (up to ~60 s).
    DATA lo_result  TYPE REF TO /aws1/cl_iotsearchindexrsp.
    DATA lv_found   TYPE abap_bool VALUE abap_false.
    DATA lv_attempt TYPE i VALUE 0.

    WHILE lv_attempt < 12 AND lv_found = abap_false.
      TRY.
          lo_result = ao_iot_actions->search_index(
            iv_query = |thingName:{ av_thing_name }| ).
          IF lo_result IS BOUND.
            LOOP AT lo_result->get_things( ) INTO DATA(lo_thing).
              IF lo_thing->get_thingname( ) = av_thing_name.
                lv_found = abap_true.
              ENDIF.
            ENDLOOP.
          ENDIF.
        CATCH /aws1/cx_iotindexnotreadyex.
          " Index not ready yet — wait and retry.
        CATCH /aws1/cx_rt_generic.
          " Transient error — retry.
      ENDTRY.
      IF lv_found = abap_false.
        lv_attempt = lv_attempt + 1.
        WAIT UP TO 5 SECONDS.
      ENDIF.
    ENDWHILE.

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = |search_index: result was never bound after { lv_attempt } attempts| ).

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |search_index: thing '{ av_thing_name }' not found after { lv_attempt } retries| ).
  ENDMETHOD.


  METHOD delete_thing.
    " Use the dedicated delete-thing created in class_setup.
    ao_iot_actions->delete_thing( iv_thing_name = av_del_thing ).

    " Verify: DescribeThing must raise ResourceNotFound.
    DATA lv_gone TYPE abap_bool VALUE abap_false.
    TRY.
        ao_iot->describething( iv_thingname = av_del_thing ).
      CATCH /aws1/cx_iotresourcenotfoundex.
        lv_gone = abap_true.
      CATCH /aws1/cx_rt_generic.
        lv_gone = abap_true.
    ENDTRY.

    cl_abap_unit_assert=>assert_true(
      act = lv_gone
      msg = |delete_thing: thing '{ av_del_thing }' still exists after deletion| ).

    CLEAR av_del_thing.   " Prevent double-delete in class_teardown.
  ENDMETHOD.


  METHOD delete_topic_rule.
    " av_del_rule was pre-created in class_setup.
    ao_iot_actions->delete_topic_rule( iv_rule_name = av_del_rule ).

    " Verify: GetTopicRule must raise an exception.
    DATA lv_gone TYPE abap_bool VALUE abap_false.
    TRY.
        ao_iot->gettopicrule( iv_rulename = av_del_rule ).
      CATCH /aws1/cx_rt_generic.
        lv_gone = abap_true.
    ENDTRY.

    cl_abap_unit_assert=>assert_true(
      act = lv_gone
      msg = |delete_topic_rule: rule '{ av_del_rule }' still exists after deletion| ).

    CLEAR av_del_rule.   " Prevent double-delete in class_teardown.
  ENDMETHOD.

ENDCLASS.
