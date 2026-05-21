" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS /awsex/cl_iot_actions DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    " Creates an AWS IoT thing.
    " @parameter iv_thing_name | The name of the thing to create (e.g., 'MyIoTThing')
    " @parameter oo_result     | The result object containing the created thing name and ARN
    " @raising /aws1/cx_rt_generic | Thrown when the operation fails
    METHODS create_thing
      IMPORTING
        !iv_thing_name TYPE /aws1/iotthingname
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_iotcreatethingrsp
      RAISING
        /aws1/cx_rt_generic.

    " Lists all AWS IoT things.
    " @parameter ot_things | The table of things
    " @raising /aws1/cx_rt_generic | Thrown when the operation fails
    METHODS list_things
      RETURNING
        VALUE(ot_things) TYPE /aws1/cl_iotthingattribute=>tt_thingattrlist
      RAISING
        /aws1/cx_rt_generic.

    " Creates keys and a certificate for an AWS IoT thing.
    " @parameter oo_result | The result object containing the certificate ID, ARN, and PEM
    " @raising /aws1/cx_rt_generic | Thrown when the operation fails
    METHODS create_keys_and_certificate
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_iotcrekeysandcertrsp
      RAISING
        /aws1/cx_rt_generic.

    " Attaches a certificate to an AWS IoT thing.
    " @parameter iv_thing_name | The name of the thing (e.g., 'MyIoTThing')
    " @parameter iv_principal  | The ARN of the certificate
    " @raising /aws1/cx_rt_generic | Thrown when the operation fails
    METHODS attach_thing_principal
      IMPORTING
        !iv_thing_name TYPE /aws1/iotthingname
        !iv_principal  TYPE /aws1/iotprincipal
      RAISING
        /aws1/cx_rt_generic.

    " Gets the AWS IoT endpoint address.
    " @parameter iv_endpoint_type | The endpoint type (e.g., 'iot:Data-ATS')
    " @parameter ov_endpoint      | The endpoint address
    " @raising /aws1/cx_rt_generic | Thrown when the operation fails
    METHODS describe_endpoint
      IMPORTING
        !iv_endpoint_type TYPE /aws1/iotendpointtype
                          DEFAULT 'iot:Data-ATS'
      RETURNING
        VALUE(ov_endpoint) TYPE /aws1/iotendpointaddress
      RAISING
        /aws1/cx_rt_generic.

    " Lists all AWS IoT certificates.
    " @parameter ot_certs | The table of certificates
    " @raising /aws1/cx_rt_generic | Thrown when the operation fails
    METHODS list_certificates
      RETURNING
        VALUE(ot_certs) TYPE /aws1/cl_iotcertificate=>tt_certificates
      RAISING
        /aws1/cx_rt_generic.

    " Detaches a certificate from an AWS IoT thing.
    " @parameter iv_thing_name | The name of the thing (e.g., 'MyIoTThing')
    " @parameter iv_principal  | The ARN of the certificate
    " @raising /aws1/cx_rt_generic | Thrown when the operation fails
    METHODS detach_thing_principal
      IMPORTING
        !iv_thing_name TYPE /aws1/iotthingname
        !iv_principal  TYPE /aws1/iotprincipal
      RAISING
        /aws1/cx_rt_generic.

    " Deactivates and deletes an AWS IoT certificate.
    " @parameter iv_certificate_id | The ID of the certificate to delete (e.g., 'abc123...')
    " @raising /aws1/cx_rt_generic | Thrown when the operation fails
    METHODS delete_certificate
      IMPORTING
        !iv_certificate_id TYPE /aws1/iotcertificateid
      RAISING
        /aws1/cx_rt_generic.

    " Creates an AWS IoT topic rule that publishes to an SNS topic.
    " @parameter iv_rule_name      | The name of the rule (e.g., 'MyTopicRule')
    " @parameter iv_topic          | The MQTT topic to subscribe to (e.g., 'my/topic')
    " @parameter iv_sns_action_arn | The ARN of the SNS topic
    " @parameter iv_role_arn       | The ARN of the IAM role
    " @raising /aws1/cx_rt_generic | Thrown when the operation fails
    METHODS create_topic_rule
      IMPORTING
        !iv_rule_name      TYPE /aws1/iotrulename
        !iv_topic          TYPE /aws1/iottopic
        !iv_sns_action_arn TYPE /aws1/iotawsarn
        !iv_role_arn       TYPE /aws1/iotawsarn
      RAISING
        /aws1/cx_rt_generic.

    " Lists all AWS IoT topic rules.
    " @parameter ot_rules | The table of topic rules
    " @raising /aws1/cx_rt_generic | Thrown when the operation fails
    METHODS list_topic_rules
      RETURNING
        VALUE(ot_rules) TYPE /aws1/cl_iottopicrulelst=>tt_topicruleslist
      RAISING
        /aws1/cx_rt_generic.

    " Searches the AWS IoT fleet index.
    " @parameter iv_query   | The search query string (e.g., 'thingName:My*')
    " @parameter ot_things  | The table of matching things
    " @raising /aws1/cx_rt_generic | Thrown when the operation fails
    METHODS search_index
      IMPORTING
        !iv_query TYPE /aws1/iotquerystring
      RETURNING
        VALUE(ot_things) TYPE /aws1/cl_iotthingdocument=>tt_thingdocumentlist
      RAISING
        /aws1/cx_rt_generic.

    " Updates the AWS IoT indexing configuration to enable thing indexing.
    " @raising /aws1/cx_rt_generic | Thrown when the operation fails
    METHODS update_indexing_configuration
      RAISING
        /aws1/cx_rt_generic.

    " Deletes an AWS IoT thing.
    " @parameter iv_thing_name | The name of the thing to delete (e.g., 'MyIoTThing')
    " @raising /aws1/cx_rt_generic | Thrown when the operation fails
    METHODS delete_thing
      IMPORTING
        !iv_thing_name TYPE /aws1/iotthingname
      RAISING
        /aws1/cx_rt_generic.

    " Deletes an AWS IoT topic rule.
    " @parameter iv_rule_name | The name of the rule to delete (e.g., 'MyTopicRule')
    " @raising /aws1/cx_rt_generic | Thrown when the operation fails
    METHODS delete_topic_rule
      IMPORTING
        !iv_rule_name TYPE /aws1/iotrulename
      RAISING
        /aws1/cx_rt_generic.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS /awsex/cl_iot_actions IMPLEMENTATION.

  METHOD create_thing.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.create_thing]
    TRY.
        " iv_thing_name example value: 'MyIoTThing'
        oo_result = lo_iot->creatething( iv_thingname = iv_thing_name ).
        MESSAGE |IoT thing created: { oo_result->get_thingname( ) } ARN: { oo_result->get_thingarn( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex INTO DATA(lo_already_exists).
        MESSAGE |Thing { iv_thing_name } already exists.| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc /aws1/cx_iotserverexc INTO DATA(lo_exception).
        MESSAGE lo_exception->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.create_thing]
  ENDMETHOD.


  METHOD list_things.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.list_things]
    TRY.
        DATA(lo_result) = lo_iot->listthings( ).
        ot_things = lo_result->get_things( ).
        MESSAGE |Retrieved { lines( ot_things ) } IoT things| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc /aws1/cx_iotserverexc INTO DATA(lo_exception).
        MESSAGE lo_exception->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.list_things]
  ENDMETHOD.


  METHOD create_keys_and_certificate.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.create_keys_and_certificate]
    TRY.
        oo_result = lo_iot->createkeysandcertificate( iv_setasactive = abap_true ).
        MESSAGE |Certificate created: { oo_result->get_certificateid( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc /aws1/cx_iotserverexc INTO DATA(lo_exception).
        MESSAGE lo_exception->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.create_keys_and_certificate]
  ENDMETHOD.


  METHOD attach_thing_principal.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.attach_thing_principal]
    TRY.
        " iv_thing_name example value: 'MyIoTThing'
        " iv_principal  example value: 'arn:aws:iot:us-east-1:123456789012:cert/abc123'
        lo_iot->attachthingprincipal(
          iv_thingname = iv_thing_name
          iv_principal = iv_principal ).
        MESSAGE |Principal { iv_principal } attached to thing { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_not_found).
        MESSAGE |Resource not found: { lo_not_found->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc /aws1/cx_iotserverexc INTO DATA(lo_exception).
        MESSAGE lo_exception->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.attach_thing_principal]
  ENDMETHOD.


  METHOD describe_endpoint.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.describe_endpoint]
    TRY.
        " iv_endpoint_type example value: 'iot:Data-ATS'
        DATA(lo_result) = lo_iot->describeendpoint( iv_endpoint_type ).
        ov_endpoint = lo_result->get_endpointaddress( ).
        MESSAGE |Endpoint address: { ov_endpoint }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc /aws1/cx_iotserverexc INTO DATA(lo_exception).
        MESSAGE lo_exception->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.describe_endpoint]
  ENDMETHOD.


  METHOD list_certificates.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.list_certificates]
    TRY.
        DATA lv_marker TYPE /aws1/iotmarker.
        DATA lv_done   TYPE abap_bool VALUE abap_false.

        WHILE lv_done = abap_false.
          DATA(lo_result) = lo_iot->listcertificates( iv_marker = lv_marker ).
          APPEND LINES OF lo_result->get_certificates( ) TO ot_certs.
          lv_marker = lo_result->get_nextmarker( ).
          IF lv_marker IS INITIAL.
            lv_done = abap_true.
          ENDIF.
        ENDWHILE.

        MESSAGE |Retrieved { lines( ot_certs ) } IoT certificates| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc /aws1/cx_iotserverexc INTO DATA(lo_exception).
        MESSAGE lo_exception->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.list_certificates]
  ENDMETHOD.


  METHOD detach_thing_principal.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.detach_thing_principal]
    TRY.
        " iv_thing_name example value: 'MyIoTThing'
        " iv_principal  example value: 'arn:aws:iot:us-east-1:123456789012:cert/abc123'
        lo_iot->detachthingprincipal(
          iv_thingname = iv_thing_name
          iv_principal = iv_principal ).
        MESSAGE |Principal { iv_principal } detached from thing { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_not_found).
        MESSAGE |Resource not found: { lo_not_found->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc /aws1/cx_iotserverexc INTO DATA(lo_exception).
        MESSAGE lo_exception->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.detach_thing_principal]
  ENDMETHOD.


  METHOD delete_certificate.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.delete_certificate]
    TRY.
        " iv_certificate_id example value: 'abc123def456...'
        lo_iot->updatecertificate(
          iv_certificateid = iv_certificate_id
          iv_newstatus     = 'INACTIVE' ).
        lo_iot->deletecertificate( iv_certificateid = iv_certificate_id ).
        MESSAGE |Certificate deleted: { iv_certificate_id }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_not_found).
        MESSAGE |Certificate not found: { lo_not_found->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc /aws1/cx_iotserverexc INTO DATA(lo_exception).
        MESSAGE lo_exception->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_certificate]
  ENDMETHOD.


  METHOD create_topic_rule.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.create_topic_rule]
    TRY.
        " iv_rule_name      example value: 'MyTopicRule'
        " iv_topic          example value: 'my/iot/topic'
        " iv_sns_action_arn example value: 'arn:aws:sns:us-east-1:123456789012:MyTopic'
        " iv_role_arn       example value: 'arn:aws:iam::123456789012:role/MyIoTRole'
        DATA(lv_sql) = |SELECT * FROM '{ iv_topic }'|.

        DATA lt_actions TYPE /aws1/cl_iotaction=>tt_actionlist.
        APPEND NEW /aws1/cl_iotaction(
          io_sns = NEW /aws1/cl_iotsnsaction(
            iv_targetarn = iv_sns_action_arn
            iv_rolearn   = iv_role_arn )
        ) TO lt_actions.

        lo_iot->createtopicrule(
          iv_rulename         = iv_rule_name
          io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
            iv_sql        = lv_sql
            it_actions    = lt_actions ) ).
        MESSAGE |Topic rule created: { iv_rule_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex INTO DATA(lo_already_exists).
        MESSAGE |Topic rule { iv_rule_name } already exists.| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc /aws1/cx_iotserverexc INTO DATA(lo_exception).
        MESSAGE lo_exception->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.create_topic_rule]
  ENDMETHOD.


  METHOD list_topic_rules.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.list_topic_rules]
    TRY.
        DATA lv_next_token TYPE /aws1/iotnexttoken.
        DATA lv_done       TYPE abap_bool VALUE abap_false.

        WHILE lv_done = abap_false.
          DATA(lo_result) = lo_iot->listtopicrules( iv_nexttoken = lv_next_token ).
          APPEND LINES OF lo_result->get_rules( ) TO ot_rules.
          lv_next_token = lo_result->get_nexttoken( ).
          IF lv_next_token IS INITIAL.
            lv_done = abap_true.
          ENDIF.
        ENDWHILE.

        MESSAGE |Retrieved { lines( ot_rules ) } IoT topic rules| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc /aws1/cx_iotserverexc INTO DATA(lo_exception).
        MESSAGE lo_exception->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.list_topic_rules]
  ENDMETHOD.


  METHOD search_index.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.search_index]
    TRY.
        " iv_query example value: 'thingName:My*'
        DATA(lo_result) = lo_iot->searchindex( iv_querystring = iv_query ).
        ot_things = lo_result->get_things( ).
        MESSAGE |Found { lines( ot_things ) } IoT things matching query| TYPE 'I'.
      CATCH /aws1/cx_iotindexnotreadyex INTO DATA(lo_not_ready).
        MESSAGE |Index not ready: { lo_not_ready->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc /aws1/cx_iotserverexc INTO DATA(lo_exception).
        MESSAGE lo_exception->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.search_index]
  ENDMETHOD.


  METHOD update_indexing_configuration.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.update_indexing_configuration]
    TRY.
        lo_iot->updateindexingconfiguration(
          io_thingindexingconf = NEW /aws1/cl_iotthingindexingconf(
            " 'REGISTRY' enables indexing of thing registry data
            iv_thingindexingmode = 'REGISTRY' ) ).
        MESSAGE 'IoT indexing configuration updated to REGISTRY mode' TYPE 'I'.
      CATCH /aws1/cx_iotclientexc /aws1/cx_iotserverexc INTO DATA(lo_exception).
        MESSAGE lo_exception->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.update_indexing_configuration]
  ENDMETHOD.


  METHOD delete_thing.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.delete_thing]
    TRY.
        " iv_thing_name example value: 'MyIoTThing'
        lo_iot->deletething( iv_thingname = iv_thing_name ).
        MESSAGE |IoT thing deleted: { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_not_found).
        MESSAGE |Thing not found: { lo_not_found->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc /aws1/cx_iotserverexc INTO DATA(lo_exception).
        MESSAGE lo_exception->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_thing]
  ENDMETHOD.


  METHOD delete_topic_rule.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.delete_topic_rule]
    TRY.
        " iv_rule_name example value: 'MyTopicRule'
        lo_iot->deletetopicrule( iv_rulename = iv_rule_name ).
        MESSAGE |Topic rule deleted: { iv_rule_name }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc /aws1/cx_iotserverexc INTO DATA(lo_exception).
        MESSAGE lo_exception->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_topic_rule]
  ENDMETHOD.

ENDCLASS.
