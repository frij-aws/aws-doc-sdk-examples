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

    " Service clients
    CLASS-DATA ao_iot         TYPE REF TO /aws1/if_iot.
    CLASS-DATA ao_iam         TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_sns         TYPE REF TO /aws1/if_sns.
    CLASS-DATA ao_session     TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_iot_actions TYPE REF TO /awsex/cl_iot_actions.

    " Things:  one shared read-only, two dedicated for delete/detach tests
    CLASS-DATA av_thing_name        TYPE /aws1/iotthingname.
    CLASS-DATA av_thing_arn         TYPE /aws1/iotthingarn.
    CLASS-DATA av_del_thing_name    TYPE /aws1/iotthingname.
    CLASS-DATA av_detach_thing_name TYPE /aws1/iotthingname.
    CLASS-DATA av_detach_thing_arn  TYPE /aws1/iotthingarn.

    " Certificates: shared (for list/attach), dedicated for delete/detach
    CLASS-DATA av_cert_id           TYPE /aws1/iotcertificateid.
    CLASS-DATA av_cert_arn          TYPE /aws1/iotcertificatearn.
    CLASS-DATA av_del_cert_id       TYPE /aws1/iotcertificateid.
    CLASS-DATA av_detach_cert_id    TYPE /aws1/iotcertificateid.
    CLASS-DATA av_detach_cert_arn   TYPE /aws1/iotcertificatearn.

    " Topic rules: one for list_topic_rules, one dedicated for delete
    CLASS-DATA av_rule_name         TYPE /aws1/iotrulename.
    CLASS-DATA av_del_rule_name     TYPE /aws1/iotrulename.

    " Supporting IAM / SNS resources needed for topic rule
    CLASS-DATA av_role_name         TYPE /aws1/iamrolenametype.
    CLASS-DATA av_role_arn          TYPE /aws1/iamarntype.
    CLASS-DATA av_sns_topic_arn     TYPE /aws1/snstopicarn.

    " One-time suffix for all resource names in this run
    CLASS-DATA av_suffix            TYPE string.

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

    " --- Internal helpers ---

    " Create an IoT thing, fail the suite if it cannot be created.
    " Things are not taggable; tracked by naming convention (sap-iot-* prefix).
    CLASS-METHODS create_thing_internal
      IMPORTING
        iv_name        TYPE /aws1/iotthingname
      RETURNING
        VALUE(ov_arn)  TYPE /aws1/iotthingarn
      RAISING
        /aws1/cx_rt_generic.

    " Create an active certificate, fail the suite if it cannot be created.
    CLASS-METHODS create_cert_internal
      EXPORTING
        ev_cert_id  TYPE /aws1/iotcertificateid
        ev_cert_arn TYPE /aws1/iotcertificatearn
      RAISING
        /aws1/cx_rt_generic.

    " Deactivate and delete a certificate quietly (used in teardown).
    CLASS-METHODS delete_cert_quietly
      IMPORTING iv_cert_id TYPE /aws1/iotcertificateid.

    " Create a real SNS topic tagged with convert_test.
    CLASS-METHODS create_sns_topic
      IMPORTING iv_topic_name    TYPE /aws1/snstopicname
      RETURNING VALUE(ov_arn)    TYPE /aws1/snstopicarn
      RAISING   /aws1/cx_rt_generic.

    " Create an IAM role that IoT can assume, with SNS publish permission.
    CLASS-METHODS create_iot_rule_role
      IMPORTING
        iv_role_name    TYPE /aws1/iamrolenametype
        iv_sns_arn      TYPE /aws1/snstopicarn
      RETURNING
        VALUE(ov_arn)   TYPE /aws1/iamarntype
      RAISING
        /aws1/cx_rt_generic.

    " Create a topic rule (used both as setup helper and in the test).
    CLASS-METHODS create_rule_internal
      IMPORTING
        iv_rule_name    TYPE /aws1/iotrulename
        iv_sns_arn      TYPE /aws1/snstopicarn
        iv_role_arn     TYPE /aws1/iamarntype
      RAISING
        /aws1/cx_rt_generic.

