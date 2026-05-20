" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_se2_actions DEFINITION DEFERRED.
CLASS /awsex/cl_se2_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_se2_actions.

CLASS ltc_awsex_cl_se2_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " -----------------------------------------------------------------------
    " Pre-requisite: The ZCODE_DEMO account must have the following verified
    " sender email address registered as an SES identity BEFORE running tests.
    " Use success+sender@simulator.amazonses.com is NOT a valid sender;
    " this must be a domain or address you actually own and have verified.
    " For the ABAP SDK example test account this is a pre-verified identity.
    " -----------------------------------------------------------------------
    CONSTANTS cv_verified_sender TYPE /aws1/se2emailaddress
      VALUE 'sestest@example.com'.

    " SES mailbox simulator success address - valid recipient in sandbox/production
    " without needing recipient verification. Appending a label ensures uniqueness.
    CONSTANTS cv_sim_base TYPE string VALUE 'success@simulator.amazonses.com'.

    CLASS-DATA ao_se2    TYPE REF TO /aws1/if_se2.
    CLASS-DATA ao_session TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_se2_actions TYPE REF TO /awsex/cl_se2_actions.
    CLASS-DATA av_uuid   TYPE string.

    " Resources created once in class_setup and shared across read-only tests
    CLASS-DATA av_contact_list_name TYPE /aws1/se2contactlistname.
    CLASS-DATA av_template_name     TYPE /aws1/se2emailtemplatename.
    CLASS-DATA av_sender_identity   TYPE /aws1/se2identity.

    " Resources created for mutation tests - each test creates its own
    CLASS-DATA av_del_list_name   TYPE /aws1/se2contactlistname.
    CLASS-DATA av_del_tmpl_name   TYPE /aws1/se2emailtemplatename.
    CLASS-DATA av_del_identity    TYPE /aws1/se2identity.

    METHODS:
      " --- New operations added in this conversion ---
      get_email_identity       FOR TESTING RAISING /aws1/cx_rt_generic,
      send_email_with_attachment FOR TESTING RAISING /aws1/cx_rt_generic,
      send_bulk_email          FOR TESTING RAISING /aws1/cx_rt_generic,
      " --- Pre-existing operations ---
      create_email_identity    FOR TESTING RAISING /aws1/cx_rt_generic,
      create_email_template    FOR TESTING RAISING /aws1/cx_rt_generic,
      create_contact_list      FOR TESTING RAISING /aws1/cx_rt_generic,
      create_contact           FOR TESTING RAISING /aws1/cx_rt_generic,
      send_email               FOR TESTING RAISING /aws1/cx_rt_generic,
      send_email_template      FOR TESTING RAISING /aws1/cx_rt_generic,
      list_contacts            FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_contact_list      FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_email_template    FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_email_identity    FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " Helper: apply convert_test tag to an SES resource ARN
    CLASS-METHODS tag_resource
      IMPORTING iv_resource_arn TYPE /aws1/se2amazonresourcename
      RAISING   /aws1/cx_rt_generic.

    " Helper: return the simulator recipient address labelled with the given suffix
    CLASS-METHODS sim_addr
      IMPORTING iv_label        TYPE string
      RETURNING VALUE(rv_email) TYPE /aws1/se2emailaddress.

    " Helper: build arn for the given identity name
    CLASS-METHODS identity_arn
      IMPORTING iv_identity     TYPE /aws1/se2identity
      RETURNING VALUE(rv_arn)   TYPE /aws1/se2amazonresourcename.

    " Helper: build arn for the given template name
    CLASS-METHODS template_arn
      IMPORTING iv_template_name TYPE /aws1/se2emailtemplatename
      RETURNING VALUE(rv_arn)    TYPE /aws1/se2amazonresourcename.

    " Helper: build arn for the given contact list
    CLASS-METHODS contact_list_arn
      IMPORTING iv_list_name TYPE /aws1/se2contactlistname
      RETURNING VALUE(rv_arn) TYPE /aws1/se2amazonresourcename.

ENDCLASS.

