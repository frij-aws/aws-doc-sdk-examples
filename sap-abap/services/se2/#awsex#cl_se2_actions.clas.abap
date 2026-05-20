" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS /awsex/cl_se2_actions DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.
    METHODS create_email_identity
      IMPORTING
        !iv_email_identity TYPE /aws1/se2identity
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_se2createemailidrsp
      RAISING
        /aws1/cx_rt_generic.

    METHODS create_contact_list
      IMPORTING
        !iv_contact_list_name TYPE /aws1/se2contactlistname
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_se2crecontactlistrsp
      RAISING
        /aws1/cx_rt_generic.

    METHODS create_email_template
      IMPORTING
        !iv_template_name TYPE /aws1/se2emailtemplatename
        !iv_subject       TYPE /aws1/se2emailtemplatesubject
        !iv_html          TYPE /aws1/se2emailtemplatehtml
        !iv_text          TYPE /aws1/se2emailtemplatetext
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_se2createemailtmplrsp
      RAISING
        /aws1/cx_rt_generic.

    METHODS create_contact
      IMPORTING
        !iv_contact_list_name TYPE /aws1/se2contactlistname
        !iv_email_address     TYPE /aws1/se2emailaddress
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_se2createcontactrsp
      RAISING
        /aws1/cx_rt_generic.

    METHODS send_email
      IMPORTING
        !iv_from_email_address TYPE /aws1/se2emailaddress
        !iv_to_email_address   TYPE /aws1/se2emailaddress
        !iv_subject            TYPE /aws1/se2messagedata
        !iv_html_body          TYPE /aws1/se2messagedata
        !iv_text_body          TYPE /aws1/se2messagedata
      RETURNING
        VALUE(ov_message_id) TYPE /aws1/se2outboundmessageid
      RAISING
        /aws1/cx_rt_generic.

    METHODS send_email_template
      IMPORTING
        !iv_from_email_address TYPE /aws1/se2emailaddress
        !iv_to_email_address   TYPE /aws1/se2emailaddress
        !iv_template_name      TYPE /aws1/se2emailtemplatename
        !iv_template_data      TYPE /aws1/se2emailtemplatedata
        !iv_contact_list_name  TYPE /aws1/se2contactlistname
      RETURNING
        VALUE(ov_message_id) TYPE /aws1/se2outboundmessageid
      RAISING
        /aws1/cx_rt_generic.

    METHODS list_contacts
      IMPORTING
        !iv_contact_list_name TYPE /aws1/se2contactlistname
      EXPORTING
        !oo_result            TYPE REF TO /aws1/cl_se2listcontactsrsp
      RAISING
        /aws1/cx_rt_generic.

    METHODS delete_contact_list
      IMPORTING
        !iv_contact_list_name TYPE /aws1/se2contactlistname
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_se2delcontactlistrsp
      RAISING
        /aws1/cx_rt_generic.

    METHODS delete_email_template
      IMPORTING
        !iv_template_name TYPE /aws1/se2emailtemplatename
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_se2deleteemailtmplrsp
      RAISING
        /aws1/cx_rt_generic.

    METHODS delete_email_identity
      IMPORTING
        !iv_email_identity TYPE /aws1/se2identity
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_se2deleteemailidrsp
      RAISING
        /aws1/cx_rt_generic.

    METHODS get_email_identity
      IMPORTING
        !iv_email_address TYPE /aws1/se2identity
      EXPORTING
        !oo_result TYPE REF TO /aws1/cl_se2getemailidresponse
      RAISING
        /aws1/cx_rt_generic.

    METHODS send_email_with_attachment
      IMPORTING
        !iv_from_address   TYPE /aws1/se2emailaddress
        !it_to_addresses   TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist
        !iv_subject        TYPE /aws1/se2messagedata
        !iv_html_body      TYPE /aws1/se2messagedata
        !iv_text_body      TYPE /aws1/se2messagedata
        !it_attachments    TYPE /aws1/cl_se2attachment=>tt_attachmentlist OPTIONAL
      RETURNING
        VALUE(ov_message_id) TYPE /aws1/se2outboundmessageid
      RAISING
        /aws1/cx_rt_generic.

    METHODS send_bulk_email
      IMPORTING
        !iv_from_address          TYPE /aws1/se2emailaddress
        !iv_template_name         TYPE /aws1/se2emailtemplatename
        !iv_default_template_data TYPE /aws1/se2emailtemplatedata
        !it_bulk_entries          TYPE /aws1/cl_se2bulkemailentry=>tt_bulkemailentrylist
        !it_attachments           TYPE /aws1/cl_se2attachment=>tt_attachmentlist OPTIONAL
      RETURNING
        VALUE(ot_results) TYPE /aws1/cl_se2bulkemailentryrslt=>tt_bulkemailentryresultlist
      RAISING
        /aws1/cx_rt_generic.

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS /awsex/cl_se2_actions IMPLEMENTATION.

  METHOD create_email_identity.
    " snippet-start:[se2.abapv1.create_email_identity]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_se2) = /aws1/cl_se2_factory=>create( lo_session ).

    TRY.
        oo_result = lo_se2->createemailidentity(
          iv_emailidentity = iv_email_identity ).
        " e.g. iv_email_identity = 'sender@example.com'
        DATA(lv_identity_type) = oo_result->get_identitytype( ).
        MESSAGE |Email identity created: { iv_email_identity } | &&
                |type: { lv_identity_type }| TYPE 'I'.
      CATCH /aws1/cx_se2alreadyexistsex.
        MESSAGE |Email identity { iv_email_identity } already exists.| TYPE 'I'.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bad_request).
        MESSAGE lo_bad_request TYPE 'I' DISPLAY LIKE 'E'.
      CATCH /aws1/cx_se2limitexceededex INTO DATA(lo_limit_exceeded).
        MESSAGE lo_limit_exceeded TYPE 'I' DISPLAY LIKE 'E'.
    ENDTRY.
    " snippet-end:[se2.abapv1.create_email_identity]
  ENDMETHOD.

  METHOD create_contact_list.
    " snippet-start:[se2.abapv1.create_contact_list]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_se2) = /aws1/cl_se2_factory=>create( lo_session ).

    TRY.
        oo_result = lo_se2->createcontactlist(
          iv_contactlistname = iv_contact_list_name ).
        MESSAGE |Contact list created: { iv_contact_list_name }| TYPE 'I'.
      CATCH /aws1/cx_se2alreadyexistsex.
        MESSAGE |Contact list { iv_contact_list_name } already exists.| TYPE 'I'.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bad_request).
        MESSAGE 'Bad request - contact list limit may be reached.' TYPE 'I'.
        " Re-raise so the caller can handle the limit condition
        RAISE EXCEPTION lo_bad_request.
      CATCH /aws1/cx_se2limitexceededex INTO DATA(lo_limit_exceeded).
        MESSAGE 'Limit exceeded - contact list limit reached.' TYPE 'I'.
        " Re-raise so the caller can handle the limit condition
        RAISE EXCEPTION lo_limit_exceeded.
    ENDTRY.
    " snippet-end:[se2.abapv1.create_contact_list]
  ENDMETHOD.

  METHOD create_email_template.
    " snippet-start:[se2.abapv1.create_email_template]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_se2) = /aws1/cl_se2_factory=>create( lo_session ).

    TRY.
        DATA(lo_template_content) = NEW /aws1/cl_se2emailtmplcontent(
          iv_subject = iv_subject
          iv_html    = iv_html
          iv_text    = iv_text ).

        oo_result = lo_se2->createemailtemplate(
          iv_templatename    = iv_template_name
          io_templatecontent = lo_template_content ).
        MESSAGE |Email template created: { iv_template_name }| TYPE 'I'.
      CATCH /aws1/cx_se2alreadyexistsex.
        MESSAGE |Email template { iv_template_name } already exists.| TYPE 'I'.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bad_request).
        MESSAGE 'Bad request.' TYPE 'I' DISPLAY LIKE 'E'.
      CATCH /aws1/cx_se2limitexceededex INTO DATA(lo_limit_exceeded).
        MESSAGE 'Limit exceeded.' TYPE 'I' DISPLAY LIKE 'E'.
    ENDTRY.
    " snippet-end:[se2.abapv1.create_email_template]
  ENDMETHOD.

  METHOD create_contact.
    " snippet-start:[se2.abapv1.create_contact]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_se2) = /aws1/cl_se2_factory=>create( lo_session ).

    TRY.
        oo_result = lo_se2->createcontact(
          iv_contactlistname = iv_contact_list_name
          iv_emailaddress    = iv_email_address ).
        MESSAGE |Contact created: { iv_email_address }| TYPE 'I'.
      CATCH /aws1/cx_se2alreadyexistsex.
        MESSAGE |Contact { iv_email_address } already exists.| TYPE 'I'.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bad_request).
        MESSAGE 'Bad request.' TYPE 'I' DISPLAY LIKE 'E'.
      CATCH /aws1/cx_se2notfoundexception INTO DATA(lo_not_found).
        MESSAGE 'Contact list not found.' TYPE 'I' DISPLAY LIKE 'E'.
    ENDTRY.
    " snippet-end:[se2.abapv1.create_contact]
  ENDMETHOD.

  METHOD send_email.
    " snippet-start:[se2.abapv1.send_email]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_se2) = /aws1/cl_se2_factory=>create( lo_session ).

    TRY.
        " Build recipient list and destination
        DATA lt_to_addresses TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
        APPEND NEW /aws1/cl_se2emailaddresslist_w(
          iv_value = iv_to_email_address ) TO lt_to_addresses.
        DATA(lo_destination) = NEW /aws1/cl_se2destination(
          it_toaddresses = lt_to_addresses ).

        " Build subject and body
        DATA(lo_subject)   = NEW /aws1/cl_se2content( iv_data = iv_subject ).
        DATA(lo_text_body) = NEW /aws1/cl_se2content( iv_data = iv_text_body ).
        DATA(lo_html_body) = NEW /aws1/cl_se2content( iv_data = iv_html_body ).
        DATA(lo_body)      = NEW /aws1/cl_se2body(
          io_text = lo_text_body
          io_html = lo_html_body ).
        DATA(lo_message)   = NEW /aws1/cl_se2message(
          io_subject = lo_subject
          io_body    = lo_body ).
        DATA(lo_content)   = NEW /aws1/cl_se2emailcontent(
          io_simple = lo_message ).

        " Send the email
        DATA(lo_result) = lo_se2->sendemail(
          iv_fromemailaddress = iv_from_email_address
          io_destination      = lo_destination
          io_content          = lo_content ).

        ov_message_id = lo_result->get_messageid( ).
        MESSAGE |Email sent. MessageId: { ov_message_id }| TYPE 'I'.
      CATCH /aws1/cx_se2accountsuspendedex INTO DATA(lo_account_suspended).
        MESSAGE 'Account suspended.' TYPE 'I'.
        RAISE EXCEPTION lo_account_suspended.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bad_request).
        MESSAGE 'Bad request.' TYPE 'I'.
        RAISE EXCEPTION lo_bad_request.
      CATCH /aws1/cx_se2messagerejected INTO DATA(lo_message_rejected).
        MESSAGE 'Message rejected - check email verification.' TYPE 'I'.
        RAISE EXCEPTION lo_message_rejected.
    ENDTRY.
    " snippet-end:[se2.abapv1.send_email]
  ENDMETHOD.

  METHOD send_email_template.
    " snippet-start:[se2.abapv1.send_email_template]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_se2) = /aws1/cl_se2_factory=>create( lo_session ).

    TRY.
        " Build recipient list and destination
        DATA lt_to_addresses TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
        APPEND NEW /aws1/cl_se2emailaddresslist_w(
          iv_value = iv_to_email_address ) TO lt_to_addresses.
        DATA(lo_destination) = NEW /aws1/cl_se2destination(
          it_toaddresses = lt_to_addresses ).

        " Reference the template and its variable data
        DATA(lo_template) = NEW /aws1/cl_se2template(
          iv_templatename = iv_template_name
          iv_templatedata = iv_template_data ).
        DATA(lo_content)  = NEW /aws1/cl_se2emailcontent(
          io_template = lo_template ).

        " Honour list-management unsubscribe preferences
        DATA(lo_list_mgmt) = NEW /aws1/cl_se2listmanagementopts(
          iv_contactlistname = iv_contact_list_name ).

        " Send the templated email
        DATA(lo_result) = lo_se2->sendemail(
          iv_fromemailaddress     = iv_from_email_address
          io_destination          = lo_destination
          io_content              = lo_content
          io_listmanagementoptions = lo_list_mgmt ).

        ov_message_id = lo_result->get_messageid( ).
        MESSAGE |Templated email sent. MessageId: { ov_message_id }| TYPE 'I'.
      CATCH /aws1/cx_se2accountsuspendedex INTO DATA(lo_account_suspended).
        MESSAGE 'Account suspended.' TYPE 'I'.
        RAISE EXCEPTION lo_account_suspended.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bad_request).
        MESSAGE 'Bad request.' TYPE 'I'.
        RAISE EXCEPTION lo_bad_request.
      CATCH /aws1/cx_se2messagerejected INTO DATA(lo_message_rejected).
        MESSAGE 'Message rejected - check email verification.' TYPE 'I'.
        RAISE EXCEPTION lo_message_rejected.
    ENDTRY.
    " snippet-end:[se2.abapv1.send_email_template]
  ENDMETHOD.

  METHOD list_contacts.
    " snippet-start:[se2.abapv1.list_contacts]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_se2) = /aws1/cl_se2_factory=>create( lo_session ).

    TRY.
        oo_result = lo_se2->listcontacts(
          iv_contactlistname = iv_contact_list_name ).
        MESSAGE |Retrieved { lines( oo_result->get_contacts( ) ) } | &&
                |contacts from list { iv_contact_list_name }.| TYPE 'I'.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bad_request).
        MESSAGE 'Bad request.' TYPE 'I'.
        RAISE EXCEPTION lo_bad_request.
      CATCH /aws1/cx_se2notfoundexception INTO DATA(lo_not_found).
        MESSAGE 'Contact list not found.' TYPE 'I'.
        RAISE EXCEPTION lo_not_found.
    ENDTRY.
    " snippet-end:[se2.abapv1.list_contacts]
  ENDMETHOD.

  METHOD delete_contact_list.
    " snippet-start:[se2.abapv1.delete_contact_list]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_se2) = /aws1/cl_se2_factory=>create( lo_session ).

    TRY.
        oo_result = lo_se2->deletecontactlist(
          iv_contactlistname = iv_contact_list_name ).
        MESSAGE |Contact list deleted: { iv_contact_list_name }| TYPE 'I'.
      CATCH /aws1/cx_se2notfoundexception.
        MESSAGE |Contact list { iv_contact_list_name } not found | &&
                |or already deleted.| TYPE 'I'.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bad_request).
        MESSAGE 'Bad request.' TYPE 'I'.
        RAISE EXCEPTION lo_bad_request.
    ENDTRY.
    " snippet-end:[se2.abapv1.delete_contact_list]
  ENDMETHOD.

  METHOD delete_email_template.
    " snippet-start:[se2.abapv1.delete_email_template]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_se2) = /aws1/cl_se2_factory=>create( lo_session ).

    TRY.
        oo_result = lo_se2->deleteemailtemplate(
          iv_templatename = iv_template_name ).
        MESSAGE |Email template deleted: { iv_template_name }| TYPE 'I'.
      CATCH /aws1/cx_se2notfoundexception.
        MESSAGE |Email template { iv_template_name } not found | &&
                |or already deleted.| TYPE 'I'.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bad_request).
        MESSAGE 'Bad request.' TYPE 'I'.
        RAISE EXCEPTION lo_bad_request.
    ENDTRY.
    " snippet-end:[se2.abapv1.delete_email_template]
  ENDMETHOD.

  METHOD delete_email_identity.
    " snippet-start:[se2.abapv1.delete_email_identity]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_se2) = /aws1/cl_se2_factory=>create( lo_session ).

    TRY.
        oo_result = lo_se2->deleteemailidentity(
          iv_emailidentity = iv_email_identity ).
        MESSAGE |Email identity deleted: { iv_email_identity }| TYPE 'I'.
      CATCH /aws1/cx_se2notfoundexception.
        MESSAGE |Email identity { iv_email_identity } not found | &&
                |or already deleted.| TYPE 'I'.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bad_request).
        MESSAGE 'Bad request.' TYPE 'I'.
        RAISE EXCEPTION lo_bad_request.
    ENDTRY.
    " snippet-end:[se2.abapv1.delete_email_identity]
  ENDMETHOD.

  METHOD get_email_identity.
    " snippet-start:[se2.abapv1.get_email_identity]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_se2) = /aws1/cl_se2_factory=>create( lo_session ).

    TRY.
        oo_result = lo_se2->getemailidentity(
          iv_emailidentity = iv_email_address ).
        " e.g. iv_email_address = 'sender@example.com'
        MESSAGE |Email identity type: { oo_result->get_identitytype( ) }| TYPE 'I'.
      CATCH /aws1/cx_se2notfoundexception INTO DATA(lo_not_found).
        MESSAGE |Email identity { iv_email_address } not found.| TYPE 'I' DISPLAY LIKE 'E'.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bad_request).
        MESSAGE 'Bad request.' TYPE 'I' DISPLAY LIKE 'E'.
    ENDTRY.
    " snippet-end:[se2.abapv1.get_email_identity]
  ENDMETHOD.

  METHOD send_email_with_attachment.
    " snippet-start:[se2.abapv1.send_email_with_attachment]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_se2) = /aws1/cl_se2_factory=>create( lo_session ).

    TRY.
        " Build destination from the supplied list of To addresses
        DATA(lo_destination) = NEW /aws1/cl_se2destination(
          it_toaddresses = it_to_addresses ).

        " Build subject and body content objects
        DATA(lo_subject)    = NEW /aws1/cl_se2content( iv_data = iv_subject ).
        DATA(lo_text_part)  = NEW /aws1/cl_se2content( iv_data = iv_text_body ).
        DATA(lo_html_part)  = NEW /aws1/cl_se2content( iv_data = iv_html_body ).
        DATA(lo_body)       = NEW /aws1/cl_se2body(
          io_text = lo_text_part
          io_html = lo_html_part ).

        " Build Simple message, optionally including attachments.
        " SES handles MIME construction automatically when attachments
        " are included with the Simple content type.
        DATA(lo_message)    = NEW /aws1/cl_se2message(
          io_subject     = lo_subject
          io_body        = lo_body
          it_attachments = it_attachments ).
        DATA(lo_content)    = NEW /aws1/cl_se2emailcontent(
          io_simple = lo_message ).

        DATA(lo_result) = lo_se2->sendemail(
          iv_fromemailaddress = iv_from_address
          io_destination      = lo_destination
          io_content          = lo_content ).

        ov_message_id = lo_result->get_messageid( ).
        MESSAGE |Email sent. MessageId: { ov_message_id }| TYPE 'I'.
      CATCH /aws1/cx_se2messagerejected INTO DATA(lo_msg_rejected).
        MESSAGE 'Message rejected. Check that attachments use supported ' &&
                'file types and total message size is under 40 MB.' TYPE 'I' DISPLAY LIKE 'E'.
      CATCH /aws1/cx_se2accountsuspendedex INTO DATA(lo_suspended).
        MESSAGE 'Account is suspended.' TYPE 'I' DISPLAY LIKE 'E'.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bad_request).
        MESSAGE 'Bad request - check sender/recipient addresses.' TYPE 'I' DISPLAY LIKE 'E'.
    ENDTRY.
    " snippet-end:[se2.abapv1.send_email_with_attachment]
  ENDMETHOD.

  METHOD send_bulk_email.
    " snippet-start:[se2.abapv1.send_bulk_email]
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_se2) = /aws1/cl_se2_factory=>create( lo_session ).

    TRY.
        " Build the template, optionally attaching files shared by all recipients.
        " Per-recipient template data personalisation is controlled via it_bulk_entries.
        DATA(lo_template) = NEW /aws1/cl_se2template(
          iv_templatename  = iv_template_name
          iv_templatedata  = iv_default_template_data
          it_attachments   = it_attachments ).

        DATA(lo_default_content) = NEW /aws1/cl_se2bulkemailcontent(
          io_template = lo_template ).

        DATA(lo_result) = lo_se2->sendbulkemail(
          iv_fromemailaddress = iv_from_address
          io_defaultcontent   = lo_default_content
          it_bulkemailentries = it_bulk_entries ).

        ot_results = lo_result->get_bulkemailentryresults( ).
        MESSAGE |Sent bulk email to { lines( it_bulk_entries ) } recipients.| TYPE 'I'.
      CATCH /aws1/cx_se2messagerejected INTO DATA(lo_msg_rejected).
        MESSAGE 'Bulk message rejected. Check template, attachment types, ' &&
                'and message size limits.' TYPE 'I' DISPLAY LIKE 'E'.
      CATCH /aws1/cx_se2accountsuspendedex INTO DATA(lo_suspended).
        MESSAGE 'Account is suspended.' TYPE 'I' DISPLAY LIKE 'E'.
      CATCH /aws1/cx_se2notfoundexception INTO DATA(lo_not_found).
        MESSAGE 'Template or identity not found.' TYPE 'I' DISPLAY LIKE 'E'.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bad_request).
        MESSAGE 'Bad request - check sender address and template name.' TYPE 'I' DISPLAY LIKE 'E'.
    ENDTRY.
    " snippet-end:[se2.abapv1.send_bulk_email]
  ENDMETHOD.

ENDCLASS.
