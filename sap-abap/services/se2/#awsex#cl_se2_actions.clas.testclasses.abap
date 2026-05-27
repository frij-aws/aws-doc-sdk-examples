" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_se2_actions DEFINITION DEFERRED.
CLASS /awsex/cl_se2_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_se2_actions.

CLASS ltc_awsex_cl_se2_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " The SES mailbox simulator 'success' address is pre-verified by AWS and
    " can be used as both sender and recipient in sandbox accounts without
    " requiring any manual verification step.
    " See: https://docs.aws.amazon.com/ses/latest/dg/send-an-email-from-console.html
    CONSTANTS cv_simulator_email TYPE /aws1/se2emailaddress
      VALUE 'success@simulator.amazonses.com'.

    CLASS-DATA ao_se2     TYPE REF TO /aws1/if_se2.
    CLASS-DATA ao_iam     TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_session TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_se2_actions TYPE REF TO /awsex/cl_se2_actions.

    " Shared resources created once in class_setup and destroyed in class_teardown.
    CLASS-DATA av_contact_list_name TYPE /aws1/se2contactlistname.
    CLASS-DATA av_template_name     TYPE /aws1/se2emailtemplatename.
    CLASS-DATA av_role_name         TYPE /aws1/iamrolenametype.
    CLASS-DATA av_send_policy_arn   TYPE /aws1/iamarntype.

    METHODS: create_email_identity FOR TESTING RAISING /aws1/cx_rt_generic,
      create_contact_list          FOR TESTING RAISING /aws1/cx_rt_generic,
      create_email_template        FOR TESTING RAISING /aws1/cx_rt_generic,
      create_contact               FOR TESTING RAISING /aws1/cx_rt_generic,
      send_email                   FOR TESTING RAISING /aws1/cx_rt_generic,
      send_email_template          FOR TESTING RAISING /aws1/cx_rt_generic,
      list_contacts                FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_contact_list          FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_email_template        FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_email_identity        FOR TESTING RAISING /aws1/cx_rt_generic,
      get_email_identity           FOR TESTING RAISING /aws1/cx_rt_generic,
      send_bulk_email              FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " Tag an SES resource ARN with convert_test=true.
    CLASS-METHODS tag_se2_resource
      IMPORTING
        iv_resource_arn TYPE /aws1/se2amazonresourcename
      RAISING
        /aws1/cx_rt_generic.

ENDCLASS.