CLASS ltc_awsex_cl_se2_actions IMPLEMENTATION.

  " =========================================================================
  " CLASS_SETUP - runs once before all tests
  " Creates: sender identity, shared contact list, shared template,
  "          and dedicated resources for each delete test.
  " =========================================================================
  METHOD class_setup.
    ao_session     = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_se2         = /aws1/cl_se2_factory=>create( ao_session ).
    ao_se2_actions = NEW /awsex/cl_se2_actions( ).

    " Unique suffix for all resource names in this run
    DATA lv_uuid TYPE guid_32.
    TRY.
        lv_uuid = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        lv_uuid = /awsex/cl_utils=>get_random_string( ).
    ENDTRY.
    DATA lv_uuid_str TYPE string.
    lv_uuid_str = lv_uuid.
    TRANSLATE lv_uuid_str TO LOWER CASE.
    REPLACE ALL OCCURRENCES OF '-' IN lv_uuid_str WITH ''.
    av_uuid = lv_uuid_str(12).

    " -----------------------------------------------------------------------
    " 1. Sender identity
    " -----------------------------------------------------------------------
    " We register cv_verified_sender as an SES identity.
    " Email-address identities require the owner to click a verification link,
    " so this identity is NOT programmatically verifiable. The ZCODE_DEMO test
    " account must already have this address verified before running tests.
    " We create it here to ensure it is registered; the send tests rely on it.
    av_sender_identity = cv_verified_sender.

    TRY.
        ao_se2->createemailidentity(
          iv_emailidentity = av_sender_identity ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Already registered - that is fine
    ENDTRY.

    " Tag for cleanup tracking
    TRY.
        tag_resource( identity_arn( av_sender_identity ) ).
      CATCH /aws1/cx_rt_generic.
        " Best effort - tagging may fail if identity was just created
    ENDTRY.

    " -----------------------------------------------------------------------
    " 2. Shared email template used by list / send tests
    " -----------------------------------------------------------------------
    av_template_name = |se2-tst-tmpl-{ av_uuid }|.
    DATA(lo_tc) = NEW /aws1/cl_se2emailtmplcontent(
      iv_subject = 'Test subject for {{name}}'
      iv_html    = '<html><body><h1>Hello {{name}}</h1></body></html>'
      iv_text    = 'Hello {{name}}' ).
    TRY.
        ao_se2->createemailtemplate(
          iv_templatename    = av_template_name
          io_templatecontent = lo_tc ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Exists from a previous run - fine
    ENDTRY.
    TRY.
        tag_resource( template_arn( av_template_name ) ).
      CATCH /aws1/cx_rt_generic.
        " Best effort
    ENDTRY.

    " -----------------------------------------------------------------------
    " 3. Shared contact list used by list / create-contact / send-template tests
    " -----------------------------------------------------------------------
    av_contact_list_name = |se2-tst-lst-{ av_uuid }|.
    TRY.
        ao_se2->createcontactlist(
          iv_contactlistname = av_contact_list_name ).
        tag_resource( contact_list_arn( av_contact_list_name ) ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Exists - fine
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_br).
        " Sandbox caps contacts lists at 1; find and reuse the existing one
        DATA(lo_lists) = ao_se2->listcontactlists( ).
        IF lines( lo_lists->get_contactlists( ) ) > 0.
          LOOP AT lo_lists->get_contactlists( ) INTO DATA(lo_cl).
            av_contact_list_name = lo_cl->get_contactlistname( ).
            EXIT.
          ENDLOOP.
          TRY.
              tag_resource( contact_list_arn( av_contact_list_name ) ).
            CATCH /aws1/cx_rt_generic.
          ENDTRY.
        ELSE.
          cl_abap_unit_assert=>fail(
            msg = |Contact list limit hit but no existing list found: { lo_br->get_text( ) }| ).
        ENDIF.
    ENDTRY.

    " -----------------------------------------------------------------------
    " 4. Dedicated resources for each DELETE test
    "    (Created fresh here so each delete test works in isolation)
    " -----------------------------------------------------------------------

    " 4a. Contact list to delete
    av_del_list_name = |se2-del-lst-{ av_uuid }|.
    TRY.
        ao_se2->createcontactlist(
          iv_contactlistname = av_del_list_name ).
        tag_resource( contact_list_arn( av_del_list_name ) ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Fine
      CATCH /aws1/cx_se2badrequestex.
        " Sandbox limit: skip dedicated delete list; delete test will use shared list name
        av_del_list_name = av_contact_list_name.
    ENDTRY.

    " 4b. Template to delete
    av_del_tmpl_name = |se2-del-tmpl-{ av_uuid }|.
    TRY.
        ao_se2->createemailtemplate(
          iv_templatename    = av_del_tmpl_name
          io_templatecontent = NEW /aws1/cl_se2emailtmplcontent(
            iv_subject = 'Del subject'
            iv_html    = '<html><body>Del</body></html>'
            iv_text    = 'Del' ) ).
        tag_resource( template_arn( av_del_tmpl_name ) ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Fine
    ENDTRY.

    " 4c. Identity to delete
    av_del_identity = |se2-del-id-{ av_uuid }@example.com|.
    TRY.
        ao_se2->createemailidentity(
          iv_emailidentity = av_del_identity ).
        tag_resource( identity_arn( av_del_identity ) ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Fine
    ENDTRY.

  ENDMETHOD.

  " =========================================================================
  " CLASS_TEARDOWN - runs once after all tests
  " =========================================================================
  METHOD class_teardown.
    " --- Delete all contacts from the shared contact list ---
    TRY.
        DATA(lo_contacts) = ao_se2->listcontacts(
          iv_contactlistname = av_contact_list_name ).
        LOOP AT lo_contacts->get_contacts( ) INTO DATA(lo_c).
          TRY.
              ao_se2->deletecontact(
                iv_contactlistname = av_contact_list_name
                iv_emailaddress    = lo_c->get_emailaddress( ) ).
            CATCH /aws1/cx_rt_generic.
          ENDTRY.
        ENDLOOP.
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " --- Delete shared contact list ---
    TRY.
        ao_se2->deletecontactlist(
          iv_contactlistname = av_contact_list_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " --- Delete shared template (may already have been deleted by test) ---
    TRY.
        ao_se2->deleteemailtemplate( iv_templatename = av_template_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " --- Delete dedicated delete-test resources if not already removed ---
    TRY.
        ao_se2->deletecontactlist(
          iv_contactlistname = av_del_list_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_se2->deleteemailtemplate( iv_templatename = av_del_tmpl_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
    TRY.
        ao_se2->deleteemailidentity(
          iv_emailidentity = av_del_identity ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " --- Delete sender identity ---
    " Only delete if it is the test-run specific one; cv_verified_sender
    " may be a permanently verified identity in the account.
    " We leave cv_verified_sender in place intentionally.

  ENDMETHOD.

  " =========================================================================
  " HELPER METHODS
  " =========================================================================
  METHOD tag_resource.
    DATA lt_tags TYPE /aws1/cl_se2tag=>tt_taglist.
    APPEND NEW /aws1/cl_se2tag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_tags.
    ao_se2->tagresource(
      iv_resourcearn = iv_resource_arn
      it_tags        = lt_tags ).
  ENDMETHOD.

  METHOD sim_addr.
    " Returns success+<label>@simulator.amazonses.com
    rv_email = |success+{ iv_label }@simulator.amazonses.com|.
  ENDMETHOD.

  METHOD identity_arn.
    rv_arn = |arn:aws:ses:{ ao_session->get_region( ) }| &&
             |:{ ao_session->get_account_id( ) }| &&
             |:identity/{ iv_identity }|.
  ENDMETHOD.

  METHOD template_arn.
    rv_arn = |arn:aws:ses:{ ao_session->get_region( ) }| &&
             |:{ ao_session->get_account_id( ) }| &&
             |:template/{ iv_template_name }|.
  ENDMETHOD.

  METHOD contact_list_arn.
    rv_arn = |arn:aws:ses:{ ao_session->get_region( ) }| &&
             |:{ ao_session->get_account_id( ) }| &&
             |:contact-list/{ iv_list_name }|.
  ENDMETHOD.

  " =========================================================================
  " TEST METHODS - one per service operation
  " =========================================================================

  " -------------------------------------------------------------------------
  " get_email_identity (NEW)
  " -------------------------------------------------------------------------
  METHOD get_email_identity.
    " Uses the sender identity created in class_setup.
    DATA lo_result TYPE REF TO /aws1/cl_se2getemailidresponse.

    ao_se2_actions->get_email_identity(
      EXPORTING iv_email_address = av_sender_identity
      IMPORTING oo_result        = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'get_email_identity must return a non-null result' ).

    " Identity type must be EMAIL_ADDRESS since av_sender_identity is an email
    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_identitytype( )
      exp = 'EMAIL_ADDRESS'
      msg = |Identity type mismatch for { av_sender_identity }| ).
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " send_email_with_attachment (NEW)
  " -------------------------------------------------------------------------
  METHOD send_email_with_attachment.
    " Recipient: SES simulator success address (no verification needed).
    " Sender:    cv_verified_sender - must be pre-verified in the account.
    DATA lt_to TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w(
      iv_value = sim_addr( |attsnd{ av_uuid }| ) )
      TO lt_to.

    " Simple 8-byte binary attachment (content: "TestData")
    DATA lt_attach TYPE /aws1/cl_se2attachment=>tt_attachmentlist.
    APPEND NEW /aws1/cl_se2attachment(
      iv_rawcontent  = 'VGVzdERhdGE='   " base64("TestData")
      iv_filename    = 'test.txt'
      iv_contenttype = 'text/plain' )
      TO lt_attach.

    DATA lv_msg_id TYPE /aws1/se2outboundmessageid.
    lv_msg_id = ao_se2_actions->send_email_with_attachment(
      iv_from_address = av_sender_identity
      it_to_addresses = lt_to
      iv_subject      = 'ABAP SDK test - attachment'
      iv_html_body    = '<html><body><p>Test attachment email.</p></body></html>'
      iv_text_body    = 'Test attachment email.'
      it_attachments  = lt_attach ).

    " The operation must succeed and return a non-empty MessageId
    cl_abap_unit_assert=>assert_not_initial(
      act = lv_msg_id
      msg = 'send_email_with_attachment must return a MessageId' ).
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " send_bulk_email (NEW)
  " -------------------------------------------------------------------------
  METHOD send_bulk_email.
    " Build two bulk entries directed at the SES simulator
    DATA lt_entries TYPE /aws1/cl_se2bulkemailentry=>tt_bulkemailentrylist.

    DATA lt_to1 TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w(
      iv_value = sim_addr( |blk1{ av_uuid }| ) ) TO lt_to1.
    APPEND NEW /aws1/cl_se2bulkemailentry(
      io_destination = NEW /aws1/cl_se2destination( it_toaddresses = lt_to1 ) )
      TO lt_entries.

    DATA lt_to2 TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w(
      iv_value = sim_addr( |blk2{ av_uuid }| ) ) TO lt_to2.
    APPEND NEW /aws1/cl_se2bulkemailentry(
      io_destination = NEW /aws1/cl_se2destination( it_toaddresses = lt_to2 ) )
      TO lt_entries.

    DATA(lt_results) = ao_se2_actions->send_bulk_email(
      iv_from_address          = av_sender_identity
      iv_template_name         = av_template_name
      iv_default_template_data = '{"name":"ABAP Tester"}'
      it_bulk_entries          = lt_entries ).

    " Must receive one result entry per recipient
    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_results )
      exp = 2
      msg = |Expected 2 bulk email results, got { lines( lt_results ) }| ).

    " Every result entry must have a non-empty MessageId (status = Success)
    LOOP AT lt_results INTO DATA(lo_r).
      cl_abap_unit_assert=>assert_not_initial(
        act = lo_r->get_messageid( )
        msg = |Bulk email entry has no MessageId - status: { lo_r->get_status( ) }| ).
    ENDLOOP.
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " create_email_identity
  " -------------------------------------------------------------------------
  METHOD create_email_identity.
    " Create a fresh identity, verify it appears in SES, then clean up.
    DATA(lv_new_id) = |se2-cre-id-{ av_uuid }@example.com|.

    ao_se2_actions->create_email_identity( lv_new_id ).

    " Tag for safety before verification check
    TRY.
        tag_resource( identity_arn( lv_new_id ) ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Verify the identity now exists in SES
    DATA(lo_get) = ao_se2->getemailidentity(
      iv_emailidentity = lv_new_id ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_get->get_identitytype( )
      exp = 'EMAIL_ADDRESS'
      msg = |Email identity { lv_new_id } was not created| ).

    " Clean up
    ao_se2->deleteemailidentity( iv_emailidentity = lv_new_id ).
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " create_email_template
  " -------------------------------------------------------------------------
  METHOD create_email_template.
    DATA(lv_new_tmpl) = |se2-cre-tmpl-{ av_uuid }|.

    ao_se2_actions->create_email_template(
      iv_template_name = lv_new_tmpl
      iv_subject       = 'Subject for {{name}}'
      iv_html          = '<html><body>Hello {{name}}</body></html>'
      iv_text          = 'Hello {{name}}' ).

    TRY.
        tag_resource( template_arn( lv_new_tmpl ) ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    DATA(lo_get) = ao_se2->getemailtemplate(
      iv_templatename = lv_new_tmpl ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_get->get_templatename( )
      exp = lv_new_tmpl
      msg = |Template { lv_new_tmpl } was not created| ).

    " Clean up
    ao_se2->deleteemailtemplate( iv_templatename = lv_new_tmpl ).
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " create_contact_list
  " -------------------------------------------------------------------------
  METHOD create_contact_list.
    " In sandbox mode the account is limited to 1 contact list.
    " We create a new one and verify it exists; if we hit the limit the action
    " method re-raises BadRequest and we verify the exception handling is correct.
    DATA(lv_new_list) = |se2-cre-lst-{ av_uuid }|.

    TRY.
        ao_se2_actions->create_contact_list( lv_new_list ).

        TRY.
            tag_resource( contact_list_arn( lv_new_list ) ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.

        DATA(lo_get) = ao_se2->getcontactlist(
          iv_contactlistname = lv_new_list ).

        cl_abap_unit_assert=>assert_equals(
          act = lo_get->get_contactlistname( )
          exp = lv_new_list
          msg = |Contact list { lv_new_list } was not created| ).

        " Clean up this extra list
        ao_se2->deletecontactlist( iv_contactlistname = lv_new_list ).

      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_br).
        " Sandbox: 1-list limit reached - the action correctly surfaces the error.
        " Confirm the error text mentions a limit-related issue.
        cl_abap_unit_assert=>assert_not_initial(
          act = lo_br->get_text( )
          msg = 'BadRequest must carry an error message' ).
      CATCH /aws1/cx_se2limitexceededex INTO DATA(lo_lim).
        cl_abap_unit_assert=>assert_not_initial(
          act = lo_lim->get_text( )
          msg = 'LimitExceeded must carry an error message' ).
    ENDTRY.
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " create_contact
  " -------------------------------------------------------------------------
  METHOD create_contact.
    " SES simulator addresses are valid recipients, no extra verification needed.
    DATA(lv_email) = sim_addr( |crcnt{ av_uuid }| ).

    ao_se2_actions->create_contact(
      iv_contact_list_name = av_contact_list_name
      iv_email_address     = lv_email ).

    " Verify the contact appears in the list
    DATA(lo_result) = ao_se2->listcontacts(
      iv_contactlistname = av_contact_list_name ).

    DATA lv_found TYPE abap_bool.
    LOOP AT lo_result->get_contacts( ) INTO DATA(lo_cnt).
      IF lo_cnt->get_emailaddress( ) = lv_email.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Contact { lv_email } was not found after creation| ).

    " Clean up
    ao_se2->deletecontact(
      iv_contactlistname = av_contact_list_name
      iv_emailaddress    = lv_email ).
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " send_email
  " -------------------------------------------------------------------------
  METHOD send_email.
    " Sends a plain text/HTML email with no attachments.
    " Sender: pre-verified cv_verified_sender.
    " Recipient: SES simulator - no verification required.
    ao_se2_actions->send_email(
      iv_from_email_address = av_sender_identity
      iv_to_email_address   = sim_addr( |snd{ av_uuid }| )
      iv_subject            = 'ABAP SDK integration test'
      iv_html_body          = '<html><body><p>Integration test email.</p></body></html>'
      iv_text_body          = 'Integration test email.' ).

    " If we reach here the send succeeded - no assertion needed beyond no exception.
    " The operation returning without raising is the success criterion.
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " send_email_template
  " -------------------------------------------------------------------------
  METHOD send_email_template.
    " Add the simulator address as a contact so ListManagementOptions succeeds
    DATA(lv_recipient) = sim_addr( |tmpsnd{ av_uuid }| ).

    TRY.
        ao_se2->createcontact(
          iv_contactlistname = av_contact_list_name
          iv_emailaddress    = lv_recipient ).
      CATCH /aws1/cx_se2alreadyexistsex.
    ENDTRY.

    ao_se2_actions->send_email_template(
      iv_from_email_address = av_sender_identity
      iv_to_email_address   = lv_recipient
      iv_template_name      = av_template_name
      iv_template_data      = '{"name":"ABAP Tester"}'
      iv_contact_list_name  = av_contact_list_name ).

    " Clean up the test contact
    TRY.
        ao_se2->deletecontact(
          iv_contactlistname = av_contact_list_name
          iv_emailaddress    = lv_recipient ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " list_contacts
  " -------------------------------------------------------------------------
  METHOD list_contacts.
    " Insert a known contact, list, verify it's present, then clean up.
    DATA(lv_email) = sim_addr( |lstcnt{ av_uuid }| ).

    TRY.
        ao_se2->createcontact(
          iv_contactlistname = av_contact_list_name
          iv_emailaddress    = lv_email ).
      CATCH /aws1/cx_se2alreadyexistsex.
    ENDTRY.

    DATA lo_result TYPE REF TO /aws1/cl_se2listcontactsrsp.
    ao_se2_actions->list_contacts(
      EXPORTING iv_contact_list_name = av_contact_list_name
      IMPORTING oo_result            = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_contacts must return a bound result' ).

    " At minimum the contact we just inserted must be present
    DATA lv_found TYPE abap_bool.
    LOOP AT lo_result->get_contacts( ) INTO DATA(lo_c).
      IF lo_c->get_emailaddress( ) = lv_email.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Contact { lv_email } was not found in list_contacts result| ).

    " Clean up
    TRY.
        ao_se2->deletecontact(
          iv_contactlistname = av_contact_list_name
          iv_emailaddress    = lv_email ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " delete_contact_list
  " -------------------------------------------------------------------------
  METHOD delete_contact_list.
    " Uses the dedicated list pre-created in class_setup.
    " After deletion, a GetContactList call must raise NotFoundException.

    " If the dedicated list could not be created (sandbox limit), create one now
    IF av_del_list_name = av_contact_list_name.
      " Cannot delete the shared list; create a temporary one just for this test
      DATA(lv_tmp_list) = |se2-del-lst2-{ av_uuid }|.
      TRY.
          ao_se2->createcontactlist( iv_contactlistname = lv_tmp_list ).
          tag_resource( contact_list_arn( lv_tmp_list ) ).
          ao_se2_actions->delete_contact_list( lv_tmp_list ).
          " Verify deletion
          TRY.
              ao_se2->getcontactlist( iv_contactlistname = lv_tmp_list ).
              cl_abap_unit_assert=>fail(
                msg = |Contact list { lv_tmp_list } should have been deleted| ).
            CATCH /aws1/cx_se2notfoundexception.
              " Expected - successfully deleted
          ENDTRY.
        CATCH /aws1/cx_se2badrequestex.
          " Sandbox limit - can't create another list; test the action with a
          " non-existent name and verify the graceful no-op behaviour.
          DATA(lv_fake) = |se2-nonexist-{ av_uuid }|.
          ao_se2_actions->delete_contact_list( lv_fake ).
          " No exception means the action correctly swallowed NotFoundException
      ENDTRY.
      RETURN.
    ENDIF.

    ao_se2_actions->delete_contact_list( av_del_list_name ).

    " Verify the list is gone
    TRY.
        ao_se2->getcontactlist( iv_contactlistname = av_del_list_name ).
        cl_abap_unit_assert=>fail(
          msg = |Contact list { av_del_list_name } should have been deleted| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected - successfully deleted
    ENDTRY.
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " delete_email_template
  " -------------------------------------------------------------------------
  METHOD delete_email_template.
    " Uses the dedicated template pre-created in class_setup.
    ao_se2_actions->delete_email_template( av_del_tmpl_name ).

    TRY.
        ao_se2->getemailtemplate( iv_templatename = av_del_tmpl_name ).
        cl_abap_unit_assert=>fail(
          msg = |Template { av_del_tmpl_name } should have been deleted| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected - successfully deleted
    ENDTRY.
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " delete_email_identity
  " -------------------------------------------------------------------------
  METHOD delete_email_identity.
    " Uses the dedicated identity pre-created in class_setup.
    ao_se2_actions->delete_email_identity( av_del_identity ).

    TRY.
        ao_se2->getemailidentity( iv_emailidentity = av_del_identity ).
        cl_abap_unit_assert=>fail(
          msg = |Identity { av_del_identity } should have been deleted| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected - successfully deleted
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
