" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS /awsex/cl_iot_actions DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    " Creates an AWS IoT thing.
    " @parameter iv_thing_name | The name of the thing to create (e.g., 'MyIoTThing')
    " @parameter oo_result | The response containing the thing name, ARN, and ID
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS create_thing
      IMPORTING
        !iv_thing_name  TYPE /aws1/iotthingname
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_iotcreatethingrsp
      RAISING
        /aws1/cx_rt_generic.

    " Lists AWS IoT things.
    " @parameter ot_things | The list of things
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS list_things
      RETURNING
        VALUE(ot_things) TYPE /aws1/cl_iotthingattribute=>tt_thingattributelist
      RAISING
        /aws1/cx_rt_generic.

    " Creates keys and a certificate for an AWS IoT thing.
    " @parameter oo_result | The response containing certificate ID, ARN, PEM, and key pair
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS create_keys_and_certificate
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_iotcrekeysandcertrsp
      RAISING
        /aws1/cx_rt_generic.

    " Attaches a certificate to an AWS IoT thing.
    " @parameter iv_thing_name | The name of the thing (e.g., 'MyIoTThing')
    " @parameter iv_principal | The ARN of the certificate
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS attach_thing_principal
      IMPORTING
        !iv_thing_name TYPE /aws1/iotthingname
        !iv_principal  TYPE /aws1/iotprincipal
      RAISING
        /aws1/cx_rt_generic.

    " Gets the AWS IoT endpoint address.
    " @parameter iv_endpoint_type | The endpoint type (e.g., 'iot:Data-ATS')
    " @parameter ov_endpoint_address | The endpoint address
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS describe_endpoint
      IMPORTING
        !iv_endpoint_type    TYPE /aws1/iotendpointtype
                             DEFAULT 'iot:Data-ATS'
      RETURNING
        VALUE(ov_endpoint_address) TYPE /aws1/iotendpointaddress
      RAISING
        /aws1/cx_rt_generic.

    " Lists AWS IoT certificates.
    " @parameter ot_certificates | The list of certificates
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS list_certificates
      RETURNING
        VALUE(ot_certificates) TYPE /aws1/cl_iotcertificate=>tt_certificates
      RAISING
        /aws1/cx_rt_generic.

    " Detaches a certificate from an AWS IoT thing.
    " @parameter iv_thing_name | The name of the thing (e.g., 'MyIoTThing')
    " @parameter iv_principal | The ARN of the certificate
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS detach_thing_principal
      IMPORTING
        !iv_thing_name TYPE /aws1/iotthingname
        !iv_principal  TYPE /aws1/iotprincipal
      RAISING
        /aws1/cx_rt_generic.

    " Deactivates and deletes an AWS IoT certificate.
    " @parameter iv_certificate_id | The ID of the certificate to delete
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS delete_certificate
      IMPORTING
        !iv_certificate_id TYPE /aws1/iotcertificateid
      RAISING
        /aws1/cx_rt_generic.

    " Creates an AWS IoT topic rule with an SNS action.
    " @parameter iv_rule_name | The name of the rule (e.g., 'MyTopicRule')
    " @parameter iv_topic | The MQTT topic to subscribe to (e.g., 'iot/sensors')
    " @parameter iv_sns_action_arn | The ARN of the SNS topic
    " @parameter iv_role_arn | The ARN of the IAM role
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS create_topic_rule
      IMPORTING
        !iv_rule_name      TYPE /aws1/iotrulename
        !iv_topic          TYPE /aws1/iotstring
        !iv_sns_action_arn TYPE /aws1/iotawsarn
        !iv_role_arn       TYPE /aws1/iotawsarn
      RAISING
        /aws1/cx_rt_generic.

    " Lists AWS IoT topic rules.
    " @parameter ot_rules | The list of topic rules
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS list_topic_rules
      RETURNING
        VALUE(ot_rules) TYPE /aws1/cl_iottopicrulelistitem=>tt_topicrulelist
      RAISING
        /aws1/cx_rt_generic.

    " Searches the AWS IoT fleet index.
    " @parameter iv_query | The search query string (e.g., 'thingName:My*')
    " @parameter ot_things | The list of matching things
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS search_index
      IMPORTING
        !iv_query   TYPE /aws1/iotquerystring
      RETURNING
        VALUE(ot_things) TYPE /aws1/cl_iotthingdocument=>tt_thingdocumentlist
      RAISING
        /aws1/cx_rt_generic.

    " Updates the AWS IoT indexing configuration to enable REGISTRY indexing.
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS update_indexing_configuration
      RAISING
        /aws1/cx_rt_generic.

    " Deletes an AWS IoT thing.
    " @parameter iv_thing_name | The name of the thing to delete (e.g., 'MyIoTThing')
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS delete_thing
      IMPORTING
        !iv_thing_name TYPE /aws1/iotthingname
      RAISING
        /aws1/cx_rt_generic.

    " Deletes an AWS IoT topic rule.
    " @parameter iv_rule_name | The name of the rule to delete (e.g., 'MyTopicRule')
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
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
        oo_result = lo_iot->creatething(
          iv_thingname = iv_thing_name ).
        MESSAGE |IoT thing created: { oo_result->get_thingname( ) } ARN: { oo_result->get_thingarn( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex INTO DATA(lo_exists).
        MESSAGE |Thing { iv_thing_name } already exists: { lo_exists->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_client_ex).
        MESSAGE |IoT client error creating thing: { lo_client_ex->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_server_ex).
        MESSAGE |IoT server error creating thing: { lo_server_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.create_thing]
  ENDMETHOD.


  METHOD list_things.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.list_things]
    TRY.
        DATA(lv_next_token) = CONV /aws1/iotnexttoken( '' ).
        DO.
          DATA(lo_result) = lo_iot->listthings(
            iv_nexttoken = lv_next_token ).
          APPEND LINES OF lo_result->get_things( ) TO ot_things.
          lv_next_token = lo_result->get_nexttoken( ).
          IF lv_next_token IS INITIAL.
            EXIT.
          ENDIF.
        ENDDO.
        MESSAGE |Retrieved { lines( ot_things ) } IoT things| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_client_ex).
        MESSAGE |IoT client error listing things: { lo_client_ex->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_server_ex).
        MESSAGE |IoT server error listing things: { lo_server_ex->get_text( ) }| TYPE 'I'.
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
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_client_ex).
        MESSAGE |IoT client error creating certificate: { lo_client_ex->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_server_ex).
        MESSAGE |IoT server error creating certificate: { lo_server_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.create_keys_and_certificate]
  ENDMETHOD.


  METHOD attach_thing_principal.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.attach_thing_principal]
    TRY.
        lo_iot->attachthingprincipal(
          iv_thingname = iv_thing_name
          iv_principal = iv_principal ).
        MESSAGE |Principal { iv_principal } attached to thing { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_not_found).
        MESSAGE |Resource not found attaching principal: { lo_not_found->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_client_ex).
        MESSAGE |IoT client error attaching principal: { lo_client_ex->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_server_ex).
        MESSAGE |IoT server error attaching principal: { lo_server_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.attach_thing_principal]
  ENDMETHOD.


  METHOD describe_endpoint.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.describe_endpoint]
    TRY.
        DATA(lo_result) = lo_iot->describeendpoint(
          iv_endpointtype = iv_endpoint_type ).
        ov_endpoint_address = lo_result->get_endpointaddress( ).
        MESSAGE |Endpoint address: { ov_endpoint_address }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_client_ex).
        MESSAGE |IoT client error describing endpoint: { lo_client_ex->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_server_ex).
        MESSAGE |IoT server error describing endpoint: { lo_server_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.describe_endpoint]
  ENDMETHOD.


  METHOD list_certificates.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.list_certificates]
    TRY.
        DATA(lv_marker) = CONV /aws1/iotmarker( '' ).
        DO.
          DATA(lo_result) = lo_iot->listcertificates(
            iv_marker = lv_marker ).
          APPEND LINES OF lo_result->get_certificates( ) TO ot_certificates.
          lv_marker = lo_result->get_nextmarker( ).
          IF lv_marker IS INITIAL.
            EXIT.
          ENDIF.
        ENDDO.
        MESSAGE |Retrieved { lines( ot_certificates ) } IoT certificates| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_client_ex).
        MESSAGE |IoT client error listing certificates: { lo_client_ex->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_server_ex).
        MESSAGE |IoT server error listing certificates: { lo_server_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.list_certificates]
  ENDMETHOD.


  METHOD detach_thing_principal.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.detach_thing_principal]
    TRY.
        lo_iot->detachthingprincipal(
          iv_thingname = iv_thing_name
          iv_principal = iv_principal ).
        MESSAGE |Principal { iv_principal } detached from thing { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_not_found).
        MESSAGE |Resource not found detaching principal: { lo_not_found->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_client_ex).
        MESSAGE |IoT client error detaching principal: { lo_client_ex->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_server_ex).
        MESSAGE |IoT server error detaching principal: { lo_server_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.detach_thing_principal]
  ENDMETHOD.


  METHOD delete_certificate.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.delete_certificate]
    TRY.
        " First deactivate the certificate before deleting it
        lo_iot->updatecertificate(
          iv_certificateid = iv_certificate_id
          iv_newstatus     = 'INACTIVE' ).
        lo_iot->deletecertificate(
          iv_certificateid = iv_certificate_id ).
        MESSAGE |Certificate deleted: { iv_certificate_id }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_not_found).
        MESSAGE |Certificate not found for deletion: { lo_not_found->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_client_ex).
        MESSAGE |IoT client error deleting certificate: { lo_client_ex->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_server_ex).
        MESSAGE |IoT server error deleting certificate: { lo_server_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_certificate]
  ENDMETHOD.


  METHOD create_topic_rule.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.create_topic_rule]
    TRY.
        " Build the SNS action for the topic rule
        DATA(lo_sns_action) = NEW /aws1/cl_iotsnsaction(
          iv_targetarn = iv_sns_action_arn
          iv_rolearn   = iv_role_arn ).

        DATA(lo_action) = NEW /aws1/cl_iotaction(
          io_sns = lo_sns_action ).

        DATA lt_actions TYPE /aws1/cl_iotaction=>tt_actionlist.
        APPEND lo_action TO lt_actions.

        " The SQL statement selects all fields from the given MQTT topic
        " e.g., iv_topic = 'iot/sensors'
        DATA(lo_payload) = NEW /aws1/cl_iottopicrulepayload(
          iv_sql     = |SELECT * FROM '{ iv_topic }'|
          it_actions = lt_actions ).

        lo_iot->createtopicrule(
          iv_rulename        = iv_rule_name
          io_topicrulepayload = lo_payload ).
        MESSAGE |Topic rule created: { iv_rule_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex INTO DATA(lo_exists).
        MESSAGE |Topic rule { iv_rule_name } already exists: { lo_exists->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_client_ex).
        MESSAGE |IoT client error creating topic rule: { lo_client_ex->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_server_ex).
        MESSAGE |IoT server error creating topic rule: { lo_server_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.create_topic_rule]
  ENDMETHOD.


  METHOD list_topic_rules.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.list_topic_rules]
    TRY.
        DATA(lv_next_token) = CONV /aws1/iotnexttoken( '' ).
        DO.
          DATA(lo_result) = lo_iot->listtopicrules(
            iv_nexttoken = lv_next_token ).
          APPEND LINES OF lo_result->get_rules( ) TO ot_rules.
          lv_next_token = lo_result->get_nexttoken( ).
          IF lv_next_token IS INITIAL.
            EXIT.
          ENDIF.
        ENDDO.
        MESSAGE |Retrieved { lines( ot_rules ) } IoT topic rules| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_client_ex).
        MESSAGE |IoT client error listing topic rules: { lo_client_ex->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_server_ex).
        MESSAGE |IoT server error listing topic rules: { lo_server_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.list_topic_rules]
  ENDMETHOD.


  METHOD search_index.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.search_index]
    TRY.
        DATA(lo_result) = lo_iot->searchindex(
          iv_querystring = iv_query ).
        ot_things = lo_result->get_things( ).
        MESSAGE |Found { lines( ot_things ) } IoT things matching query: { iv_query }| TYPE 'I'.
      CATCH /aws1/cx_iotindexnotreadyex INTO DATA(lo_not_ready).
        MESSAGE |Index not ready: { lo_not_ready->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_client_ex).
        MESSAGE |IoT client error searching index: { lo_client_ex->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_server_ex).
        MESSAGE |IoT server error searching index: { lo_server_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.search_index]
  ENDMETHOD.


  METHOD update_indexing_configuration.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.update_indexing_configuration]
    TRY.
        " Enable REGISTRY indexing mode so things are searchable
        DATA(lo_thing_idx_conf) = NEW /aws1/cl_iotthingindexingconf(
          iv_thingindexingmode = 'REGISTRY' ).

        lo_iot->updateindexingconfiguration(
          io_thingindexingconf = lo_thing_idx_conf ).
        MESSAGE 'IoT indexing configuration updated to REGISTRY mode' TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_client_ex).
        MESSAGE |IoT client error updating indexing config: { lo_client_ex->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_server_ex).
        MESSAGE |IoT server error updating indexing config: { lo_server_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.update_indexing_configuration]
  ENDMETHOD.


  METHOD delete_thing.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.delete_thing]
    TRY.
        lo_iot->deletething( iv_thingname = iv_thing_name ).
        MESSAGE |IoT thing deleted: { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_not_found).
        MESSAGE |Thing not found for deletion: { lo_not_found->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_client_ex).
        MESSAGE |IoT client error deleting thing: { lo_client_ex->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_server_ex).
        MESSAGE |IoT server error deleting thing: { lo_server_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_thing]
  ENDMETHOD.


  METHOD delete_topic_rule.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.delete_topic_rule]
    TRY.
        lo_iot->deletetopicrule( iv_rulename = iv_rule_name ).
        MESSAGE |IoT topic rule deleted: { iv_rule_name }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_client_ex).
        MESSAGE |IoT client error deleting topic rule: { lo_client_ex->get_text( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_server_ex).
        MESSAGE |IoT server error deleting topic rule: { lo_server_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_topic_rule]
  ENDMETHOD.

ENDCLASS.
