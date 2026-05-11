" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS /awsex/cl_iot_actions DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC.

  PUBLIC SECTION.
    METHODS create_thing
      IMPORTING
        iv_thing_name TYPE /aws1/iotthingname
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_iotcreatethingrsp
      RAISING
        /aws1/cx_iotclientexc
        /aws1/cx_iotserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

    METHODS list_things
      RETURNING
        VALUE(ot_things) TYPE /aws1/cl_iotthingattribute=>tt_thingattributelist
      RAISING
        /aws1/cx_iotclientexc
        /aws1/cx_iotserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

    METHODS create_keys_and_certificate
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_iotcrekeysandcertrsp
      RAISING
        /aws1/cx_iotclientexc
        /aws1/cx_iotserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

    METHODS attach_thing_principal
      IMPORTING
        iv_thing_name TYPE /aws1/iotthingname
        iv_principal  TYPE /aws1/iotprincipal
      RAISING
        /aws1/cx_iotclientexc
        /aws1/cx_iotserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

    METHODS describe_endpoint
      IMPORTING
        iv_endpoint_type TYPE /aws1/iotendpointtype
                              DEFAULT 'iot:Data-ATS'
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_iotdescrendptresponse
      RAISING
        /aws1/cx_iotclientexc
        /aws1/cx_iotserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

    METHODS list_certificates
      RETURNING
        VALUE(ot_certs) TYPE /aws1/cl_iotcertificate=>tt_certificates
      RAISING
        /aws1/cx_iotclientexc
        /aws1/cx_iotserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

    METHODS detach_thing_principal
      IMPORTING
        iv_thing_name TYPE /aws1/iotthingname
        iv_principal  TYPE /aws1/iotprincipal
      RAISING
        /aws1/cx_iotclientexc
        /aws1/cx_iotserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

    METHODS delete_certificate
      IMPORTING
        iv_certificate_id TYPE /aws1/iotcertificateid
      RAISING
        /aws1/cx_iotclientexc
        /aws1/cx_iotserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

    METHODS create_topic_rule
      IMPORTING
        iv_rule_name      TYPE /aws1/iotrulename
        iv_topic          TYPE /aws1/iottopic
        iv_sns_action_arn TYPE /aws1/iotawsarn
        iv_role_arn       TYPE /aws1/iotrolearn
      RAISING
        /aws1/cx_iotclientexc
        /aws1/cx_iotserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

    METHODS list_topic_rules
      RETURNING
        VALUE(ot_rules) TYPE /aws1/cl_iottopicrulelistitem=>tt_topicrulelist
      RAISING
        /aws1/cx_iotclientexc
        /aws1/cx_iotserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

    METHODS search_index
      IMPORTING
        iv_query_string TYPE /aws1/iotquerystring
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_iotsearchindexrsp
      RAISING
        /aws1/cx_iotclientexc
        /aws1/cx_iotserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

    METHODS update_indexing_configuration
      RAISING
        /aws1/cx_iotclientexc
        /aws1/cx_iotserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

    METHODS delete_thing
      IMPORTING
        iv_thing_name TYPE /aws1/iotthingname
      RAISING
        /aws1/cx_iotclientexc
        /aws1/cx_iotserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

    METHODS delete_topic_rule
      IMPORTING
        iv_rule_name TYPE /aws1/iotrulename
      RAISING
        /aws1/cx_iotclientexc
        /aws1/cx_iotserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

    METHODS update_thing_shadow
      IMPORTING
        iv_thing_name   TYPE /aws1/iopthingname
        iv_shadow_state TYPE /aws1/iopjsondocument
      RAISING
        /aws1/cx_iopclientexc
        /aws1/cx_iopserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

    METHODS get_thing_shadow
      IMPORTING
        iv_thing_name        TYPE /aws1/iopthingname
      RETURNING
        VALUE(ov_shadow_json) TYPE /aws1/iopjsondocument
      RAISING
        /aws1/cx_iopclientexc
        /aws1/cx_iopserverexc
        /aws1/cx_rt_service_generic
        /aws1/cx_rt_technical_generic.

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
          " For example, iv_thing_name = 'my-iot-thing'
          iv_thingname = iv_thing_name
        ).
        MESSAGE |IoT thing created: { iv_thing_name } ARN: { oo_result->get_thingarn( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex.
        MESSAGE |IoT thing { iv_thing_name } already exists.| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.create_thing]
  ENDMETHOD.


  METHOD list_things.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.list_things]
    TRY.
        DATA lv_next_token TYPE /aws1/iotnexttoken.

        " Paginate through all things
        DO.
          DATA(lo_page) = lo_iot->listthings(
            iv_nexttoken = lv_next_token
          ).
          APPEND LINES OF lo_page->get_things( ) TO ot_things.
          lv_next_token = lo_page->get_nexttoken( ).
          IF lv_next_token IS INITIAL.
            EXIT.
          ENDIF.
        ENDDO.

        MESSAGE |Retrieved { lines( ot_things ) } IoT things| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.list_things]
  ENDMETHOD.


  METHOD create_keys_and_certificate.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.create_keys_and_certificate]
    TRY.
        oo_result = lo_iot->createkeysandcertificate(
          iv_setasactive = abap_true
        ).
        MESSAGE |Certificate created: { oo_result->get_certificateid( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
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
          " For example, iv_thing_name = 'my-iot-thing'
          iv_thingname = iv_thing_name
          " For example, iv_principal = 'arn:aws:iot:us-east-1:123456789012:cert/abc123...'
          iv_principal  = iv_principal
        ).
        MESSAGE |Principal { iv_principal } attached to thing { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_notfound).
        MESSAGE |Resource not found: { lo_notfound->get_text( ) }| TYPE 'E'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.attach_thing_principal]
  ENDMETHOD.


  METHOD describe_endpoint.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.describe_endpoint]
    TRY.
        oo_result = lo_iot->describeendpoint(
          " For example, iv_endpoint_type = 'iot:Data-ATS'
          iv_endpointtype = iv_endpoint_type
        ).
        DATA(lv_endpoint_address) = oo_result->get_endpointaddress( ).
        MESSAGE |Endpoint address: { lv_endpoint_address }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
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

        " Paginate through all certificates
        DO.
          DATA(lo_page) = lo_iot->listcertificates(
            iv_marker = lv_marker
          ).
          APPEND LINES OF lo_page->get_certificates( ) TO ot_certs.
          lv_marker = lo_page->get_nextmarker( ).
          IF lv_marker IS INITIAL.
            EXIT.
          ENDIF.
        ENDDO.

        MESSAGE |Retrieved { lines( ot_certs ) } IoT certificates| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
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
          " For example, iv_thing_name = 'my-iot-thing'
          iv_thingname = iv_thing_name
          " For example, iv_principal = 'arn:aws:iot:us-east-1:123456789012:cert/abc123...'
          iv_principal  = iv_principal
        ).
        MESSAGE |Principal { iv_principal } detached from thing { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_notfound).
        MESSAGE |Resource not found: { lo_notfound->get_text( ) }| TYPE 'E'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.detach_thing_principal]
  ENDMETHOD.


  METHOD delete_certificate.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.delete_certificate]
    TRY.
        " First deactivate the certificate before deleting
        lo_iot->updatecertificate(
          " For example, iv_certificate_id = 'abc12345def67890...'
          iv_certificateid = iv_certificate_id
          iv_newstatus     = 'INACTIVE'
        ).
        lo_iot->deletecertificate(
          iv_certificateid = iv_certificate_id
        ).
        MESSAGE |Certificate deleted: { iv_certificate_id }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_notfound).
        MESSAGE |Certificate not found: { lo_notfound->get_text( ) }| TYPE 'E'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_certificate]
  ENDMETHOD.


  METHOD create_topic_rule.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.create_topic_rule]
    TRY.
        " Build the SNS action
        DATA(lo_sns_action) = NEW /aws1/cl_iotsnsaction(
          " For example, iv_targetarn = 'arn:aws:sns:us-east-1:123456789012:MyTopic'
          iv_targetarn = iv_sns_action_arn
          " For example, iv_rolearn = 'arn:aws:iam::123456789012:role/MyIoTRole'
          iv_rolearn   = iv_role_arn
        ).

        DATA(lo_action) = NEW /aws1/cl_iotaction(
          io_sns = lo_sns_action
        ).

        DATA lt_actions TYPE /aws1/cl_iotaction=>tt_actionlist.
        APPEND lo_action TO lt_actions.

        DATA(lo_payload) = NEW /aws1/cl_iottopicrulepayload(
          " SQL selects all messages from the given MQTT topic
          " For example, iv_topic = 'my/iot/topic'
          iv_sql     = |SELECT * FROM '{ iv_topic }'|
          it_actions = lt_actions
        ).

        lo_iot->createtopicrule(
          " For example, iv_rule_name = 'MyTopicRule'
          iv_rulename        = iv_rule_name
          io_topicrulepayload = lo_payload
        ).
        MESSAGE |Topic rule created: { iv_rule_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex.
        MESSAGE |Topic rule { iv_rule_name } already exists.| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
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

        " Paginate through all topic rules
        DO.
          DATA(lo_page) = lo_iot->listtopicrules(
            iv_nexttoken = lv_next_token
          ).
          APPEND LINES OF lo_page->get_rules( ) TO ot_rules.
          lv_next_token = lo_page->get_nexttoken( ).
          IF lv_next_token IS INITIAL.
            EXIT.
          ENDIF.
        ENDDO.

        MESSAGE |Retrieved { lines( ot_rules ) } IoT topic rules| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.list_topic_rules]
  ENDMETHOD.


  METHOD search_index.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.search_index]
    TRY.
        oo_result = lo_iot->searchindex(
          " For example, iv_query_string = 'thingName:my-thing*'
          iv_querystring = iv_query_string
        ).
        DATA(lt_things) = oo_result->get_things( ).
        MESSAGE |Found { lines( lt_things ) } IoT things matching the query| TYPE 'I'.
      CATCH /aws1/cx_iotindexnotreadyex INTO DATA(lo_not_ready).
        MESSAGE |IoT index not ready: { lo_not_ready->get_text( ) }| TYPE 'E'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.search_index]
  ENDMETHOD.


  METHOD update_indexing_configuration.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.update_indexing_configuration]
    TRY.
        DATA(lo_idx_conf) = NEW /aws1/cl_iotthingindexingconf(
          " Enable REGISTRY indexing mode so things can be searched
          iv_thingindexingmode = 'REGISTRY'
        ).

        lo_iot->updateindexingconfiguration(
          io_thingindexingconf = lo_idx_conf
        ).
        MESSAGE |IoT indexing configuration updated to REGISTRY mode| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.update_indexing_configuration]
  ENDMETHOD.


  METHOD delete_thing.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.delete_thing]
    TRY.
        lo_iot->deletething(
          " For example, iv_thing_name = 'my-iot-thing'
          iv_thingname = iv_thing_name
        ).
        MESSAGE |IoT thing deleted: { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_notfound).
        MESSAGE |Thing not found: { lo_notfound->get_text( ) }| TYPE 'E'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_thing]
  ENDMETHOD.


  METHOD delete_topic_rule.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.delete_topic_rule]
    TRY.
        lo_iot->deletetopicrule(
          " For example, iv_rule_name = 'MyTopicRule'
          iv_rulename = iv_rule_name
        ).
        MESSAGE |Topic rule deleted: { iv_rule_name }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_topic_rule]
  ENDMETHOD.


  METHOD update_thing_shadow.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iop) = /aws1/cl_iop_factory=>create( lo_session ).

    " snippet-start:[iop.abapv1.update_thing_shadow]
    TRY.
        lo_iop->updatethingshadow(
          " For example, iv_thing_name = 'my-iot-thing'
          iv_thingname = iv_thing_name
          " For example: '{"state":{"desired":{"color":"red"}}}'
          iv_payload   = iv_shadow_state
        ).
        MESSAGE |Shadow updated for IoT thing: { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iopresourcenotfoundex INTO DATA(lo_notfound).
        MESSAGE |Thing not found: { lo_notfound->get_text( ) }| TYPE 'E'.
      CATCH /aws1/cx_iopclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iop.abapv1.update_thing_shadow]
  ENDMETHOD.


  METHOD get_thing_shadow.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iop) = /aws1/cl_iop_factory=>create( lo_session ).

    " snippet-start:[iop.abapv1.get_thing_shadow]
    TRY.
        DATA(oo_result) = lo_iop->getthingshadow(
          " For example, iv_thing_name = 'my-iot-thing'
          iv_thingname = iv_thing_name
        ).
        ov_shadow_json = oo_result->get_payload( ).
        MESSAGE |Shadow state for { iv_thing_name }: { ov_shadow_json }| TYPE 'I'.
      CATCH /aws1/cx_iopresourcenotfoundex INTO DATA(lo_notfound).
        MESSAGE |Thing shadow not found: { lo_notfound->get_text( ) }| TYPE 'E'.
      CATCH /aws1/cx_iopclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iop.abapv1.get_thing_shadow]
  ENDMETHOD.

ENDCLASS.
