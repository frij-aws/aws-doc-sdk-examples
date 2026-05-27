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
      RAISING
        /aws1/cx_rt_generic.

    METHODS list_things
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_iotlistthingsresponse
      RAISING
        /aws1/cx_rt_generic.

    METHODS create_keys_and_certificate
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_iotcrekeysandcertrsp
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
      RETURNING
        VALUE(ov_address) TYPE /aws1/iotendpointaddress
      RAISING
        /aws1/cx_rt_generic.

    METHODS list_certificates
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_iotlistcertsresponse
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
        !iv_rule_name      TYPE /aws1/iotrulename
        !iv_topic          TYPE /aws1/iottopic
        !iv_sns_action_arn TYPE /aws1/iotawsarn
        !iv_role_arn       TYPE /aws1/iotawsarn
      RAISING
        /aws1/cx_rt_generic.

    METHODS list_topic_rules
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_iotlisttopicrulesrsp
      RAISING
        /aws1/cx_rt_generic.

    METHODS search_index
      IMPORTING
        !iv_query        TYPE /aws1/iotquerystring
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_iotsearchindexrsp
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
          iv_thingname = iv_thing_name
        ).
        MESSAGE |IoT thing created: { iv_thing_name } ARN: { oo_result->get_thingarn( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
      CATCH /aws1/cx_iotinvalidrequestex INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex2.
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
      CATCH /aws1/cx_iotinvalidrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
    ENDTRY.
    " snippet-end:[iot.abapv1.list_things]
  ENDMETHOD.


  METHOD create_keys_and_certificate.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.create_keys_and_certificate]
    TRY.
        oo_result = lo_iot->createkeysandcertificate( abap_true ).
        MESSAGE |Certificate created: { oo_result->get_certificateid( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotinvalidrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
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
          iv_principal = iv_principal
        ).
        MESSAGE |Principal attached to thing: { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
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
          " iv_endpoint_type = 'iot:Data-ATS'
          iv_endpointtype = iv_endpoint_type
        ).
        ov_address = lo_result->get_endpointaddress( ).
        MESSAGE |Endpoint address: { ov_address }| TYPE 'I'.
      CATCH /aws1/cx_iotinvalidrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
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
        MESSAGE |Retrieved { lines( oo_result->get_certificates( ) ) } IoT certificates| TYPE 'I'.
      CATCH /aws1/cx_iotinvalidrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
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
          iv_principal = iv_principal
        ).
        MESSAGE |Principal detached from thing: { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
    ENDTRY.
    " snippet-end:[iot.abapv1.detach_thing_principal]
  ENDMETHOD.


  METHOD delete_certificate.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.delete_certificate]
    TRY.
        " Deactivate the certificate before deleting it.
        lo_iot->updatecertificate(
          iv_certificateid = iv_certificate_id
          iv_newstatus     = 'INACTIVE'
        ).
        lo_iot->deletecertificate(
          iv_certificateid = iv_certificate_id
        ).
        MESSAGE |Certificate deleted: { iv_certificate_id }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_certificate]
  ENDMETHOD.


  METHOD create_topic_rule.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.create_topic_rule]
    TRY.
        lo_iot->createtopicrule(
          iv_rulename = iv_rule_name
          io_topicrulepayload = NEW /aws1/cl_iottopicrulepayload(
            " iv_sql = 'SELECT * FROM ''my/iot/topic'''
            iv_sql     = |SELECT * FROM '{ iv_topic }'|
            it_actions = VALUE /aws1/cl_iotaction=>tt_actionlist(
              (
                NEW /aws1/cl_iotaction(
                  io_sns = NEW /aws1/cl_iotsnsaction(
                    iv_targetarn = iv_sns_action_arn
                    iv_rolearn   = iv_role_arn
                  )
                )
              )
            )
          )
        ).
        MESSAGE |Topic rule created: { iv_rule_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
      CATCH /aws1/cx_iotsqlparseexception INTO DATA(lo_sql_ex).
        MESSAGE lo_sql_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_sql_ex.
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
      CATCH /aws1/cx_iotinvalidrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
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
          " iv_query = 'thingName:MyDevice*'
          iv_querystring = iv_query
        ).
        MESSAGE |Found { lines( oo_result->get_things( ) ) } things matching query| TYPE 'I'.
      CATCH /aws1/cx_iotindexnotreadyex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_ex2).
        MESSAGE lo_ex2->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex2.
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
            " iv_thingindexingmode = 'REGISTRY' (other options: OFF, REGISTRY_AND_SHADOW)
            iv_thingindexingmode = 'REGISTRY'
          )
        ).
        MESSAGE 'IoT thing indexing configuration updated to REGISTRY mode.' TYPE 'I'.
      CATCH /aws1/cx_iotinvalidrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
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
          iv_thingname = iv_thing_name
        ).
        MESSAGE |IoT thing deleted: { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
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
          iv_rulename = iv_rule_name
        ).
        MESSAGE |Topic rule deleted: { iv_rule_name }| TYPE 'I'.
      CATCH /aws1/cx_iotinvalidrequestex INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'I'.
        RAISE EXCEPTION lo_ex.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_topic_rule]
  ENDMETHOD.

ENDCLASS.
