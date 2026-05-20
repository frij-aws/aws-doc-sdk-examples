" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS /awsex/cl_iot_actions DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    METHODS create_thing
      IMPORTING
        !iv_thing_name TYPE /aws1/iotthingname
      EXPORTING
        !oo_result     TYPE REF TO /aws1/cl_iotcreatethingrsp
      RAISING
        /aws1/cx_rt_generic.

    METHODS list_things
      EXPORTING
        !oo_result TYPE REF TO /aws1/cl_iotlistthingsresponse
      RAISING
        /aws1/cx_rt_generic.

    METHODS create_keys_and_certificate
      EXPORTING
        !oo_result TYPE REF TO /aws1/cl_iotcrekeysandcertrsp
      RAISING
        /aws1/cx_rt_generic.

    METHODS attach_thing_principal
      IMPORTING
        !iv_thing_name TYPE /aws1/iotthingname
        !iv_principal  TYPE /aws1/iotprincipal
      RAISING
        /aws1/cx_rt_generic.

    METHODS describe_endpoint
      IMPORTING
        !iv_endpoint_type TYPE /aws1/iotendpointtype
                          DEFAULT 'iot:Data-ATS'
      EXPORTING
        !ov_endpoint_addr TYPE /aws1/iotendpointaddress
      RAISING
        /aws1/cx_rt_generic.

    METHODS list_certificates
      EXPORTING
        !oo_result TYPE REF TO /aws1/cl_iotlistcertsresponse
      RAISING
        /aws1/cx_rt_generic.

    METHODS detach_thing_principal
      IMPORTING
        !iv_thing_name TYPE /aws1/iotthingname
        !iv_principal  TYPE /aws1/iotprincipal
      RAISING
        /aws1/cx_rt_generic.

    METHODS delete_certificate
      IMPORTING
        !iv_certificate_id TYPE /aws1/iotcertificateid
      RAISING
        /aws1/cx_rt_generic.

    METHODS create_topic_rule
      IMPORTING
        !iv_rule_name       TYPE /aws1/iotrulename
        !iv_topic           TYPE /aws1/iottopic
        !iv_sns_action_arn  TYPE /aws1/iotawsarn
        !iv_role_arn        TYPE /aws1/iotrolearn
      RAISING
        /aws1/cx_rt_generic.

    METHODS list_topic_rules
      EXPORTING
        !oo_result TYPE REF TO /aws1/cl_iotlisttopicrulesrsp
      RAISING
        /aws1/cx_rt_generic.

    METHODS search_index
      IMPORTING
        !iv_query_string TYPE /aws1/iotquerystring
      EXPORTING
        !oo_result       TYPE REF TO /aws1/cl_iotsearchindexrsp
      RAISING
        /aws1/cx_rt_generic.

    METHODS update_indexing_configuration
      RAISING
        /aws1/cx_rt_generic.

    METHODS delete_thing
      IMPORTING
        !iv_thing_name TYPE /aws1/iotthingname
      RAISING
        /aws1/cx_rt_generic.

    METHODS delete_topic_rule
      IMPORTING
        !iv_rule_name TYPE /aws1/iotrulename
      RAISING
        /aws1/cx_rt_generic.

    METHODS update_thing_shadow
      IMPORTING
        !iv_thing_name    TYPE /aws1/iopthingname
        !iv_shadow_state  TYPE /aws1/iopjsondocument
      RAISING
        /aws1/cx_rt_generic.

    METHODS get_thing_shadow
      IMPORTING
        !iv_thing_name  TYPE /aws1/iopthingname
      EXPORTING
        !oo_result      TYPE REF TO /aws1/cl_iopgetthingshadowrsp
      RAISING
        /aws1/cx_rt_generic.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS /AWSEX/CL_IOT_ACTIONS IMPLEMENTATION.


  METHOD create_thing.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.create_thing]
    TRY.
        " iv_thing_name = 'MyIoTThing'
        oo_result = lo_iot->creatething( iv_thingname = iv_thing_name ).
        MESSAGE |IoT thing created: { iv_thing_name } ARN: { oo_result->get_thingarn( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex.
        MESSAGE 'IoT thing already exists.' TYPE 'E'.
      CATCH /aws1/cx_iotinvalidrequestex.
        MESSAGE 'Invalid request to create IoT thing.' TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_ex).
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
        oo_result = lo_iot->listthings( ).
        MESSAGE |Retrieved { lines( oo_result->get_things( ) ) } IoT things| TYPE 'I'.
      CATCH /aws1/cx_iotthrottlingex.
        MESSAGE 'Request throttled. Please try again later.' TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_ex).
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
        oo_result = lo_iot->createkeysandcertificate( iv_setasactive = abap_true ).
        MESSAGE |Certificate created: { oo_result->get_certificateid( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotthrottlingex.
        MESSAGE 'Request throttled. Please try again later.' TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_ex).
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
        " iv_thing_name = 'MyIoTThing'
        " iv_principal  = 'arn:aws:iot:us-east-1:123456789012:cert/abc123...'
        lo_iot->attachthingprincipal(
          iv_thingname = iv_thing_name
          iv_principal = iv_principal ).
        MESSAGE |Principal attached to thing: { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE 'Cannot attach principal. Resource not found.' TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_ex).
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
        " iv_endpoint_type = 'iot:Data-ATS'
        DATA(lo_result) = lo_iot->describeendpoint(
                            iv_endpointtype = iv_endpoint_type ).
        ov_endpoint_addr = lo_result->get_endpointaddress( ).
        MESSAGE |Endpoint address: { ov_endpoint_addr }| TYPE 'I'.
      CATCH /aws1/cx_iotthrottlingex.
        MESSAGE 'Request throttled. Please try again later.' TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_ex).
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
        oo_result = lo_iot->listcertificates( ).
        MESSAGE |Retrieved { lines( oo_result->get_certificates( ) ) } certificates| TYPE 'I'.
      CATCH /aws1/cx_iotthrottlingex.
        MESSAGE 'Request throttled. Please try again later.' TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_ex).
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
        " iv_thing_name = 'MyIoTThing'
        " iv_principal  = 'arn:aws:iot:us-east-1:123456789012:cert/abc123...'
        lo_iot->detachthingprincipal(
          iv_thingname = iv_thing_name
          iv_principal = iv_principal ).
        MESSAGE |Principal detached from thing: { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE 'Cannot detach principal. Resource not found.' TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_ex).
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
        " iv_certificate_id = 'abc123...'
        lo_iot->updatecertificate(
          iv_certificateid = iv_certificate_id
          iv_newstatus     = 'INACTIVE' ).
        lo_iot->deletecertificate(
          iv_certificateid = iv_certificate_id ).
        MESSAGE |Certificate deleted: { iv_certificate_id }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE 'Cannot delete certificate. Resource not found.' TYPE 'E'.
      CATCH /aws1/cx_iotcertstateexception.
        MESSAGE 'Certificate is in an invalid state for deletion.' TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_ex).
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
        " iv_rule_name      = 'MyIoTRule'
        " iv_topic          = 'my/iot/topic'
        " iv_sns_action_arn = 'arn:aws:sns:us-east-1:123456789012:MyTopic'
        " iv_role_arn       = 'arn:aws:iam::123456789012:role/MyIoTRole'
        DATA(lo_sns_action) = NEW /aws1/cl_iotsnsaction(
          iv_targetarn = iv_sns_action_arn
          iv_rolearn   = iv_role_arn ).

        DATA(lo_action) = NEW /aws1/cl_iotaction(
          io_sns = lo_sns_action ).

        DATA lt_actions TYPE /aws1/cl_iotaction=>tt_actionlist.
        APPEND lo_action TO lt_actions.

        DATA(lo_payload) = NEW /aws1/cl_iottopicrulepayload(
          iv_sql     = |SELECT * FROM '{ iv_topic }'|
          it_actions = lt_actions ).

        lo_iot->createtopicrule(
          iv_rulename        = iv_rule_name
          io_topicrulepayload = lo_payload ).
        MESSAGE |IoT topic rule created: { iv_rule_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex.
        MESSAGE 'Topic rule already exists.' TYPE 'E'.
      CATCH /aws1/cx_iotsqlparseexception.
        MESSAGE 'Invalid SQL expression in topic rule.' TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_ex).
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
        oo_result = lo_iot->listtopicrules( ).
        MESSAGE |Retrieved { lines( oo_result->get_rules( ) ) } IoT topic rules| TYPE 'I'.
      CATCH /aws1/cx_iotthrottlingex.
        MESSAGE 'Request throttled. Please try again later.' TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_ex).
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
        " iv_query_string = 'thingName:MyDevice*'
        oo_result = lo_iot->searchindex(
          iv_querystring = iv_query_string ).
        MESSAGE |Found { lines( oo_result->get_things( ) ) } IoT things| TYPE 'I'.
      CATCH /aws1/cx_iotindexnotreadyex.
        MESSAGE 'Index is not ready. Enable indexing first.' TYPE 'E'.
      CATCH /aws1/cx_iotinvalidqueryex.
        MESSAGE 'Invalid query expression.' TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_ex).
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
        DATA(lo_thing_idx_conf) = NEW /aws1/cl_iotthingindexingconf(
          iv_thingindexingmode = 'REGISTRY' ).

        lo_iot->updateindexingconfiguration(
          io_thingindexingconf = lo_thing_idx_conf ).
        MESSAGE 'IoT indexing configuration updated to REGISTRY mode.' TYPE 'I'.
      CATCH /aws1/cx_iotinvalidrequestex.
        MESSAGE 'Invalid indexing configuration request.' TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_ex).
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
        " iv_thing_name = 'MyIoTThing'
        lo_iot->deletething( iv_thingname = iv_thing_name ).
        MESSAGE |IoT thing deleted: { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE 'Cannot delete thing. Resource not found.' TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_ex).
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
        " iv_rule_name = 'MyIoTRule'
        lo_iot->deletetopicrule( iv_rulename = iv_rule_name ).
        MESSAGE |IoT topic rule deleted: { iv_rule_name }| TYPE 'I'.
      CATCH /aws1/cx_iotcnflctresrcupdex.
        MESSAGE 'Conflict updating topic rule resource.' TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_topic_rule]
  ENDMETHOD.


  METHOD update_thing_shadow.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iop) = /aws1/cl_iop_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.update_thing_shadow]
    TRY.
        " iv_thing_name   = 'MyIoTThing'
        " iv_shadow_state = '{"state":{"reported":{"temperature":22}}}'
        lo_iop->updatethingshadow(
          iv_thingname = iv_thing_name
          iv_payload   = iv_shadow_state ).
        MESSAGE |Shadow updated for IoT thing: { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iopresourcenotfoundex.
        MESSAGE 'Cannot update thing shadow. Resource not found.' TYPE 'E'.
      CATCH /aws1/cx_iopconflictexception.
        MESSAGE 'Shadow update conflict. State version mismatch.' TYPE 'E'.
      CATCH /aws1/cx_iopserverexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.update_thing_shadow]
  ENDMETHOD.


  METHOD get_thing_shadow.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iop) = /aws1/cl_iop_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.get_thing_shadow]
    TRY.
        " iv_thing_name = 'MyIoTThing'
        oo_result = lo_iop->getthingshadow(
          iv_thingname = iv_thing_name ).
        MESSAGE |Shadow retrieved for IoT thing: { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iopresourcenotfoundex.
        MESSAGE 'Cannot get thing shadow. Resource not found.' TYPE 'E'.
      CATCH /aws1/cx_iopserverexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.get_thing_shadow]
  ENDMETHOD.

ENDCLASS.
