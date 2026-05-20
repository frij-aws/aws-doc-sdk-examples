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
        VALUE(oo_result) TYPE REF TO /aws1/cl_iotcreatethingrsp.

    METHODS list_things
      RETURNING
        VALUE(ot_things)
          TYPE /aws1/cl_iotthingattribute=>tt_thingattributelist.

    METHODS create_keys_and_certificate
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_iotcrekeysandcertrsp.

    METHODS attach_thing_principal
      IMPORTING
        iv_thing_name TYPE /aws1/iotthingname
        iv_principal  TYPE /aws1/iotprincipal.

    METHODS describe_endpoint
      IMPORTING
        iv_endpoint_type TYPE /aws1/iotendpointtype
                         DEFAULT 'iot:Data-ATS'
      RETURNING
        VALUE(ov_endpoint_address) TYPE /aws1/iotendpointaddress.

    METHODS list_certificates
      RETURNING
        VALUE(ot_certificates)
          TYPE /aws1/cl_iotcertificate=>tt_certificates.

    METHODS detach_thing_principal
      IMPORTING
        iv_thing_name TYPE /aws1/iotthingname
        iv_principal  TYPE /aws1/iotprincipal.

    METHODS delete_certificate
      IMPORTING
        iv_certificate_id TYPE /aws1/iotcertificateid.

    METHODS create_topic_rule
      IMPORTING
        iv_rule_name      TYPE /aws1/iotrulename
        iv_topic          TYPE /aws1/iottopic
        iv_sns_action_arn TYPE /aws1/iotarn
        iv_role_arn       TYPE /aws1/iotarn.

    METHODS list_topic_rules
      RETURNING
        VALUE(ot_rules)
          TYPE /aws1/cl_iottopicrulelistitem=>tt_topicrulelist.

    METHODS search_index
      IMPORTING
        iv_query_string TYPE /aws1/iotquerystring
      RETURNING
        VALUE(ot_things)
          TYPE /aws1/cl_iotthingdocument=>tt_thingdocumentlist.

    METHODS update_indexing_configuration.

    METHODS delete_thing
      IMPORTING
        iv_thing_name TYPE /aws1/iotthingname.

    METHODS delete_topic_rule
      IMPORTING
        iv_rule_name TYPE /aws1/iotrulename.

    METHODS update_thing_shadow
      IMPORTING
        iv_thing_name   TYPE /aws1/iopthingname
        iv_shadow_state TYPE string.

    METHODS get_thing_shadow
      IMPORTING
        iv_thing_name    TYPE /aws1/iopthingname
      RETURNING
        VALUE(ov_shadow) TYPE string.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.


