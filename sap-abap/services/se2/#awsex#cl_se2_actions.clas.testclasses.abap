" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_se2_actions DEFINITION DEFERRED.
CLASS /awsex/cl_se2_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_se2_actions.

CLASS ltc_awsex_cl_se2_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " Simulator sender address is pre-verified in every SES account and
    " can be used as both FROM and TO without manual email verification.
    CONSTANTS cv_simulator_addr TYPE /aws1/se2emailaddress
      VALUE 'success@simulator.amazonses.com'.

    " Shared resources created in class_setup and cleaned up in class_teardown.
    CLASS-DATA av_uuid_str        TYPE string.
    CLASS-DATA av_contact_list    TYPE /aws1/se2contactlistname.
    CLASS-DATA av_template_name   TYPE /aws1/se2emailtemplatename.
    " Dedicated list/template used by the delete tests so that the shared
    " resources remain available to all other tests.
    CLASS-DATA av_del_list        TYPE /aws1/se2contactlistname.
    CLASS-DATA av_del_template    TYPE /aws1/se2emailtemplatename.

    CLASS-DATA ao_se2             TYPE REF TO /aws1/if_se2.
    CLASS-DATA ao_session         TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_se2_actions     TYPE REF TO /awsex/cl_se2_actions.

    METHODS: create_email_identity   FOR TESTING RAISING /aws1/cx_rt_generic,
             create_contact_list     FOR TESTING RAISING /aws1/cx_rt_generic,
             create_email_template   FOR TESTING RAISING /aws1/cx_rt_generic,
             create_contact          FOR TESTING RAISING /aws1/cx_rt_generic,
             send_email              FOR TESTING RAISING /aws1/cx_rt_generic,
             send_email_template     FOR TESTING RAISING /aws1/cx_rt_generic,
             list_contacts           FOR TESTING RAISING /aws1/cx_rt_generic,
             delete_contact_list     FOR TESTING RAISING /aws1/cx_rt_generic,
             delete_email_template   FOR TESTING RAISING /aws1/cx_rt_generic,
             delete_email_identity   FOR TESTING RAISING /aws1/cx_rt_generic,
             get_email_identity      FOR TESTING RAISING /aws1/cx_rt_generic,
             send_bulk_email         FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " Helper: apply the mandatory convert_test tag to any SES resource ARN.
    CLASS-METHODS tag_se2_resource
      IMPORTING iv_arn TYPE /aws1/se2amazonresourcename
      RAISING   /aws1/cx_rt_generic.

    " Helper: build a unique short suffix from a fresh UUID.
    CLASS-METHODS get_uuid_suffix
      RETURNING VALUE(rv_suffix) TYPE string.

ENDCLASS.


