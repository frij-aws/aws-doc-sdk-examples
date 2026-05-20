" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS /awsex/cl_iot_actions DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    " Creates an AWS IoT thing.
    " @parameter iv_thing_name | The name of the thing to create (e.g., 'MyIoTThing')
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS create_thing
      IMPORTING
        !iv_thing_name    TYPE /aws1/iotthingname
      RAISING
        /aws1/cx_rt_generic.

    " Lists AWS IoT things.
    " @parameter ot_things | The list of thing attributes
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS list_things
      EXPORTING
        VALUE(ot_things)  TYPE /aws1/cl_iotthingattribute=>tt_thingattributelist
      RAISING
        /aws1/cx_rt_generic.

    " Creates keys and a certificate for an AWS IoT thing.
    " @parameter ov_certificate_id | The ID of the created certificate
    " @parameter ov_certificate_arn | The ARN of the created certificate
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS create_keys_and_certificate
      EXPORTING
        VALUE(ov_certificate_id)  TYPE /aws1/iotcertificateid
        VALUE(ov_certificate_arn) TYPE /aws1/iotcertificatearn
      RAISING
        /aws1/cx_rt_generic.

    " Attaches a certificate to an AWS IoT thing.
    " @parameter iv_thing_name | The name of the thing (e.g., 'MyIoTThing')
    " @parameter iv_principal | The ARN of the certificate to attach
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS attach_thing_principal
      IMPORTING
        !iv_thing_name  TYPE /aws1/iotthingname
        !iv_principal   TYPE /aws1/iotprincipal
      RAISING
        /aws1/cx_rt_generic.

    " Gets the AWS IoT endpoint address.
    " @parameter iv_endpoint_type | Endpoint type (e.g., 'iot:Data-ATS')
    " @parameter ov_endpoint_address | The endpoint address
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS describe_endpoint
      IMPORTING
        !iv_endpoint_type       TYPE /aws1/iotendpointtype
                                DEFAULT 'iot:Data-ATS'
      EXPORTING
        VALUE(ov_endpoint_addr) TYPE /aws1/iotendpointaddress
      RAISING
        /aws1/cx_rt_generic.

    " Lists AWS IoT certificates.
    " @parameter ot_certificates | The list of certificates
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS list_certificates
      EXPORTING
        VALUE(ot_certificates) TYPE /aws1/cl_iotcertificate=>tt_certificates
      RAISING
        /aws1/cx_rt_generic.

    " Detaches a certificate from an AWS IoT thing.
    " @parameter iv_thing_name | The name of the thing
    " @parameter iv_principal | The ARN of the certificate to detach
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS detach_thing_principal
      IMPORTING
        !iv_thing_name  TYPE /aws1/iotthingname
        !iv_principal   TYPE /aws1/iotprincipal
      RAISING
        /aws1/cx_rt_generic.

    " Deactivates and deletes an AWS IoT certificate.
    " @parameter iv_certificate_id | The ID of the certificate to delete
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS delete_certificate
      IMPORTING
        !iv_certificate_id  TYPE /aws1/iotcertificateid
      RAISING
        /aws1/cx_rt_generic.

    " Creates an AWS IoT topic rule that routes messages to SNS.
    " @parameter iv_rule_name | The name of the rule (e.g., 'MyTopicRule')
    " @parameter iv_topic | The MQTT topic to subscribe to (e.g., 'iot/my/topic')
    " @parameter iv_sns_action_arn | The ARN of the SNS topic
    " @parameter iv_role_arn | The ARN of the IAM role
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS create_topic_rule
      IMPORTING
        !iv_rule_name       TYPE /aws1/iotrulename
        !iv_topic           TYPE /aws1/iottopic
        !iv_sns_action_arn  TYPE /aws1/iotawsarn
        !iv_role_arn        TYPE /aws1/iotawsarn
      RAISING
        /aws1/cx_rt_generic.

    " Lists AWS IoT topic rules.
    " @parameter ot_rules | The list of topic rule list items
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS list_topic_rules
      EXPORTING
        VALUE(ot_rules) TYPE /aws1/cl_iottopicrulelistitem=>tt_topicrulelist
      RAISING
        /aws1/cx_rt_generic.

    " Searches the AWS IoT fleet index.
    " @parameter iv_query | The search query string (e.g., 'thingName:MyThing*')
    " @parameter ot_things | The list of matching thing documents
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS search_index
      IMPORTING
        !iv_query       TYPE /aws1/iotquerystring
      EXPORTING
        VALUE(ot_things) TYPE /aws1/cl_iotthingdocument=>tt_thingdocumentlist
      RAISING
        /aws1/cx_rt_generic.

    " Updates the AWS IoT indexing configuration to enable thing indexing.
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS update_indexing_configuration
      RAISING
        /aws1/cx_rt_generic.

    " Deletes an AWS IoT thing.
    " @parameter iv_thing_name | The name of the thing to delete
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS delete_thing
      IMPORTING
        !iv_thing_name  TYPE /aws1/iotthingname
      RAISING
        /aws1/cx_rt_generic.

    " Deletes an AWS IoT topic rule.
    " @parameter iv_rule_name | The name of the rule to delete
    " @raising /aws1/cx_rt_generic | Thrown when operation fails
    METHODS delete_topic_rule
      IMPORTING
        !iv_rule_name   TYPE /aws1/iotrulename
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
        DATA(oo_result) = lo_iot->creatething(
          iv_thingname = iv_thing_name ).
        MESSAGE |IoT thing created: { oo_result->get_thingname( ) }| &&
                | ARN: { oo_result->get_thingarn( ) }| TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex.
        MESSAGE |Thing '{ iv_thing_name }' already exists.| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_srvex).
        MESSAGE lo_srvex->get_text( ) TYPE 'E'.
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
        CLEAR ot_things.
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
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_srvex).
        MESSAGE lo_srvex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.list_things]
  ENDMETHOD.


  METHOD create_keys_and_certificate.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.create_keys_and_certificate]
    TRY.
        DATA(lo_result) = lo_iot->createkeysandcertificate(
          iv_setasactive = abap_true ).
        ov_certificate_id  = lo_result->get_certificateid( ).
        ov_certificate_arn = lo_result->get_certificatearn( ).
        MESSAGE |Certificate created: { ov_certificate_id }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_srvex).
        MESSAGE lo_srvex->get_text( ) TYPE 'E'.
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
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE |Resource not found when attaching principal.| TYPE 'E'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_srvex).
        MESSAGE lo_srvex->get_text( ) TYPE 'E'.
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
        " example: 'abcdefgh12345-ats.iot.us-east-1.amazonaws.com'
        ov_endpoint_addr = lo_result->get_endpointaddress( ).
        MESSAGE |Endpoint address: { ov_endpoint_addr }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_srvex).
        MESSAGE lo_srvex->get_text( ) TYPE 'E'.
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
        CLEAR ot_certificates.
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
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_srvex).
        MESSAGE lo_srvex->get_text( ) TYPE 'E'.
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
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE |Resource not found when detaching principal.| TYPE 'E'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_srvex).
        MESSAGE lo_srvex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.detach_thing_principal]
  ENDMETHOD.


  METHOD delete_certificate.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.delete_certificate]
    TRY.
        " Deactivate the certificate before deleting it
        lo_iot->updatecertificate(
          iv_certificateid = iv_certificate_id
          iv_newstatus     = 'INACTIVE' ).
        lo_iot->deletecertificate(
          iv_certificateid = iv_certificate_id ).
        MESSAGE |Certificate deleted: { iv_certificate_id }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE |Certificate not found.| TYPE 'E'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_srvex).
        MESSAGE lo_srvex->get_text( ) TYPE 'E'.
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
          iv_targetarn = iv_sns_action_arn
          iv_rolearn   = iv_role_arn ).

        " Wrap in an action object
        DATA(lo_action) = NEW /aws1/cl_iotaction(
          io_sns = lo_sns_action ).

        " Build the actions list
        DATA lt_actions TYPE /aws1/cl_iotaction=>tt_actionlist.
        APPEND lo_action TO lt_actions.

        " Build the topic rule SQL statement
        DATA(lv_sql) = |SELECT * FROM '{ iv_topic }'|.

        " Build the topic rule payload
        DATA(lo_payload) = NEW /aws1/cl_iottopicrulepayload(
          iv_sql     = lv_sql
          it_actions = lt_actions ).

        lo_iot->createtopicrule(
          iv_rulename         = iv_rule_name
          io_topicrulepayload = lo_payload ).
        MESSAGE |Topic rule created: { iv_rule_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresrcalrdyexistsex.
        MESSAGE |Topic rule '{ iv_rule_name }' already exists.| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_srvex).
        MESSAGE lo_srvex->get_text( ) TYPE 'E'.
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
        CLEAR ot_rules.
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
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_srvex).
        MESSAGE lo_srvex->get_text( ) TYPE 'E'.
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
        MESSAGE |Found { lines( ot_things ) } IoT things matching query| TYPE 'I'.
      CATCH /aws1/cx_iotindexnotreadyex.
        MESSAGE 'Indexing is not ready. Enable indexing first.' TYPE 'E'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_srvex).
        MESSAGE lo_srvex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.search_index]
  ENDMETHOD.


  METHOD update_indexing_configuration.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_iot) = /aws1/cl_iot_factory=>create( lo_session ).

    " snippet-start:[iot.abapv1.update_indexing_configuration]
    TRY.
        " 'REGISTRY' mode indexes thing names, types, and attributes
        DATA(lo_thing_idx_conf) = NEW /aws1/cl_iotthingindexingconf(
          iv_thingindexingmode = 'REGISTRY' ).
        lo_iot->updateindexingconfiguration(
          io_thingindexingconf = lo_thing_idx_conf ).
        MESSAGE 'Indexing configuration updated to REGISTRY mode.' TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_srvex).
        MESSAGE lo_srvex->get_text( ) TYPE 'E'.
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
          iv_thingname = iv_thing_name ).
        MESSAGE |IoT thing deleted: { iv_thing_name }| TYPE 'I'.
      CATCH /aws1/cx_iotresourcenotfoundex.
        MESSAGE |Thing '{ iv_thing_name }' not found.| TYPE 'E'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_srvex).
        MESSAGE lo_srvex->get_text( ) TYPE 'E'.
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
          iv_rulename = iv_rule_name ).
        MESSAGE |Topic rule deleted: { iv_rule_name }| TYPE 'I'.
      CATCH /aws1/cx_iotclientexc INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_iotserverexc INTO DATA(lo_srvex).
        MESSAGE lo_srvex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[iot.abapv1.delete_topic_rule]
  ENDMETHOD.

ENDCLASS.