CLASS /awsex/cl_iot_actions IMPLEMENTATION.


  METHOD create_thing.
    " snippet-start:[iot.abapv1.create_thing]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).
    TRY.
        " iv_thing_name example: 'MyIoTThing'
        oo_result = lo_iot->creatething(
          iv_thingname = iv_thing_name ).
        MESSAGE |IoT thing created: { oo_result->get_thingname( ) } ARN: { oo_result->get_thingarn( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex.
        MESSAGE |Thing { iv_thing_name } already exists.| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.create_thing]
  ENDMETHOD.


  METHOD list_things.
    " snippet-start:[iot.abapv1.list_things]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).
    TRY.
        DATA lv_next_token TYPE /aws1/iotnexttoken.
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
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.list_things]
  ENDMETHOD.


  METHOD create_keys_and_certificate.
    " snippet-start:[iot.abapv1.create_keys_and_certificate]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).
    TRY.
        oo_result = lo_iot->createkeysandcertificate(
          iv_setasactive = abap_true ).
        MESSAGE |Certificate created: { oo_result->get_certificateid( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.create_keys_and_certificate]
  ENDMETHOD.


  METHOD attach_thing_principal.
    " snippet-start:[iot.abapv1.attach_thing_principal]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).
    TRY.
        " iv_thing_name example: 'MyIoTThing'
        " iv_principal  example: 'arn:aws:iot:us-east-1:123456789012:cert/abc123'
        lo_iot->attachthingprincipal(
          iv_thingname = iv_thing_name
          iv_principal = iv_principal ).
        MESSAGE |Attached principal { iv_principal } to thing { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE |Resource not found. Cannot attach principal.| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.attach_thing_principal]
  ENDMETHOD.


  METHOD describe_endpoint.
    " snippet-start:[iot.abapv1.describe_endpoint]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).
    TRY.
        " iv_endpoint_type example: 'iot:Data-ATS'
        DATA(lo_result) = lo_iot->describeendpoint(
          iv_endpointtype = iv_endpoint_type ).
        ov_endpoint_address = lo_result->get_endpointaddress( ).
        MESSAGE |Endpoint address: { ov_endpoint_address }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.describe_endpoint]
  ENDMETHOD.


  METHOD list_certificates.
    " snippet-start:[iot.abapv1.list_certificates]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).
    TRY.
        DATA lv_marker TYPE /aws1/iotmarker.
        DO.
          DATA(lo_result) = lo_iot->listcertificates(
            iv_marker = lv_marker ).
          APPEND LINES OF lo_result->get_certificates( ) TO ot_certificates.
          lv_marker = lo_result->get_nextmarker( ).
          IF lv_marker IS INITIAL.
            EXIT.
          ENDIF.
        ENDDO.
        MESSAGE |Retrieved { lines( ot_certificates ) } certificates| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.list_certificates]
  ENDMETHOD.


  METHOD detach_thing_principal.
    " snippet-start:[iot.abapv1.detach_thing_principal]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).
    TRY.
        " iv_thing_name example: 'MyIoTThing'
        " iv_principal  example: 'arn:aws:iot:us-east-1:123456789012:cert/abc123'
        lo_iot->detachthingprincipal(
          iv_thingname = iv_thing_name
          iv_principal = iv_principal ).
        MESSAGE |Detached principal { iv_principal } from thing { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE |Resource not found. Cannot detach principal.| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.detach_thing_principal]
  ENDMETHOD.


  METHOD delete_certificate.
    " snippet-start:[iot.abapv1.delete_certificate]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).
    TRY.
        " iv_certificate_id example: 'abc123def456...'
        " First deactivate the certificate before deleting it.
        lo_iot->updatecertificate(
          iv_certificateid = iv_certificate_id
          iv_newstatus     = 'INACTIVE' ).
        lo_iot->deletecertificate(
          iv_certificateid = iv_certificate_id ).
        MESSAGE |Certificate deleted: { iv_certificate_id }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE |Cannot delete certificate. Resource not found.| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_certificate]
  ENDMETHOD.


  METHOD create_topic_rule.
    " snippet-start:[iot.abapv1.create_topic_rule]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).
    TRY.
        " iv_rule_name      example: 'MyTopicRule'
        " iv_topic          example: 'my/iot/topic'
        " iv_sns_action_arn example: 'arn:aws:sns:us-east-1:123456789012:MyTopic'
        " iv_role_arn       example: 'arn:aws:iam::123456789012:role/MyIoTRole'
        DATA(lv_sql) = |SELECT * FROM '{ iv_topic }'|.

        DATA lt_actions TYPE /aws1/cl_iotaction=>tt_actionlist.
        APPEND NEW /aws1/cl_iotaction(
          io_sns = NEW /aws1/cl_iotsnsaction(
            iv_targetarn    = iv_sns_action_arn
            iv_rolearn      = iv_role_arn
            iv_messageformat = 'RAW' )
        ) TO lt_actions.

        lo_iot->createtopicrule(
          iv_rulename         = iv_rule_name
          io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
            iv_sql     = lv_sql
            it_actions = lt_actions ) ).
        MESSAGE |Topic rule created: { iv_rule_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex.
        MESSAGE |Topic rule { iv_rule_name } already exists.| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.create_topic_rule]
  ENDMETHOD.


  METHOD list_topic_rules.
    " snippet-start:[iot.abapv1.list_topic_rules]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).
    TRY.
        DATA lv_next_token TYPE /aws1/iotnexttoken.
        DO.
          DATA(lo_result) = lo_iot->listtopicrules(
            iv_nexttoken = lv_next_token ).
          APPEND LINES OF lo_result->get_rules( ) TO ot_rules.
          lv_next_token = lo_result->get_nexttoken( ).
          IF lv_next_token IS INITIAL.
            EXIT.
          ENDIF.
        ENDDO.
        MESSAGE |Retrieved { lines( ot_rules ) } topic rules| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.list_topic_rules]
  ENDMETHOD.


  METHOD search_index.
    " snippet-start:[iot.abapv1.search_index]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).
    TRY.
        " iv_query_string example: 'thingName:MyThing*'
        DATA(lo_result) = lo_iot->searchindex(
          iv_querystring = iv_query_string ).
        ot_things = lo_result->get_things( ).
        MESSAGE |Found { lines( ot_things ) } IoT things matching query| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.search_index]
  ENDMETHOD.


  METHOD update_indexing_configuration.
    " snippet-start:[iot.abapv1.update_indexing_configuration]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).
    TRY.
        lo_iot->updateindexingconfiguration(
          io_thingindexingconf = NEW /aws1/cl_iotthingindexingconf(
            " 'REGISTRY' enables indexing of thing registry data.
            iv_thingindexingmode = 'REGISTRY' ) ).
        MESSAGE |Indexing configuration updated to REGISTRY mode| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.update_indexing_configuration]
  ENDMETHOD.


  METHOD delete_thing.
    " snippet-start:[iot.abapv1.delete_thing]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).
    TRY.
        " iv_thing_name example: 'MyIoTThing'
        lo_iot->deletething(
          iv_thingname = iv_thing_name ).
        MESSAGE |IoT thing deleted: { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE |Cannot delete thing. Resource not found.| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_thing]
  ENDMETHOD.


  METHOD delete_topic_rule.
    " snippet-start:[iot.abapv1.delete_topic_rule]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).
    TRY.
        " iv_rule_name example: 'MyTopicRule'
        lo_iot->deletetopicrule(
          iv_rulename = iv_rule_name ).
        MESSAGE |Topic rule deleted: { iv_rule_name }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_topic_rule]
  ENDMETHOD.


  METHOD update_thing_shadow.
    " snippet-start:[iot.abapv1.update_thing_shadow]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iop) = /aws1/cl_iop_factory=>create( lo_session ).
    TRY.
        " iv_thing_name   example: 'MyIoTThing'
        " iv_shadow_state example: '{"state":{"reported":{"temperature":25}}}'
        DATA(lv_payload) = cl_abap_codepage=>convert_to(
          source   = iv_shadow_state
          codepage = 'UTF-8' ).
        lo_iop->updatethingshadow(
          iv_thingname = iv_thing_name
          iv_payload   = lv_payload ).
        MESSAGE |Shadow updated for thing: { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iopresourcenotfoundex.
        MESSAGE |Cannot update thing shadow. Resource not found.| TYPE 'I'.
      CATCH /aws1/cx_iopclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.update_thing_shadow]
  ENDMETHOD.


  METHOD get_thing_shadow.
    " snippet-start:[iot.abapv1.get_thing_shadow]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iop) = /aws1/cl_iop_factory=>create( lo_session ).
    TRY.
        " iv_thing_name example: 'MyIoTThing'
        DATA(lo_result) = lo_iop->getthingshadow(
          iv_thingname = iv_thing_name ).
        ov_shadow = cl_abap_codepage=>convert_from(
          source   = lo_result->get_payload( )
          codepage = 'UTF-8' ).
        MESSAGE |Shadow for { iv_thing_name }: { ov_shadow }| TYPE 'I'.
      CATCH /aws1/cx_iopresourcenotfoundex.
        MESSAGE |Cannot get thing shadow. Resource not found.| TYPE 'I'.
      CATCH /aws1/cx_iopclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.get_thing_shadow]
  ENDMETHOD.

ENDCLASS.