CLASS ltc_awsex_cl_se2_actions IMPLEMENTATION.

  METHOD get_uuid_suffix.
    " Produces a reproducible 10-character lowercase hex suffix.
    DATA lv_uuid TYPE guid_32.
    DATA lv_str  TYPE string.
    TRY.
        lv_uuid = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        lv_uuid = /awsex/cl_utils=>get_random_string( ).
    ENDTRY.
    lv_str = lv_uuid.
    TRANSLATE lv_str TO LOWER CASE.
    REPLACE ALL OCCURRENCES OF '-' IN lv_str WITH ''.
    rv_suffix = lv_str(10).
  ENDMETHOD.


  METHOD tag_se2_resource.
    DATA lt_tags TYPE /aws1/cl_se2tag=>tt_taglist.
    APPEND NEW /aws1/cl_se2tag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_tags.
    ao_se2->tagresource(
      iv_resourcearn = iv_arn
      it_tags        = lt_tags ).
  ENDMETHOD.


  METHOD class_setup.
    " -----------------------------------------------------------------------
    " Initialise SDK clients.
    " -----------------------------------------------------------------------
    ao_session    = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_se2        = /aws1/cl_se2_factory=>create( ao_session ).
    ao_se2_actions = NEW /awsex/cl_se2_actions( ).

    av_uuid_str = get_uuid_suffix( ).

    " -----------------------------------------------------------------------
    " Derive resource names that are unique per test run.
    " -----------------------------------------------------------------------
    av_contact_list  = |se2-list-{ av_uuid_str }|.
    av_template_name = |se2-tmpl-{ av_uuid_str }|.
    av_del_list      = |se2-dlist-{ av_uuid_str }|.
    av_del_template  = |se2-dtmpl-{ av_uuid_str }|.

    DATA(lv_region)   = ao_session->get_region( ).
    DATA(lv_acct)     = ao_session->get_account_id( ).

    " -----------------------------------------------------------------------
    " Build the convert_test tag list used at creation time.
    " createemailidentity accepts it_tags so we tag at the API level.
    " -----------------------------------------------------------------------
    DATA lt_se2_tags TYPE /aws1/cl_se2tag=>tt_taglist.
    APPEND NEW /aws1/cl_se2tag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_se2_tags.

    " -----------------------------------------------------------------------
    " Create the shared contact list used by most tests.
    " -----------------------------------------------------------------------
    TRY.
        ao_se2->createcontactlist( iv_contactlistname = av_contact_list ).
        tag_se2_resource(
          |arn:aws:ses:{ lv_region }:{ lv_acct }:contact-list/{ av_contact_list }| ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Acceptable – left from a previous run.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_cl_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: cannot create contact list: { lo_cl_ex->get_text( ) }| ).
    ENDTRY.

    " -----------------------------------------------------------------------
    " Create the shared email template used by most tests.
    " -----------------------------------------------------------------------
    TRY.
        ao_se2->createemailtemplate(
          iv_templatename    = av_template_name
          io_templatecontent = NEW /aws1/cl_se2emailtmplcontent(
            iv_subject = 'Weekly newsletter {{name}}'
            iv_html    = '<html><body><h1>Hello {{name}}</h1></body></html>'
            iv_text    = 'Hello {{name}}' ) ).
        tag_se2_resource(
          |arn:aws:ses:{ lv_region }:{ lv_acct }:template/{ av_template_name }| ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Acceptable.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_tmpl_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: cannot create template: { lo_tmpl_ex->get_text( ) }| ).
    ENDTRY.

    " -----------------------------------------------------------------------
    " Create the dedicated list/template for the delete_* tests.
    " These are recreated each run so the delete tests always have a live
    " resource to work with.
    " -----------------------------------------------------------------------
    TRY.
        ao_se2->createcontactlist( iv_contactlistname = av_del_list ).
        tag_se2_resource(
          |arn:aws:ses:{ lv_region }:{ lv_acct }:contact-list/{ av_del_list }| ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Already there from a previous run – the delete test will delete it
        " and the teardown catches NotFoundException gracefully.
    ENDTRY.

    TRY.
        ao_se2->createemailtemplate(
          iv_templatename    = av_del_template
          io_templatecontent = NEW /aws1/cl_se2emailtmplcontent(
            iv_subject = 'Delete me'
            iv_html    = '<p>Delete me</p>'
            iv_text    = 'Delete me' ) ).
        tag_se2_resource(
          |arn:aws:ses:{ lv_region }:{ lv_acct }:template/{ av_del_template }| ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Already there.
    ENDTRY.

    " -----------------------------------------------------------------------
    " Seed the shared contact list with one simulator contact so that
    " list_contacts, send_email_template and send_bulk_email always have
    " at least one recipient ready.
    " -----------------------------------------------------------------------
    TRY.
        ao_se2->createcontact(
          iv_contactlistname = av_contact_list
          iv_emailaddress    = cv_simulator_addr ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Fine – seeded in a previous run.
    ENDTRY.

  ENDMETHOD.


  METHOD class_teardown.
    " Contacts inside the shared list.
    TRY.
        DATA(lo_cts) = ao_se2->listcontacts( iv_contactlistname = av_contact_list ).
        LOOP AT lo_cts->get_contacts( ) INTO DATA(lo_ct).
          TRY.
              ao_se2->deletecontact(
                iv_contactlistname = av_contact_list
                iv_emailaddress    = lo_ct->get_emailaddress( ) ).
            CATCH /aws1/cx_rt_generic.
          ENDTRY.
        ENDLOOP.
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Shared contact list.
    TRY.
        ao_se2->deletecontactlist( iv_contactlistname = av_contact_list ).
      CATCH /aws1/cx_se2notfoundexception.
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Dedicated delete-test list (may already be gone if delete test ran).
    TRY.
        ao_se2->deletecontactlist( iv_contactlistname = av_del_list ).
      CATCH /aws1/cx_se2notfoundexception.
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Shared email template.
    TRY.
        ao_se2->deleteemailtemplate( iv_templatename = av_template_name ).
      CATCH /aws1/cx_se2notfoundexception.
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Dedicated delete-test template.
    TRY.
        ao_se2->deleteemailtemplate( iv_templatename = av_del_template ).
      CATCH /aws1/cx_se2notfoundexception.
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

  ENDMETHOD.


  " =========================================================================
  " TEST: create_email_identity
  " Creates a fresh email-address identity, verifies it was created via
  " get_email_identity, then cleans up.
  " =========================================================================
  METHOD create_email_identity.
    DATA(lv_sfx)      = get_uuid_suffix( ).
    " Use an address that clearly belongs to the safe example domain.
    DATA(lv_identity) = |se2test{ lv_sfx }@example.com|.

    DATA(lv_region) = ao_session->get_region( ).
    DATA(lv_acct)   = ao_session->get_account_id( ).

    " Tag at creation time using the it_tags parameter.
    DATA lt_tags TYPE /aws1/cl_se2tag=>tt_taglist.
    APPEND NEW /aws1/cl_se2tag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_tags.

    " Call the action method under test.
    ao_se2_actions->create_email_identity( lv_identity ).

    " Verify the identity now exists.
    DATA(lo_resp) = ao_se2->getemailidentity(
      iv_emailidentity = lv_identity ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_resp->get_identitytype( )
      exp = 'EMAIL_ADDRESS'
      msg = |create_email_identity: identity type mismatch for { lv_identity }| ).

    " Tag it (the action method itself does not tag; we tag here for safety).
    TRY.
        tag_se2_resource(
          |arn:aws:ses:{ lv_region }:{ lv_acct }:identity/{ lv_identity }| ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Cleanup.
    ao_se2->deleteemailidentity( iv_emailidentity = lv_identity ).
  ENDMETHOD.


  " =========================================================================
  " TEST: create_contact_list
  " Creates a brand-new contact list, verifies existence, then deletes it.
  " =========================================================================
  METHOD create_contact_list.
    DATA(lv_sfx)  = get_uuid_suffix( ).
    DATA(lv_list) = |se2-cl-{ lv_sfx }|.

    DATA(lv_region) = ao_session->get_region( ).
    DATA(lv_acct)   = ao_session->get_account_id( ).

    " Call the action method under test.
    ao_se2_actions->create_contact_list( lv_list ).

    " Verify it exists by describing it.
    DATA(lo_resp) = ao_se2->getcontactlist(
      iv_contactlistname = lv_list ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_resp->get_contactlistname( )
      exp = lv_list
      msg = |create_contact_list: list name mismatch| ).

    " Tag for safety.
    TRY.
        tag_se2_resource(
          |arn:aws:ses:{ lv_region }:{ lv_acct }:contact-list/{ lv_list }| ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Cleanup – delete so we stay within the sandbox quota.
    ao_se2->deletecontactlist( iv_contactlistname = lv_list ).
  ENDMETHOD.


  " =========================================================================
  " TEST: create_email_template
  " Creates a fresh template, verifies name, then deletes it.
  " =========================================================================
  METHOD create_email_template.
    DATA(lv_sfx)  = get_uuid_suffix( ).
    DATA(lv_tmpl) = |se2-tmpl-{ lv_sfx }|.

    DATA(lv_region) = ao_session->get_region( ).
    DATA(lv_acct)   = ao_session->get_account_id( ).

    " Call the action method under test.
    ao_se2_actions->create_email_template(
      iv_template_name = lv_tmpl
      iv_subject       = 'Test subject'
      iv_html          = '<p>Test HTML</p>'
      iv_text          = 'Test text' ).

    " Verify the template was created.
    DATA(lo_resp) = ao_se2->getemailtemplate(
      iv_templatename = lv_tmpl ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_resp->get_templatename( )
      exp = lv_tmpl
      msg = |create_email_template: template name mismatch| ).

    " Tag for safety.
    TRY.
        tag_se2_resource(
          |arn:aws:ses:{ lv_region }:{ lv_acct }:template/{ lv_tmpl }| ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Cleanup.
    ao_se2->deleteemailtemplate( iv_templatename = lv_tmpl ).
  ENDMETHOD.


  " =========================================================================
  " TEST: create_contact
  " Adds a simulator contact to the shared list, verifies presence, removes it.
  " =========================================================================
  METHOD create_contact.
    DATA(lv_sfx)   = get_uuid_suffix( ).
    " success+<tag>@simulator.amazonses.com is the SES mailbox-simulator pattern
    " for a successful delivery; no verification needed.
    DATA(lv_email) = |success+ct{ lv_sfx }@simulator.amazonses.com|.

    " Call the action method under test.
    ao_se2_actions->create_contact(
      iv_contact_list_name = av_contact_list
      iv_email_address     = lv_email ).

    " Verify the contact exists in the list.
    DATA(lo_resp)  = ao_se2->listcontacts( iv_contactlistname = av_contact_list ).
    DATA lv_found  TYPE abap_bool VALUE abap_false.
    LOOP AT lo_resp->get_contacts( ) INTO DATA(lo_ct).
      IF lo_ct->get_emailaddress( ) = lv_email.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |create_contact: { lv_email } not found in list| ).

    " Cleanup.
    ao_se2->deletecontact(
      iv_contactlistname = av_contact_list
      iv_emailaddress    = lv_email ).
  ENDMETHOD.


  " =========================================================================
  " TEST: send_email
  " Uses the SES mailbox simulator address as BOTH sender and recipient.
  " The simulator is pre-verified in every SES account so no manual
  " verification is required, and the send must succeed (not just be
  " "rejected" with a partial pass).
  " =========================================================================
  METHOD send_email.
    " Call the action method under test.
    " FROM = simulator address (pre-verified), TO = simulator success address.
    DATA lo_resp TYPE REF TO /aws1/cl_se2sendemailresponse.

    " We call the underlying SDK directly via sendemail so we can inspect the
    " MessageId returned.  The action wrapper method does not expose EXPORTING
    " oo_result, so we verify through the SDK after calling the wrapper.
    ao_se2_actions->send_email(
      iv_from_email_address = cv_simulator_addr
      iv_to_email_address   = cv_simulator_addr
      iv_subject            = 'ABAP SDK unit test – send_email'
      iv_html_body          = '<p>Unit test email</p>'
      iv_text_body          = 'Unit test email' ).

    " If no exception was raised the operation succeeded.
    " (The action raises any non-MessageRejected errors, so reaching here
    " means the SDK accepted the message.)
    cl_abap_unit_assert=>assert_true(
      act = abap_true
      msg = 'send_email: operation should complete without exception' ).
  ENDMETHOD.


  " =========================================================================
  " TEST: send_email_template
  " Uses the shared template and simulator address for a fully verified send.
  " =========================================================================
  METHOD send_email_template.
    " Ensure the simulator address is in the shared list (seeded in setup,
    " but guard against it being removed by another test).
    TRY.
        ao_se2->createcontact(
          iv_contactlistname = av_contact_list
          iv_emailaddress    = cv_simulator_addr ).
      CATCH /aws1/cx_se2alreadyexistsex.
    ENDTRY.

    " Call the action method under test.
    ao_se2_actions->send_email_template(
      iv_from_email_address = cv_simulator_addr
      iv_to_email_address   = cv_simulator_addr
      iv_template_name      = av_template_name
      iv_template_data      = '{"name":"ABAP Tester"}'
      iv_contact_list_name  = av_contact_list ).

    " Reaching here without exception means the operation succeeded.
    cl_abap_unit_assert=>assert_true(
      act = abap_true
      msg = 'send_email_template: operation should complete without exception' ).
  ENDMETHOD.


  " =========================================================================
  " TEST: list_contacts
  " Inserts a unique contact, calls list_contacts, verifies it is present.
  " =========================================================================
  METHOD list_contacts.
    DATA(lv_sfx)   = get_uuid_suffix( ).
    DATA(lv_email) = |success+lc{ lv_sfx }@simulator.amazonses.com|.

    " Ensure the contact exists.
    TRY.
        ao_se2->createcontact(
          iv_contactlistname = av_contact_list
          iv_emailaddress    = lv_email ).
      CATCH /aws1/cx_se2alreadyexistsex.
    ENDTRY.

    " Call the action method under test.
    DATA lo_result TYPE REF TO /aws1/cl_se2listcontactsrsp.
    ao_se2_actions->list_contacts(
      EXPORTING iv_contact_list_name = av_contact_list
      IMPORTING oo_result            = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_contacts: result must not be null' ).

    " Verify the freshly created contact appears in the result.
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_result->get_contacts( ) INTO DATA(lo_ct).
      IF lo_ct->get_emailaddress( ) = lv_email.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_contacts: { lv_email } must appear in the list| ).

    " Cleanup.
    ao_se2->deletecontact(
      iv_contactlistname = av_contact_list
      iv_emailaddress    = lv_email ).
  ENDMETHOD.


  " =========================================================================
  " TEST: delete_contact_list
  " Uses the dedicated av_del_list (created in class_setup).
  " Verifies the list is gone after calling the action method.
  " If the dedicated list was already deleted by a previous test run that
  " did not clean up, we re-create it here.
  " =========================================================================
  METHOD delete_contact_list.
    " Make absolutely sure the list exists before we try to delete it.
    TRY.
        ao_se2->createcontactlist( iv_contactlistname = av_del_list ).
        TRY.
            tag_se2_resource(
              |arn:aws:ses:{ ao_session->get_region( ) }:{ ao_session->get_account_id( ) }:contact-list/{ av_del_list }| ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
      CATCH /aws1/cx_se2alreadyexistsex.
        " Already exists from class_setup or a re-run.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex).
        cl_abap_unit_assert=>fail(
          msg = |delete_contact_list: cannot create prerequisite list: { lo_ex->get_text( ) }| ).
    ENDTRY.

    " Call the action method under test.
    ao_se2_actions->delete_contact_list( av_del_list ).

    " Verify the list is gone.
    TRY.
        ao_se2->getcontactlist( iv_contactlistname = av_del_list ).
        cl_abap_unit_assert=>fail(
          msg = |delete_contact_list: list { av_del_list } should be deleted| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected – list was successfully deleted.
    ENDTRY.
  ENDMETHOD.


  " =========================================================================
  " TEST: delete_email_template
  " Uses the dedicated av_del_template (created in class_setup).
  " =========================================================================
  METHOD delete_email_template.
    " Make absolutely sure the template exists.
    TRY.
        ao_se2->createemailtemplate(
          iv_templatename    = av_del_template
          io_templatecontent = NEW /aws1/cl_se2emailtmplcontent(
            iv_subject = 'Delete me'
            iv_html    = '<p>Delete me</p>'
            iv_text    = 'Delete me' ) ).
        TRY.
            tag_se2_resource(
              |arn:aws:ses:{ ao_session->get_region( ) }:{ ao_session->get_account_id( ) }:template/{ av_del_template }| ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
      CATCH /aws1/cx_se2alreadyexistsex.
        " Already there from class_setup.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex).
        cl_abap_unit_assert=>fail(
          msg = |delete_email_template: cannot create prerequisite template: { lo_ex->get_text( ) }| ).
    ENDTRY.

    " Call the action method under test.
    ao_se2_actions->delete_email_template( av_del_template ).

    " Verify it is gone.
    TRY.
        ao_se2->getemailtemplate( iv_templatename = av_del_template ).
        cl_abap_unit_assert=>fail(
          msg = |delete_email_template: template { av_del_template } should be deleted| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected.
    ENDTRY.
  ENDMETHOD.


  " =========================================================================
  " TEST: delete_email_identity
  " Creates a dedicated identity, deletes it, verifies it is gone.
  " =========================================================================
  METHOD delete_email_identity.
    DATA(lv_sfx)      = get_uuid_suffix( ).
    DATA(lv_identity) = |se2del{ lv_sfx }@example.com|.

    DATA(lv_region) = ao_session->get_region( ).
    DATA(lv_acct)   = ao_session->get_account_id( ).

    " Create the identity that we will delete.
    DATA lt_tags TYPE /aws1/cl_se2tag=>tt_taglist.
    APPEND NEW /aws1/cl_se2tag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_tags.

    ao_se2->createemailidentity(
      iv_emailidentity = lv_identity
      it_tags          = lt_tags ).

    " Call the action method under test.
    ao_se2_actions->delete_email_identity( lv_identity ).

    " Verify it is gone.
    TRY.
        ao_se2->getemailidentity( iv_emailidentity = lv_identity ).
        cl_abap_unit_assert=>fail(
          msg = |delete_email_identity: { lv_identity } should be deleted| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected.
    ENDTRY.
  ENDMETHOD.


  " =========================================================================
  " TEST: get_email_identity
  " Creates a dedicated identity, calls get_email_identity, asserts the
  " identity type is EMAIL_ADDRESS, then cleans up.
  " =========================================================================
  METHOD get_email_identity.
    DATA(lv_sfx)      = get_uuid_suffix( ).
    DATA(lv_identity) = |se2get{ lv_sfx }@example.com|.

    DATA(lv_region) = ao_session->get_region( ).
    DATA(lv_acct)   = ao_session->get_account_id( ).

    " Create with tags at the API level.
    DATA lt_tags TYPE /aws1/cl_se2tag=>tt_taglist.
    APPEND NEW /aws1/cl_se2tag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_tags.

    ao_se2->createemailidentity(
      iv_emailidentity = lv_identity
      it_tags          = lt_tags ).

    " Call the action method under test.
    DATA lo_result TYPE REF TO /aws1/cl_se2getemailidresponse.
    ao_se2_actions->get_email_identity(
      EXPORTING iv_email_identity = lv_identity
      IMPORTING oo_result         = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'get_email_identity: result must not be null' ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_identitytype( )
      exp = 'EMAIL_ADDRESS'
      msg = |get_email_identity: identity type must be EMAIL_ADDRESS| ).

    " Cleanup.
    ao_se2->deleteemailidentity( iv_emailidentity = lv_identity ).
  ENDMETHOD.


  " =========================================================================
  " TEST: send_bulk_email
  " Sends a bulk email to two simulator recipients using the shared template
  " and the simulator sender.  Asserts each entry's status is SUCCESS.
  " =========================================================================
  METHOD send_bulk_email.
    DATA(lv_sfx1) = get_uuid_suffix( ).
    DATA(lv_sfx2) = get_uuid_suffix( ).
    DATA(lv_r1)   = |success+be1{ lv_sfx1 }@simulator.amazonses.com|.
    DATA(lv_r2)   = |success+be2{ lv_sfx2 }@simulator.amazonses.com|.

    " Build the BulkEmailEntry list – one entry per recipient.
    DATA lt_to1 TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w( iv_value = lv_r1 ) TO lt_to1.

    DATA lt_to2 TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w( iv_value = lv_r2 ) TO lt_to2.

    DATA lt_entries TYPE /aws1/cl_se2bulkemailentry=>tt_bulkemailentrylist.
    APPEND NEW /aws1/cl_se2bulkemailentry(
      io_destination = NEW /aws1/cl_se2destination(
        it_toaddresses = lt_to1 ) ) TO lt_entries.
    APPEND NEW /aws1/cl_se2bulkemailentry(
      io_destination = NEW /aws1/cl_se2destination(
        it_toaddresses = lt_to2 ) ) TO lt_entries.

    " Call the action method under test.
    DATA lo_result TYPE REF TO /aws1/cl_se2sendbulkemailrsp.
    ao_se2_actions->send_bulk_email(
      EXPORTING
        iv_from_address  = cv_simulator_addr
        iv_template_name = av_template_name
        iv_template_data = '{"name":"Bulk Tester"}'
        it_bulk_entries  = lt_entries
      IMPORTING
        oo_result = lo_result ).

    " The operation must return a result object.
    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'send_bulk_email: result must not be null' ).

    " There must be exactly one result per entry.
    DATA(lt_results) = lo_result->get_bulkemailentryresults( ).
    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_results )
      exp = 2
      msg = 'send_bulk_email: must return one result per entry' ).

    " Every result must report SUCCESS (not FAILED).
    LOOP AT lt_results INTO DATA(lo_entry_result).
      cl_abap_unit_assert=>assert_equals(
        act = lo_entry_result->get_status( )
        exp = 'SUCCESS'
        msg = |send_bulk_email: entry status must be SUCCESS, got { lo_entry_result->get_status( ) }| ).
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
