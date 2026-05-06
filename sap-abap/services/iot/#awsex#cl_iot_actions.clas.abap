" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS /awsex/cl_iot_actions DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    METHODS create_thing
      IMPORTING
                !iv_thing_name   TYPE /aws1/iotthingname
      RETURNING
                VALUE(oo_result) TYPE REF TO /aws1/cl_iotcreatethingrsp
      RAISING   /aws1/cx_rt_generic.
    METHODS list_things
      RETURNING
                VALUE(oo_result) TYPE REF TO /aws1/cl_iotlistthingsresponse
      RAISING   /aws1/cx_rt_generic.
    METHODS create_keys_and_cert
      RETURNING
                VALUE(oo_result) TYPE REF TO /aws1/cl_iotcrekeysandcertrsp
      RAISING   /aws1/cx_rt_generic.
    METHODS attach_thing_principal
      IMPORTING
                !iv_thing_name TYPE /aws1/iotthingname
                !iv_principal  TYPE /aws1/iotprincipal
      RAISING   /aws1/cx_rt_generic.
    METHODS describe_endpoint
      IMPORTING
                !iv_endpoint_type TYPE /aws1/iotendpointtype DEFAULT 'iot:Data-ATS'
      RETURNING
                VALUE(oo_result)  TYPE REF TO /aws1/cl_iotdescrendptresponse
      RAISING   /aws1/cx_rt_generic.
    METHODS list_certificates
      RETURNING
                VALUE(oo_result) TYPE REF TO /aws1/cl_iotlistcertsresponse
      RAISING   /aws1/cx_rt_generic.
    METHODS detach_thing_principal
      IMPORTING
                !iv_thing_name TYPE /aws1/iotthingname
                !iv_principal  TYPE /aws1/iotprincipal
      RAISING   /aws1/cx_rt_generic.
    METHODS delete_certificate
      IMPORTING
                !iv_certificate_id TYPE /aws1/iotcertificateid
      RAISING   /aws1/cx_rt_generic.
    METHODS create_topic_rule
      IMPORTING
                !iv_rule_name      TYPE /aws1/iotrulename
                !iv_topic          TYPE /aws1/iottopic
                !iv_sns_action_arn TYPE /aws1/iotawsarn
                !iv_role_arn       TYPE /aws1/iotawsarn
      RAISING   /aws1/cx_rt_generic.
    METHODS list_topic_rules
      RETURNING
                VALUE(oo_result) TYPE REF TO /aws1/cl_iotlisttopicrulesrsp
      RAISING   /aws1/cx_rt_generic.
    METHODS search_index
      IMPORTING
                !iv_query        TYPE /aws1/iotquerystring
      RETURNING
                VALUE(oo_result) TYPE REF TO /aws1/cl_iotsearchindexrsp
      RAISING   /aws1/cx_rt_generic.
    METHODS update_index_config
      RAISING   /aws1/cx_rt_generic.
    METHODS delete_thing
      IMPORTING
                !iv_thing_name TYPE /aws1/iotthingname
      RAISING   /aws1/cx_rt_generic.
    METHODS delete_topic_rule
      IMPORTING
                !iv_rule_name TYPE /aws1/iotrulename
      RAISING   /aws1/cx_rt_generic.
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
        oo_result = lo_iot->creatething( iv_thingname = iv_thing_name ). " oo_result is returned for testing purposes. "
        MESSAGE 'IoT thing created' TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex.
        MESSAGE 'Thing already exists. Skipping creation.' TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.create_thing]
  ENDMETHOD.


  METHOD list_things.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.list_things]
    TRY.
        DATA lt_things TYPE /aws1/cl_iotthingattribute=>tt_thingattributelist.
        DATA lv_nexttoken TYPE /aws1/iotnexttoken.

        " List things with pagination
        DO.
          oo_result = lo_iot->listthings( iv_nexttoken = lv_nexttoken ). " oo_result is returned for testing purposes. "
          DATA(lt_page) = oo_result->get_things( ).
          APPEND LINES OF lt_page TO lt_things.
          lv_nexttoken = oo_result->get_nexttoken( ).
          IF lv_nexttoken IS INITIAL.
            EXIT.
          ENDIF.
        ENDDO.

        MESSAGE 'Retrieved list of IoT things' TYPE 'I'.
      CATCH /aws1/cx_iotthrottlingex.
        MESSAGE 'Request throttled. Please try again later.' TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.list_things]
  ENDMETHOD.


  METHOD create_keys_and_cert.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.create_keys_and_certificate]
    TRY.
        oo_result = lo_iot->createkeysandcertificate( iv_setasactive = abap_true ). " oo_result is returned for testing purposes. "
        DATA(lv_certificate_id) = oo_result->get_certificateid( ).
        DATA(lv_certificate_arn) = oo_result->get_certificatearn( ).
        DATA(lv_certificate_pem) = oo_result->get_certificatepem( ).
        MESSAGE 'Keys and certificate created' TYPE 'I'.
      CATCH /aws1/cx_iotthrottlingex.
        MESSAGE 'Request throttled. Please try again later.' TYPE 'E'.
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
        MESSAGE 'Certificate attached to thing' TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE 'Cannot attach principal. Resource not found.' TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.attach_thing_principal]
  ENDMETHOD.


  METHOD describe_endpoint.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.describe_endpoint]
    " iv_endpoint_type = 'iot:Data-ATS'
    TRY.
        oo_result = lo_iot->describeendpoint( iv_endpointtype = iv_endpoint_type ). " oo_result is returned for testing purposes. "
        DATA(lv_endpoint_address) = oo_result->get_endpointaddress( ).
        MESSAGE 'Retrieved endpoint address' TYPE 'I'.
      CATCH /aws1/cx_iotthrottlingex.
        MESSAGE 'Request throttled. Please try again later.' TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.describe_endpoint]
  ENDMETHOD.


  METHOD list_certificates.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.list_certificates]
    TRY.
        DATA lt_certificates TYPE /aws1/cl_iotcertificate=>tt_certificates.
        DATA lv_marker TYPE /aws1/iotmarker.

        " List certificates with pagination
        DO.
          oo_result = lo_iot->listcertificates( iv_marker = lv_marker ). " oo_result is returned for testing purposes. "
          DATA(lt_page) = oo_result->get_certificates( ).
          APPEND LINES OF lt_page TO lt_certificates.
          lv_marker = oo_result->get_nextmarker( ).
          IF lv_marker IS INITIAL.
            EXIT.
          ENDIF.
        ENDDO.

        MESSAGE 'Retrieved list of certificates' TYPE 'I'.
      CATCH /aws1/cx_iotthrottlingex.
        MESSAGE 'Request throttled. Please try again later.' TYPE 'E'.
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
        MESSAGE 'Certificate detached from thing' TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE 'Cannot detach principal. Resource not found.' TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.detach_thing_principal]
  ENDMETHOD.


  METHOD delete_certificate.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.delete_certificate]
    TRY.
        " First, update certificate status to INACTIVE
        lo_iot->updatecertificate(
          iv_certificateid = iv_certificate_id
          iv_newstatus = 'INACTIVE' ).

        " Then delete the certificate
        lo_iot->deletecertificate( iv_certificateid = iv_certificate_id ).
        MESSAGE 'Certificate deleted' TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE 'Cannot delete certificate. Resource not found.' TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_certificate]
  ENDMETHOD.


  METHOD create_topic_rule.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.create_topic_rule]
    " iv_topic = 'device/+/data'
    TRY.
        " Build SQL query
        DATA(lv_sql) = |SELECT * FROM '{ iv_topic }'|.

        " Create SNS action
        DATA(lo_sns_action) = NEW /aws1/cl_iotsnsaction(
          iv_targetarn = iv_sns_action_arn
          iv_rolearn = iv_role_arn ).

        " Create actions list
        DATA lt_actions TYPE /aws1/cl_iotaction=>tt_actionlist.
        DATA(lo_action) = NEW /aws1/cl_iotaction( io_sns = lo_sns_action ).
        APPEND lo_action TO lt_actions.

        " Create topic rule payload
        DATA(lo_payload) = NEW /aws1/cl_iottopicrulepayload(
          iv_sql = lv_sql
          it_actions = lt_actions ).

        lo_iot->createtopicrule(
          iv_rulename = iv_rule_name
          io_topicrulepayload = lo_payload ).
        MESSAGE 'Topic rule created' TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex.
        MESSAGE 'Topic rule already exists. Skipping creation.' TYPE 'I'.
    ENDTRY.
    " snippet-end:[iot.abapv1.create_topic_rule]
  ENDMETHOD.


  METHOD list_topic_rules.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.list_topic_rules]
    TRY.
        DATA lt_rules TYPE /aws1/cl_iottopicrulelistitem=>tt_topicrulelist.
        DATA lv_nexttoken TYPE /aws1/iotnexttoken.

        " List topic rules with pagination
        DO.
          oo_result = lo_iot->listtopicrules( iv_nexttoken = lv_nexttoken ). " oo_result is returned for testing purposes. "
          DATA(lt_page) = oo_result->get_rules( ).
          APPEND LINES OF lt_page TO lt_rules.
          lv_nexttoken = oo_result->get_nexttoken( ).
          IF lv_nexttoken IS INITIAL.
            EXIT.
          ENDIF.
        ENDDO.

        MESSAGE 'Retrieved list of topic rules' TYPE 'I'.
      CATCH /aws1/cx_iotthrottlingex.
        MESSAGE 'Request throttled. Please try again later.' TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.list_topic_rules]
  ENDMETHOD.


  METHOD search_index.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.search_index]
    TRY.
        oo_result = lo_iot->searchindex( iv_querystring = iv_query ). " oo_result is returned for testing purposes. "
        DATA(lt_things) = oo_result->get_things( ).
        MESSAGE 'Search index completed' TYPE 'I'.
      CATCH /aws1/cx_iotthrottlingex.
        MESSAGE 'Request throttled. Please try again later.' TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.search_index]
  ENDMETHOD.


  METHOD update_index_config.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.update_indexing_configuration]
    TRY.
        " Enable thing indexing
        DATA(lo_thing_index_config) = NEW /aws1/cl_iotthingindexingconf(
          iv_thingindexingmode = 'REGISTRY' ).

        lo_iot->updateindexingconfiguration( io_thingindexingconf = lo_thing_index_config ).
        MESSAGE 'Indexing configuration updated' TYPE 'I'.
      CATCH /aws1/cx_rt_generic.
        MESSAGE 'Failed to update indexing configuration' TYPE 'E'.
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
        MESSAGE 'IoT thing deleted' TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE 'Cannot delete thing. Resource not found.' TYPE 'E'.
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
        MESSAGE 'Topic rule deleted' TYPE 'I'.
      CATCH /aws1/cx_rt_generic.
        MESSAGE 'Failed to delete topic rule' TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_topic_rule]
  ENDMETHOD.
ENDCLASS.