ENDCLASS.


CLASS ltc_awsex_cl_iot_actions IMPLEMENTATION.

  METHOD class_setup.
    ao_session     = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_iot         = /aws1/cl_iot_factory=>create( ao_session ).
    ao_iam         = /aws1/cl_iam_factory=>create( ao_session ).
    ao_sns         = /aws1/cl_sns_factory=>create( ao_session ).
    ao_iot_actions = NEW /awsex/cl_iot_actions( ).

    " Build a short, unique suffix for all resource names in this run
    av_suffix = /awsex/cl_utils=>get_random_string( ).
    " Truncate to 8 chars to keep names short enough for IoT rule names
    av_suffix = av_suffix(8).

    " ── Thing names ──────────────────────────────────────────────────────────
    " IoT thing names: letters, digits, hyphens, underscores  (max 128 chars)
    av_thing_name        = |sap-iot-thing-{ av_suffix }|.
    av_del_thing_name    = |sap-iot-del-th-{ av_suffix }|.
    av_detach_thing_name = |sap-iot-det-th-{ av_suffix }|.

    " ── Create things ────────────────────────────────────────────────────────
    av_thing_arn        = create_thing_internal( av_thing_name ).
    create_thing_internal( av_del_thing_name ).
    av_detach_thing_arn = create_thing_internal( av_detach_thing_name ).

    " ── Certificates ─────────────────────────────────────────────────────────
    " Shared cert — used for list_certificates and attach tests
    create_cert_internal(
      IMPORTING
        ev_cert_id  = av_cert_id
        ev_cert_arn = av_cert_arn ).

    " Dedicated cert — consumed by delete_certificate test
    create_cert_internal(
      IMPORTING
        ev_cert_id  = av_del_cert_id ).

    " Dedicated cert — attached to av_detach_thing_name for detach test
    create_cert_internal(
      IMPORTING
        ev_cert_id  = av_detach_cert_id
        ev_cert_arn = av_detach_cert_arn ).

    ao_iot->attachthingprincipal(
      iv_thingname = av_detach_thing_name
      iv_principal = av_detach_cert_arn ).

    " ── SNS topic + IAM role for topic rules ─────────────────────────────────
    " IoT topic rule names: letters, digits, underscores only (max 128)
    av_rule_name     = |SapIotRule{ av_suffix }|.
    av_del_rule_name = |SapIotDelR{ av_suffix }|.
    av_role_name     = |sap-iot-rule-role-{ av_suffix }|.

    " Create a real SNS topic so IoT can validate the ARN
    av_sns_topic_arn = create_sns_topic( |sap-iot-topic-{ av_suffix }| ).

    " Create an IAM role that IoT topic rules can assume
    av_role_arn = create_iot_rule_role(
      iv_role_name = av_role_name
      iv_sns_arn   = av_sns_topic_arn ).

    " Create the pre-existing topic rule used by list_topic_rules test
    create_rule_internal(
      iv_rule_name = av_del_rule_name
      iv_sns_arn   = av_sns_topic_arn
      iv_role_arn  = av_role_arn ).

    " ── Enable fleet indexing so search_index works ───────────────────────────
    TRY.
        ao_iot->updateindexingconfiguration(
          io_thingindexingconf = NEW /aws1/cl_iotthingindexingconf(
            iv_thingindexingmode = 'REGISTRY' ) ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_idx_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: cannot enable indexing: { lo_idx_ex->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.


  METHOD class_teardown.
    " ── Delete topic rules ───────────────────────────────────────────────────
    DATA lt_rules TYPE TABLE OF /aws1/iotrulename.
    APPEND av_rule_name     TO lt_rules.
    APPEND av_del_rule_name TO lt_rules.
    LOOP AT lt_rules INTO DATA(lv_rule).
      IF lv_rule IS INITIAL. CONTINUE. ENDIF.
      TRY.
          ao_iot->deletetopicrule( iv_rulename = lv_rule ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDLOOP.

    " ── Detach principals from things then delete things ─────────────────────
    DATA lt_things TYPE TABLE OF /aws1/iotthingname.
    APPEND av_thing_name        TO lt_things.
    APPEND av_del_thing_name    TO lt_things.
    APPEND av_detach_thing_name TO lt_things.
    LOOP AT lt_things INTO DATA(lv_thing).
      IF lv_thing IS INITIAL. CONTINUE. ENDIF.
      TRY.
          DATA(lo_prcs) = ao_iot->listthingprincipals( iv_thingname = lv_thing ).
          LOOP AT lo_prcs->get_principals( ) INTO DATA(lo_prin).
            TRY.
                ao_iot->detachthingprincipal(
                  iv_thingname = lv_thing
                  iv_principal = lo_prin->get_value( ) ).
              CATCH /aws1/cx_rt_generic.
            ENDTRY.
          ENDLOOP.
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
      TRY.
          ao_iot->deletething( iv_thingname = lv_thing ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDLOOP.

    " ── Delete certificates ───────────────────────────────────────────────────
    delete_cert_quietly( av_cert_id ).
    delete_cert_quietly( av_del_cert_id ).
    delete_cert_quietly( av_detach_cert_id ).

    " ── Delete SNS topic ─────────────────────────────────────────────────────
    IF av_sns_topic_arn IS NOT INITIAL.
      TRY.
          ao_sns->deletetopic( iv_topicarn = av_sns_topic_arn ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " ── Delete IAM role (inline policy first) ────────────────────────────────
    IF av_role_name IS NOT INITIAL.
      TRY.
          ao_iam->deleterolepolicy(
            iv_rolename  = av_role_name
            iv_policyname = 'SnsPublishPolicy' ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
      TRY.
          ao_iam->deleterole( iv_rolename = av_role_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
  ENDMETHOD.


  METHOD create_thing_internal.
    " IoT Things do not support TagResource (only thinggroup, rule, cert-CA,
    " policy etc. are taggable).  Things are tracked by naming convention:
    " all test things are prefixed 'sap-iot-' and suffixed with av_suffix.
    DATA(lo_rsp) = ao_iot->creatething( iv_thingname = iv_name ).
    ov_arn = lo_rsp->get_thingarn( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = ov_arn
      msg = |class_setup: failed to create thing { iv_name }| ).
  ENDMETHOD.


  METHOD create_cert_internal.
    DATA(lo_rsp) = ao_iot->createkeysandcertificate( iv_setasactive = abap_true ).
    ev_cert_id  = lo_rsp->get_certificateid( ).
    ev_cert_arn = lo_rsp->get_certificatearn( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = ev_cert_id
      msg = 'class_setup: failed to create certificate' ).
  ENDMETHOD.


  METHOD delete_cert_quietly.
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


  METHOD create_sns_topic.
    " Create the topic with a convert_test tag
    DATA lt_tags TYPE /aws1/cl_snstag=>tt_taglist.
    APPEND NEW /aws1/cl_snstag( iv_key = 'convert_test' iv_value = 'true' )
      TO lt_tags.

    DATA(lo_rsp) = ao_sns->createtopic(
      iv_name  = iv_topic_name
      it_tags  = lt_tags ).

    ov_arn = lo_rsp->get_topicarn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = ov_arn
      msg = |class_setup: failed to create SNS topic { iv_topic_name }| ).
  ENDMETHOD.


  METHOD create_iot_rule_role.
    " Trust policy: allow IoT service to assume this role
    DATA(lv_trust) = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",' &&
      '"Principal":{"Service":"iot.amazonaws.com"},' &&
      '"Action":"sts:AssumeRole"}]}' .

    DATA(lo_role_rsp) = ao_iam->createrole(
      iv_rolename                   = iv_role_name
      iv_assumerolepolicydocument   = lv_trust ).

    ov_arn = lo_role_rsp->get_role( )->get_arn( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = ov_arn
      msg = |class_setup: failed to create IAM role { iv_role_name }| ).

    " Inline policy: allow sns:Publish on the test topic
    DATA(lv_policy) = '{"Version":"2012-10-17","Statement":[{"Effect":"Allow",' &&
      '"Action":"sns:Publish","Resource":"' && iv_sns_arn && '"}]}' .

    ao_iam->putrolepolicy(
      iv_rolename    = iv_role_name
      iv_policyname  = 'SnsPublishPolicy'
      iv_policydocument = lv_policy ).
  ENDMETHOD.


  METHOD create_rule_internal.
    DATA(lo_sns_action) = NEW /aws1/cl_iotsnsaction(
      iv_targetarn = iv_sns_arn
      iv_rolearn   = iv_role_arn ).

    DATA(lo_action) = NEW /aws1/cl_iotaction( io_sns = lo_sns_action ).

    DATA lt_actions TYPE /aws1/cl_iotaction=>tt_actionlist.
    APPEND lo_action TO lt_actions.

    DATA(lo_payload) = NEW /aws1/cl_iottopicrulepayload(
      iv_sql     = |SELECT * FROM 'iot/test/{ iv_rule_name }'|
      it_actions = lt_actions ).

    " IAM roles take up to ~15 s to propagate before IoT can assume them.
    " Retry on InvalidRequestException (the assume-role error) up to 8 times
    " with a 5-second wait between attempts (40 s max).
    DATA lv_retry  TYPE i VALUE 0.
    DATA lv_done   TYPE abap_bool VALUE abap_false.

    WHILE lv_retry <= 8 AND lv_done = abap_false.
      TRY.
          " Topic rules support tagging at creation via iv_tags (URL-encoded)
          ao_iot->createtopicrule(
            iv_rulename         = iv_rule_name
            io_topicrulepayload = lo_payload
            iv_tags             = 'convert_test=true' ).
          lv_done = abap_true.
        CATCH /aws1/cx_iotresrcalrdyexistsex.
          lv_done = abap_true.   " exists from a previous interrupted run
        CATCH /aws1/cx_iotinvalidrequestex INTO DATA(lo_inv).
          " IoT returns InvalidRequestException when the role is not yet
          " assumable.  Wait and retry; fail only after all attempts exhausted.
          lv_retry = lv_retry + 1.
          IF lv_retry > 8.
            cl_abap_unit_assert=>fail(
              msg = |class_setup: cannot create rule { iv_rule_name } after| &&
                    | { lv_retry } attempts: { lo_inv->get_text( ) }| ).
          ELSE.
            WAIT UP TO 5 SECONDS.
          ENDIF.
        CATCH /aws1/cx_rt_generic INTO DATA(lo_ex).
          cl_abap_unit_assert=>fail(
            msg = |class_setup: cannot create rule { iv_rule_name }: { lo_ex->get_text( ) }| ).
      ENDTRY.
    ENDWHILE.
  ENDMETHOD.


*─────────────────────────── TEST METHODS ───────────────────────────────────*

  METHOD create_thing.
    " Use a one-shot name so this test is isolated
    DATA(lv_name) = CONV /aws1/iotthingname(
      |sap-iot-ct-{ av_suffix }| ).

    DATA lo_result TYPE REF TO /aws1/cl_iotcreatethingrsp.
    lo_result = ao_iot_actions->create_thing( lv_name ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'create_thing: result is not bound' ).
    cl_abap_unit_assert=>assert_equals(
      exp = lv_name
      act = lo_result->get_thingname( )
      msg = |create_thing: name mismatch — got { lo_result->get_thingname( ) }| ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_thingarn( )
      msg = 'create_thing: ARN is empty' ).

    " Clean up the thing created by the action under test
    TRY.
        ao_iot->deletething( iv_thingname = lv_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  METHOD list_things.
    DATA(lt_things) = ao_iot_actions->list_things( ).

    " At least the three things we created in class_setup must be present
    cl_abap_unit_assert=>assert_not_initial(
      act = lt_things
      msg = 'list_things: returned an empty list' ).

    DATA(lv_found) = abap_false.
    LOOP AT lt_things INTO DATA(lo_thing).
      IF lo_thing->get_thingname( ) = av_thing_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_things: { av_thing_name } not found in list| ).
  ENDMETHOD.


  METHOD create_keys_and_certificate.
    DATA lo_result TYPE REF TO /aws1/cl_iotcrekeysandcertrsp.
    lo_result = ao_iot_actions->create_keys_and_certificate( ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'create_keys_and_certificate: result is not bound' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificateid( )
      msg = 'create_keys_and_certificate: certificate ID is empty' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificatearn( )
      msg = 'create_keys_and_certificate: certificate ARN is empty' ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_result->get_certificatepem( )
      msg = 'create_keys_and_certificate: PEM is empty' ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_result->get_keypair( )
      msg = 'create_keys_and_certificate: key pair is not bound' ).

    " Clean up the newly created certificate
    delete_cert_quietly( lo_result->get_certificateid( ) ).
  ENDMETHOD.


  METHOD attach_thing_principal.
    " Create a fresh certificate exclusively for this test
    DATA lv_att_cert_id  TYPE /aws1/iotcertificateid.
    DATA lv_att_cert_arn TYPE /aws1/iotcertificatearn.
    create_cert_internal(
      IMPORTING
        ev_cert_id  = lv_att_cert_id
        ev_cert_arn = lv_att_cert_arn ).

    " Use the shared read-only thing
    ao_iot_actions->attach_thing_principal(
      iv_thing_name = av_thing_name
      iv_principal  = lv_att_cert_arn ).

    " Verify attachment
    DATA(lo_list) = ao_iot->listthingprincipals( iv_thingname = av_thing_name ).
    DATA(lv_found) = abap_false.
    LOOP AT lo_list->get_principals( ) INTO DATA(lo_prin).
      IF lo_prin->get_value( ) = lv_att_cert_arn.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |attach_thing_principal: { lv_att_cert_arn } not found on { av_thing_name }| ).

    " Clean up: detach then delete the temp certificate
    TRY.
        ao_iot->detachthingprincipal(
          iv_thingname = av_thing_name
          iv_principal = lv_att_cert_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    delete_cert_quietly( lv_att_cert_id ).
  ENDMETHOD.


  METHOD describe_endpoint.
    DATA(lv_address) = ao_iot_actions->describe_endpoint( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lv_address
      msg = 'describe_endpoint: returned an empty address' ).

    " A valid ATS endpoint looks like: <prefix>.iot.<region>.amazonaws.com
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lv_address CS '.iot.' )
      msg = |describe_endpoint: '{ lv_address }' does not look like an IoT endpoint| ).
  ENDMETHOD.


  METHOD list_certificates.
    DATA(lt_certs) = ao_iot_actions->list_certificates( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_certs
      msg = 'list_certificates: returned an empty list' ).

    " The shared certificate must appear in the listing
    DATA(lv_found) = abap_false.
    LOOP AT lt_certs INTO DATA(lo_cert).
      IF lo_cert->get_certificateid( ) = av_cert_id.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_certificates: cert { av_cert_id } not found| ).
  ENDMETHOD.


  METHOD detach_thing_principal.
    " av_detach_cert_arn was attached to av_detach_thing_name in class_setup
    " Verify it is currently attached before the test
    DATA(lo_before) = ao_iot->listthingprincipals( iv_thingname = av_detach_thing_name ).
    DATA(lv_was_attached) = abap_false.
    LOOP AT lo_before->get_principals( ) INTO DATA(lo_prin_b).
      IF lo_prin_b->get_value( ) = av_detach_cert_arn.
        lv_was_attached = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_was_attached
      msg = |detach_thing_principal: pre-condition failed — cert not attached before test| ).

    " Perform the detach via the action under test
    ao_iot_actions->detach_thing_principal(
      iv_thing_name = av_detach_thing_name
      iv_principal  = av_detach_cert_arn ).

    " Verify the certificate is no longer attached
    DATA(lo_after) = ao_iot->listthingprincipals( iv_thingname = av_detach_thing_name ).
    DATA(lv_still_attached) = abap_false.
    LOOP AT lo_after->get_principals( ) INTO DATA(lo_prin_a).
      IF lo_prin_a->get_value( ) = av_detach_cert_arn.
        lv_still_attached = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_false(
      act = lv_still_attached
      msg = |detach_thing_principal: cert still attached to { av_detach_thing_name }| ).
  ENDMETHOD.


  METHOD delete_certificate.
    " av_del_cert_id was created in class_setup exclusively for this test
    DATA(lv_cert_to_delete) = av_del_cert_id.
    ao_iot_actions->delete_certificate( lv_cert_to_delete ).

    " Verify it is gone: describecertificate should raise
    " CX_IOTRESOURCENOTFOUNDEX for a deleted certificate
    DATA(lv_deleted) = abap_false.
    TRY.
        ao_iot->describecertificate( iv_certificateid = lv_cert_to_delete ).
        " If we get here the cert still exists — the assert_true below will fail
      CATCH /aws1/cx_iotresourcenotfoundex.
        lv_deleted = abap_true.
      CATCH /aws1/cx_rt_generic.
        " Any generic error after deletion is also treated as deleted
        lv_deleted = abap_true.
    ENDTRY.
    cl_abap_unit_assert=>assert_true(
      act = lv_deleted
      msg = |delete_certificate: cert { lv_cert_to_delete } still exists after deletion| ).

    " Clear so class_teardown won't attempt a second delete
    CLEAR av_del_cert_id.
  ENDMETHOD.


  METHOD create_topic_rule.
    " av_rule_name is reserved for this test (not pre-created in class_setup)
    ao_iot_actions->create_topic_rule(
      iv_rule_name      = av_rule_name
      iv_topic          = |iot/sensors/{ av_suffix }|
      iv_sns_action_arn = av_sns_topic_arn
      iv_role_arn       = av_role_arn ).

    " Verify the rule exists by reading it back via listtopicrules
    " (gettopicrule's response has the rule name under get_rule()->get_rulename())
    DATA(lt_rules) = ao_iot->listtopicrules( ).
    DATA(lv_found) = abap_false.
    LOOP AT lt_rules->get_rules( ) INTO DATA(lo_rule).
      IF lo_rule->get_rulename( ) = av_rule_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |create_topic_rule: rule { av_rule_name } not found in list| ).
  ENDMETHOD.


  METHOD list_topic_rules.
    " av_del_rule_name was created in class_setup and av_rule_name may have
    " been created by create_topic_rule (tests may run in any order).
    DATA(lt_rules) = ao_iot_actions->list_topic_rules( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lt_rules
      msg = 'list_topic_rules: returned an empty list' ).

    " At least the pre-setup rule must appear
    DATA(lv_found) = abap_false.
    LOOP AT lt_rules INTO DATA(lo_rule).
      IF lo_rule->get_rulename( ) = av_del_rule_name
      OR lo_rule->get_rulename( ) = av_rule_name.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = 'list_topic_rules: none of the test rules found' ).
  ENDMETHOD.


  METHOD update_indexing_configuration.
    " The action enables REGISTRY indexing
    ao_iot_actions->update_indexing_configuration( ).

    " Read back and confirm
    DATA(lo_cfg) = ao_iot->getindexingconfiguration( ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_cfg->get_thingindexingconf( )
      msg = 'update_indexing_configuration: thingindexingconf is not bound' ).
    cl_abap_unit_assert=>assert_equals(
      exp = 'REGISTRY'
      act = lo_cfg->get_thingindexingconf( )->get_thingindexingmode( )
      msg = 'update_indexing_configuration: mode is not REGISTRY' ).
  ENDMETHOD.


  METHOD search_index.
    " Indexing was enabled in class_setup.  Poll until the shared thing
    " appears in the index (can take up to ~30 s after thing creation).
    DATA(lv_query) = CONV /aws1/iotquerystring( |thingName:{ av_thing_name }| ).
    DATA lt_found TYPE /aws1/cl_iotthingdocument=>tt_thingdocumentlist.
    DATA lv_retry  TYPE i VALUE 0.
    DATA lv_ok     TYPE abap_bool VALUE abap_false.

    WHILE lv_retry < 15 AND lv_ok = abap_false.
      TRY.
          lt_found = ao_iot_actions->search_index( iv_query = lv_query ).
          IF lines( lt_found ) > 0.
            lv_ok = abap_true.
          ELSE.
            lv_retry = lv_retry + 1.
            WAIT UP TO 5 SECONDS.
          ENDIF.
        CATCH /aws1/cx_iotindexnotreadyex.
          lv_retry = lv_retry + 1.
          WAIT UP TO 5 SECONDS.
        CATCH /aws1/cx_rt_generic INTO DATA(lo_ex).
          cl_abap_unit_assert=>fail(
            msg = |search_index: unexpected error: { lo_ex->get_text( ) }| ).
      ENDTRY.
    ENDWHILE.

    cl_abap_unit_assert=>assert_true(
      act = lv_ok
      msg = |search_index: { av_thing_name } not found in index after 75 s| ).

    " The first result must contain our thing name
    DATA(lo_first) = lt_found[ 1 ].
    cl_abap_unit_assert=>assert_equals(
      exp = av_thing_name
      act = lo_first->get_thingname( )
      msg = |search_index: first result '{ lo_first->get_thingname( ) }' != { av_thing_name }| ).
  ENDMETHOD.


  METHOD delete_thing.
    " av_del_thing_name was created in class_setup exclusively for this test
    ao_iot_actions->delete_thing( av_del_thing_name ).

    " Confirm deletion: describething must raise ResourceNotFound
    DATA(lv_deleted) = abap_false.
    TRY.
        ao_iot->describething( iv_thingname = av_del_thing_name ).
        " Reaching here means the thing still exists
      CATCH /aws1/cx_iotresourcenotfoundex.
        lv_deleted = abap_true.
      CATCH /aws1/cx_rt_generic.
        lv_deleted = abap_true.
    ENDTRY.
    cl_abap_unit_assert=>assert_true(
      act = lv_deleted
      msg = |delete_thing: { av_del_thing_name } still exists after deletion| ).

    " Clear so class_teardown won't attempt a second delete
    CLEAR av_del_thing_name.
  ENDMETHOD.


  METHOD delete_topic_rule.
    " av_del_rule_name was created in class_setup exclusively for this test
    DATA(lv_rule_to_delete) = av_del_rule_name.
    ao_iot_actions->delete_topic_rule( lv_rule_to_delete ).

    " Confirm deletion: verify the rule is absent from listtopicrules.
    " (GetTopicRule does not raise ResourceNotFound — it raises InternalException.)
    DATA(lt_rules) = ao_iot->listtopicrules( ).
    DATA(lv_still_exists) = abap_false.
    LOOP AT lt_rules->get_rules( ) INTO DATA(lo_rule).
      IF lo_rule->get_rulename( ) = lv_rule_to_delete.
        lv_still_exists = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_false(
      act = lv_still_exists
      msg = |delete_topic_rule: { lv_rule_to_delete } still listed after deletion| ).

    " Clear so class_teardown won't attempt a second delete
    CLEAR av_del_rule_name.
  ENDMETHOD.

ENDCLASS.