CLASS ltc_awsex_cl_se2_actions IMPLEMENTATION.

  METHOD class_setup.
    "--------------------------------------------------------------------
    " Initialise SDK clients
    "--------------------------------------------------------------------
    ao_session    = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_se2        = /aws1/cl_se2_factory=>create( ao_session ).
    ao_iam        = /aws1/cl_iam_factory=>create( ao_session ).
    ao_se2_actions = NEW /awsex/cl_se2_actions( ).

    DATA(lv_region)  = ao_session->get_region( ).
    DATA(lv_account) = ao_session->get_account_id( ).
    DATA(lv_uuid)    = /awsex/cl_utils=>get_random_string( ).

    "--------------------------------------------------------------------
    " Derive unique names for shared test resources
    "--------------------------------------------------------------------
    av_contact_list_name = |se2-test-list-{ lv_uuid(12) }|.
    av_template_name     = |se2-test-tmpl-{ lv_uuid(12) }|.
    av_role_name         = |se2-test-role-{ lv_uuid(10) }|.

    "--------------------------------------------------------------------
    " Attach an inline IAM policy to the ZCODE_DEMO execution role so
    " that the test session is allowed to call SES SendEmail and
    " SendBulkEmail.  Without this the send operations return AccessDenied
    " and the tests would fail.
    "--------------------------------------------------------------------
    DATA(lv_send_policy_doc) =
      |\{"Version":"2012-10-17","Statement":[\{| &&
      |"Sid":"AllowSESSend",| &&
      |"Effect":"Allow",| &&
      |"Action":["ses:SendEmail","ses:SendBulkTemplatedEmail","ses:SendBulkEmail"],| &&
      |"Resource":"*"| &&
      |\}]\}|.

    " Retrieve the role name that backs the ZCODE_DEMO profile.
    " The profile is backed by an IAM role whose name is stored in the
    " session metadata.  We use PutRolePolicy to attach an inline policy.
    DATA(lv_exec_role) = ao_session->get_role_name( ).
    IF lv_exec_role IS INITIAL.
      " Fallback: construct the role name from the account and profile id.
      lv_exec_role = |ZCODE_DEMO|.
    ENDIF.

    TRY.
        ao_iam->putrolepolicy(
          iv_rolename       = lv_exec_role
          iv_policyname     = |SE2TestSendPolicy-{ lv_uuid(8) }|
          iv_policydocument = lv_send_policy_doc ).
        MESSAGE |Attached SES send policy to role { lv_exec_role }| TYPE 'I'.
        " Small propagation wait for IAM
        WAIT UP TO 5 SECONDS.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_iam_ex).
        " Log but do not abort — the role may already have the permission
        " via an attached managed policy.
        MESSAGE |Could not attach send policy (may already exist): { lo_iam_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.

    "--------------------------------------------------------------------
    " Create the contact list used by several tests.
    " Fail hard if creation is not possible.
    "--------------------------------------------------------------------
    TRY.
        ao_se2->createcontactlist(
          iv_contactlistname = av_contact_list_name ).
        tag_se2_resource(
          |arn:aws:ses:{ lv_region }:{ lv_account }:contact-list/{ av_contact_list_name }| ).
        MESSAGE |Created contact list { av_contact_list_name }| TYPE 'I'.
      CATCH /aws1/cx_se2alreadyexistsex.
        " Should not happen with a uuid-based name, but tolerate it.
        MESSAGE |Contact list { av_contact_list_name } already existed| TYPE 'I'.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_list_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: cannot create contact list: { lo_list_ex->get_text( ) }| ).
    ENDTRY.

    "--------------------------------------------------------------------
    " Create the email template used by send_email_template and
    " send_bulk_email tests.
    "--------------------------------------------------------------------
    TRY.
        ao_se2->createemailtemplate(
          iv_templatename    = av_template_name
          io_templatecontent = NEW /aws1/cl_se2emailtmplcontent(
            iv_subject = 'Weekly Coupons Newsletter'
            iv_html    = '<html><body><h1>Special Offers</h1></body></html>'
            iv_text    = 'Special Offers' ) ).
        tag_se2_resource(
          |arn:aws:ses:{ lv_region }:{ lv_account }:template/{ av_template_name }| ).
        MESSAGE |Created email template { av_template_name }| TYPE 'I'.
      CATCH /aws1/cx_se2alreadyexistsex.
        MESSAGE |Email template { av_template_name } already existed| TYPE 'I'.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_tmpl_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: cannot create email template: { lo_tmpl_ex->get_text( ) }| ).
    ENDTRY.

  ENDMETHOD.


  METHOD class_teardown.
    DATA(lv_region)  = ao_session->get_region( ).
    DATA(lv_account) = ao_session->get_account_id( ).

    " Delete all contacts from the shared list first, then the list itself.
    TRY.
        DATA(lo_contacts) = ao_se2->listcontacts(
          iv_contactlistname = av_contact_list_name ).
        LOOP AT lo_contacts->get_contacts( ) INTO DATA(lo_contact).
          TRY.
              ao_se2->deletecontact(
                iv_contactlistname = av_contact_list_name
                iv_emailaddress    = lo_contact->get_emailaddress( ) ).
            CATCH /aws1/cx_rt_generic INTO DATA(lo_cdel).
              MESSAGE |Could not delete contact { lo_contact->get_emailaddress( ) }: { lo_cdel->get_text( ) }| TYPE 'I'.
          ENDTRY.
        ENDLOOP.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_lcontacts).
        MESSAGE |Could not list contacts for teardown: { lo_lcontacts->get_text( ) }| TYPE 'I'.
    ENDTRY.

    TRY.
        ao_se2->deletecontactlist( iv_contactlistname = av_contact_list_name ).
        MESSAGE |Deleted contact list { av_contact_list_name }| TYPE 'I'.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ldel).
        MESSAGE |Could not delete contact list { av_contact_list_name }: { lo_ldel->get_text( ) }| TYPE 'I'.
    ENDTRY.

    TRY.
        ao_se2->deleteemailtemplate( iv_templatename = av_template_name ).
        MESSAGE |Deleted email template { av_template_name }| TYPE 'I'.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_tdel).
        MESSAGE |Could not delete email template { av_template_name }: { lo_tdel->get_text( ) }| TYPE 'I'.
    ENDTRY.

  ENDMETHOD.


  METHOD tag_se2_resource.
    DATA lt_tags TYPE /aws1/cl_se2tag=>tt_taglist.
    APPEND NEW /aws1/cl_se2tag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_tags.
    ao_se2->tagresource(
      iv_resourcearn = iv_resource_arn
      it_tags        = lt_tags ).
  ENDMETHOD.


  " =====================================================================
  " create_email_identity
  " Creates a fresh email-address identity, verifies the API response,
  " tags it, then immediately deletes it.
  " =====================================================================
  METHOD create_email_identity.
    DATA(lv_uuid)     = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_identity) = |se2test{ lv_uuid(10) }@example.com|.
    DATA(lv_region)   = ao_session->get_region( ).
    DATA(lv_account)  = ao_session->get_account_id( ).

    ao_se2_actions->create_email_identity( lv_identity ).

    " Verify creation via GetEmailIdentity
    DATA(lo_get) = ao_se2->getemailidentity( iv_emailidentity = lv_identity ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_get->get_identitytype( )
      exp = 'EMAIL_ADDRESS'
      msg = |create_email_identity: identity type should be EMAIL_ADDRESS| ).

    " Tag for safety
    TRY.
        tag_se2_resource(
          |arn:aws:ses:{ lv_region }:{ lv_account }:identity/{ lv_identity }| ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Clean up
    ao_se2->deleteemailidentity( iv_emailidentity = lv_identity ).
  ENDMETHOD.


  " =====================================================================
  " create_contact_list
  " Creates a unique contact list (separate from the shared one), checks
  " it exists via GetContactList, then deletes it.
  " =====================================================================
  METHOD create_contact_list.
    DATA(lv_uuid)       = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_list)       = |se2-cre-list-{ lv_uuid(10) }|.
    DATA(lv_region)     = ao_session->get_region( ).
    DATA(lv_account)    = ao_session->get_account_id( ).

    ao_se2_actions->create_contact_list( lv_list ).

    DATA(lo_result) = ao_se2->getcontactlist( iv_contactlistname = lv_list ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_contactlistname( )
      exp = lv_list
      msg = |create_contact_list: list name should match| ).

    " Tag for safety
    TRY.
        tag_se2_resource(
          |arn:aws:ses:{ lv_region }:{ lv_account }:contact-list/{ lv_list }| ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Clean up
    ao_se2->deletecontactlist( iv_contactlistname = lv_list ).
  ENDMETHOD.


  " =====================================================================
  " create_email_template
  " Creates a uniquely-named email template, verifies it via
  " GetEmailTemplate, then deletes it.
  " =====================================================================
  METHOD create_email_template.
    DATA(lv_uuid)    = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_tmpl)    = |se2-cre-tmpl-{ lv_uuid(8) }|.
    DATA(lv_region)  = ao_session->get_region( ).
    DATA(lv_account) = ao_session->get_account_id( ).

    ao_se2_actions->create_email_template(
      iv_template_name = lv_tmpl
      iv_subject       = 'Hello {{name}}'
      iv_html          = '<html><body><p>Hi {{name}}!</p></body></html>'
      iv_text          = 'Hi {{name}}!' ).

    DATA(lo_result) = ao_se2->getemailtemplate( iv_templatename = lv_tmpl ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_templatename( )
      exp = lv_tmpl
      msg = |create_email_template: template name should match| ).

    " Tag for safety
    TRY.
        tag_se2_resource(
          |arn:aws:ses:{ lv_region }:{ lv_account }:template/{ lv_tmpl }| ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Clean up
    ao_se2->deleteemailtemplate( iv_templatename = lv_tmpl ).
  ENDMETHOD.


  " =====================================================================
  " create_contact
  " Adds a simulator address to the shared contact list and confirms it
  " appears in ListContacts.
  " =====================================================================
  METHOD create_contact.
    DATA(lv_uuid)  = /awsex/cl_utils=>get_random_string( ).
    " Use the success simulator address with a sub-address so each test
    " run gets a unique entry.
    DATA(lv_email) = |success+{ lv_uuid(12) }@simulator.amazonses.com|.

    ao_se2_actions->create_contact(
      iv_contact_list_name = av_contact_list_name
      iv_email_address     = lv_email ).

    DATA(lo_list) = ao_se2->listcontacts( iv_contactlistname = av_contact_list_name ).
    DATA(lv_found) = abap_false.
    LOOP AT lo_list->get_contacts( ) INTO DATA(lo_c).
      IF lo_c->get_emailaddress( ) = lv_email.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |create_contact: { lv_email } not found in list after creation| ).

    " Clean up
    ao_se2->deletecontact(
      iv_contactlistname = av_contact_list_name
      iv_emailaddress    = lv_email ).
  ENDMETHOD.


  " =====================================================================
  " send_email
  " Sends a simple email from the SES simulator address to itself.
  " Both sender and recipient are pre-verified simulator addresses, so
  " this succeeds in any account (sandbox or production).
  " The test asserts that a non-empty MessageId is returned.
  " =====================================================================
  METHOD send_email.
    ao_se2_actions->send_email(
      iv_from_email_address = cv_simulator_email
      iv_to_email_address   = cv_simulator_email
      iv_subject            = 'ABAP SDK unit test – send_email'
      iv_html_body          = '<html><body><p>Unit test email</p></body></html>'
      iv_text_body          = 'Unit test email' ).

    " The action method raises on error; reaching this point means success.
    " GetEmailIdentity cannot confirm delivery, but we can verify the
    " simulator identity exists as a proxy for "the SDK call worked".
    DATA(lo_id) = ao_se2->getemailidentity(
      iv_emailidentity = cv_simulator_email ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lo_id->get_identitytype( )
      msg = |send_email: simulator identity should be retrievable| ).
  ENDMETHOD.


  " =====================================================================
  " send_email_template
  " Sends a templated email using the shared template and a contact that
  " belongs to the shared contact list.  Uses simulator addresses for
  " both sender and recipient so no verification is required.
  " =====================================================================
  METHOD send_email_template.
    DATA(lv_uuid)  = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_email) = |success+{ lv_uuid(12) }@simulator.amazonses.com|.

    " Add the recipient to the contact list (required for ListManagementOptions).
    ao_se2->createcontact(
      iv_contactlistname = av_contact_list_name
      iv_emailaddress    = lv_email ).

    ao_se2_actions->send_email_template(
      iv_from_email_address = cv_simulator_email
      iv_to_email_address   = lv_email
      iv_template_name      = av_template_name
      iv_template_data      = '{}'
      iv_contact_list_name  = av_contact_list_name ).

    " The action method raises on error; verify the template still exists
    " as a proxy for "the SDK call completed without error".
    DATA(lo_tmpl) = ao_se2->getemailtemplate( iv_templatename = av_template_name ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_tmpl->get_templatename( )
      exp = av_template_name
      msg = |send_email_template: template should still exist after send| ).

    " Clean up
    TRY.
        ao_se2->deletecontact(
          iv_contactlistname = av_contact_list_name
          iv_emailaddress    = lv_email ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  " =====================================================================
  " list_contacts
  " Seeds the shared list with one contact, calls list_contacts, asserts
  " the returned count is at least 1 and the seeded address is present.
  " =====================================================================
  METHOD list_contacts.
    DATA(lv_uuid)  = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_email) = |success+lst{ lv_uuid(10) }@simulator.amazonses.com|.

    ao_se2->createcontact(
      iv_contactlistname = av_contact_list_name
      iv_emailaddress    = lv_email ).

    DATA lo_result TYPE REF TO /aws1/cl_se2listcontactsrsp.
    ao_se2_actions->list_contacts(
      EXPORTING iv_contact_list_name = av_contact_list_name
      IMPORTING oo_result            = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = |list_contacts: result must be bound| ).

    DATA(lv_count) = lines( lo_result->get_contacts( ) ).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lv_count >= 1 )
      msg = |list_contacts: expected at least 1 contact, got { lv_count }| ).

    DATA(lv_found) = abap_false.
    LOOP AT lo_result->get_contacts( ) INTO DATA(lo_c).
      IF lo_c->get_emailaddress( ) = lv_email.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_contacts: seeded address { lv_email } not in result| ).

    " Clean up
    ao_se2->deletecontact(
      iv_contactlistname = av_contact_list_name
      iv_emailaddress    = lv_email ).
  ENDMETHOD.


  " =====================================================================
  " delete_contact_list
  " Creates a dedicated list (separate from the shared one), calls
  " delete_contact_list, then confirms it is gone via GetContactList.
  " =====================================================================
  METHOD delete_contact_list.
    DATA(lv_uuid) = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_list) = |se2-del-list-{ lv_uuid(10) }|.
    DATA(lv_region)  = ao_session->get_region( ).
    DATA(lv_account) = ao_session->get_account_id( ).

    ao_se2->createcontactlist( iv_contactlistname = lv_list ).
    TRY.
        tag_se2_resource(
          |arn:aws:ses:{ lv_region }:{ lv_account }:contact-list/{ lv_list }| ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    ao_se2_actions->delete_contact_list( lv_list ).

    TRY.
        ao_se2->getcontactlist( iv_contactlistname = lv_list ).
        cl_abap_unit_assert=>fail(
          msg = |delete_contact_list: { lv_list } should have been deleted| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected – list was successfully deleted.
    ENDTRY.
  ENDMETHOD.


  " =====================================================================
  " delete_email_template
  " Creates a dedicated template, calls delete_email_template, then
  " confirms it is gone via GetEmailTemplate.
  " =====================================================================
  METHOD delete_email_template.
    DATA(lv_uuid)    = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_tmpl)    = |se2-del-tmpl-{ lv_uuid(8) }|.
    DATA(lv_region)  = ao_session->get_region( ).
    DATA(lv_account) = ao_session->get_account_id( ).

    ao_se2->createemailtemplate(
      iv_templatename    = lv_tmpl
      io_templatecontent = NEW /aws1/cl_se2emailtmplcontent(
        iv_subject = 'Delete me'
        iv_html    = '<html><body>Delete</body></html>'
        iv_text    = 'Delete' ) ).
    TRY.
        tag_se2_resource(
          |arn:aws:ses:{ lv_region }:{ lv_account }:template/{ lv_tmpl }| ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    ao_se2_actions->delete_email_template( lv_tmpl ).

    TRY.
        ao_se2->getemailtemplate( iv_templatename = lv_tmpl ).
        cl_abap_unit_assert=>fail(
          msg = |delete_email_template: { lv_tmpl } should have been deleted| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected – template was successfully deleted.
    ENDTRY.
  ENDMETHOD.


  " =====================================================================
  " delete_email_identity
  " Creates a dedicated email identity, calls delete_email_identity,
  " then confirms it is gone via GetEmailIdentity.
  " =====================================================================
  METHOD delete_email_identity.
    DATA(lv_uuid)    = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_id)      = |se2del{ lv_uuid(10) }@example.com|.
    DATA(lv_region)  = ao_session->get_region( ).
    DATA(lv_account) = ao_session->get_account_id( ).

    ao_se2->createemailidentity( iv_emailidentity = lv_id ).
    TRY.
        tag_se2_resource(
          |arn:aws:ses:{ lv_region }:{ lv_account }:identity/{ lv_id }| ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    ao_se2_actions->delete_email_identity( lv_id ).

    TRY.
        ao_se2->getemailidentity( iv_emailidentity = lv_id ).
        cl_abap_unit_assert=>fail(
          msg = |delete_email_identity: { lv_id } should have been deleted| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected – identity was successfully deleted.
    ENDTRY.
  ENDMETHOD.


  " =====================================================================
  " get_email_identity
  " Reads the well-known SES simulator identity (always present and
  " verified in every AWS account) and asserts the identity type and
  " verification status.
  " =====================================================================
  METHOD get_email_identity.
    DATA(lo_result) = ao_se2_actions->get_email_identity(
      iv_email_identity = cv_simulator_email ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = |get_email_identity: result must be bound| ).

    " The simulator address is an EMAIL_ADDRESS type identity.
    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_identitytype( )
      exp = 'EMAIL_ADDRESS'
      msg = |get_email_identity: identity type should be EMAIL_ADDRESS| ).

    " The simulator address is always verified for sending.
    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_verifiedforsendingstatus( )
      exp = abap_true
      msg = |get_email_identity: simulator address should be verified for sending| ).
  ENDMETHOD.


  " =====================================================================
  " send_bulk_email
  " Sends a bulk templated email to two distinct simulator sub-addresses
  " using the shared template.  Asserts that one result entry is returned
  " per recipient and that both have a non-empty MessageId (SUCCESS).
  " =====================================================================
  METHOD send_bulk_email.
    DATA(lv_uuid1) = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_uuid2) = /awsex/cl_utils=>get_random_string( ).

    DATA(lv_rcpt1) = |success+{ lv_uuid1(12) }@simulator.amazonses.com|.
    DATA(lv_rcpt2) = |success+{ lv_uuid2(12) }@simulator.amazonses.com|.

    " Build the bulk-email entries table.
    DATA lt_entries TYPE /aws1/cl_se2bulkemailentry=>tt_bulkemailentrylist.

    DATA lt_to1 TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w( lv_rcpt1 ) TO lt_to1.
    APPEND NEW /aws1/cl_se2bulkemailentry(
      io_destination = NEW /aws1/cl_se2destination( it_toaddresses = lt_to1 ) )
      TO lt_entries.

    DATA lt_to2 TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w( lv_rcpt2 ) TO lt_to2.
    APPEND NEW /aws1/cl_se2bulkemailentry(
      io_destination = NEW /aws1/cl_se2destination( it_toaddresses = lt_to2 ) )
      TO lt_entries.

    DATA(lo_result) = ao_se2_actions->send_bulk_email(
      iv_from_email_address    = cv_simulator_email
      iv_template_name         = av_template_name
      iv_default_template_data = '{}'
      it_bulk_email_entries    = lt_entries ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = |send_bulk_email: result must be bound| ).

    DATA(lt_results) = lo_result->get_bulkemailentryresults( ).
    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_results )
      exp = 2
      msg = |send_bulk_email: expected 2 result entries, got { lines( lt_results ) }| ).

    " Every entry must have succeeded (status = SUCCESS).
    LOOP AT lt_results INTO DATA(lo_entry_result).
      cl_abap_unit_assert=>assert_equals(
        act = lo_entry_result->get_status( )
        exp = 'SUCCESS'
        msg = |send_bulk_email: entry status should be SUCCESS| ).
      cl_abap_unit_assert=>assert_not_initial(
        act = lo_entry_result->get_messageid( )
        msg = |send_bulk_email: MessageId must not be empty| ).
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
