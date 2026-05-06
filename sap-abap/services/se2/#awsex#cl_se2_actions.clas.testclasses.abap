" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_se2_actions DEFINITION DEFERRED.
CLASS /awsex/cl_se2_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_se2_actions.

CLASS ltc_awsex_cl_se2_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " The SES mailbox simulator SUCCESS address is pre-verified in every SES
    " account and can be used as FROM and TO without any manual verification.
    CONSTANTS cv_sim_addr TYPE /aws1/se2emailaddress
      VALUE 'success@simulator.amazonses.com'.

    " SES sandbox hard limit: 1 contact list per account.
    " av_contact_list holds the name of whichever list we are using this run.
    " It is either the one we create or the one that already exists.
    CLASS-DATA av_contact_list  TYPE /aws1/se2contactlistname.
    CLASS-DATA av_template_name TYPE /aws1/se2emailtemplatename.
    CLASS-DATA av_del_template  TYPE /aws1/se2emailtemplatename.

    CLASS-DATA ao_se2           TYPE REF TO /aws1/if_se2.
    CLASS-DATA ao_session       TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_se2_actions   TYPE REF TO /awsex/cl_se2_actions.

    METHODS: create_email_identity FOR TESTING RAISING /aws1/cx_rt_generic,
             create_contact_list   FOR TESTING RAISING /aws1/cx_rt_generic,
             create_email_template FOR TESTING RAISING /aws1/cx_rt_generic,
             create_contact        FOR TESTING RAISING /aws1/cx_rt_generic,
             send_email            FOR TESTING RAISING /aws1/cx_rt_generic,
             send_email_template   FOR TESTING RAISING /aws1/cx_rt_generic,
             list_contacts         FOR TESTING RAISING /aws1/cx_rt_generic,
             delete_contact_list   FOR TESTING RAISING /aws1/cx_rt_generic,
             delete_email_template FOR TESTING RAISING /aws1/cx_rt_generic,
             delete_email_identity FOR TESTING RAISING /aws1/cx_rt_generic,
             get_email_identity    FOR TESTING RAISING /aws1/cx_rt_generic,
             send_bulk_email       FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " Tag a SES resource ARN with convert_test=true.
    CLASS-METHODS tag_se2_resource
      IMPORTING iv_arn TYPE /aws1/se2amazonresourcename
      RAISING   /aws1/cx_rt_generic.

    " Produce a 10-char lowercase hex suffix from a fresh UUID.
    CLASS-METHODS uuid_suffix
      RETURNING VALUE(rv_s) TYPE string.

    " Ensure av_contact_list exists and is seeded with cv_sim_addr.
    " Handles the 1-list-per-account limit by reusing any existing list
    " rather than trying to create a second one.
    CLASS-METHODS ensure_contact_list RAISING /aws1/cx_rt_generic.

ENDCLASS.


CLASS ltc_awsex_cl_se2_actions IMPLEMENTATION.

  METHOD uuid_suffix.
    DATA lv_uuid TYPE guid_32.
    DATA lv_s    TYPE string.
    TRY.
        lv_uuid = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        lv_uuid = /awsex/cl_utils=>get_random_string( ).
    ENDTRY.
    lv_s = lv_uuid.
    TRANSLATE lv_s TO LOWER CASE.
    REPLACE ALL OCCURRENCES OF '-' IN lv_s WITH ''.
    rv_s = lv_s(10).
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


  METHOD ensure_contact_list.
    " ---------------------------------------------------------------------------
    " Strategy: SES sandbox allows exactly 1 contact list per account.
    "
    " 1. Try to create av_contact_list by name.
    "    a. If it succeeds – tag it and seed the simulator contact.
    "    b. If AlreadyExistsException – it already exists with our name; just
    "       seed the contact.
    "    c. If BadRequestException ("maximum of 1 list") – a DIFFERENT list
    "       exists.  Use ListContactLists to discover its name, adopt it as
    "       av_contact_list, tag it, and seed the simulator contact.
    " ---------------------------------------------------------------------------
    DATA(lv_region) = ao_session->get_region( ).
    DATA(lv_acct)   = ao_session->get_account_id( ).

    TRY.
        ao_se2->createcontactlist( iv_contactlistname = av_contact_list ).
        " Successfully created our named list – tag it.
        TRY.
            tag_se2_resource(
              |arn:aws:ses:{ lv_region }:{ lv_acct }:contact-list/{ av_contact_list }| ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.

      CATCH /aws1/cx_se2alreadyexistsex.
        " Our named list already exists – nothing extra to do.

      CATCH /aws1/cx_se2badrequestex.
        " A different list already occupies the single slot.
        " Discover its name and adopt it.
        DATA(lo_lists) = ao_se2->listcontactlists( ).
        DATA(lt_lists) = lo_lists->get_contactlists( ).
        IF lines( lt_lists ) = 0.
          " Should not happen, but fail loudly if it does.
          cl_abap_unit_assert=>fail(
            msg = 'ensure_contact_list: BadRequestException but no lists found' ).
        ENDIF.
        " Adopt the first (and only) existing list.
        READ TABLE lt_lists INDEX 1 INTO DATA(lo_existing_list).
        av_contact_list = lo_existing_list->get_contactlistname( ).
        " Tag the adopted list.
        TRY.
            tag_se2_resource(
              |arn:aws:ses:{ lv_region }:{ lv_acct }:contact-list/{ av_contact_list }| ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
    ENDTRY.

    " Seed the simulator address so send tests always have a ready recipient.
    TRY.
        ao_se2->createcontact(
          iv_contactlistname = av_contact_list
          iv_emailaddress    = cv_sim_addr ).
      CATCH /aws1/cx_se2alreadyexistsex.
    ENDTRY.
  ENDMETHOD.


  METHOD class_setup.
    ao_session     = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_se2         = /aws1/cl_se2_factory=>create( ao_session ).
    ao_se2_actions = NEW /awsex/cl_se2_actions( ).

    DATA(lv_sfx)    = uuid_suffix( ).
    DATA(lv_region) = ao_session->get_region( ).
    DATA(lv_acct)   = ao_session->get_account_id( ).

    " Desired names for this run – may be overridden by ensure_contact_list
    " if an existing list is adopted.
    av_contact_list  = |se2-list-{ lv_sfx }|.
    av_template_name = |se2-tmpl-{ lv_sfx }|.
    av_del_template  = |se2-dtpl-{ lv_sfx }|.

    " -----------------------------------------------------------------------
    " Contact list (1-per-account limit handled inside ensure_contact_list).
    " -----------------------------------------------------------------------
    ensure_contact_list( ).

    " -----------------------------------------------------------------------
    " Shared email template for send_email_template / send_bulk_email.
    " -----------------------------------------------------------------------
    TRY.
        ao_se2->createemailtemplate(
          iv_templatename    = av_template_name
          io_templatecontent = NEW /aws1/cl_se2emailtmplcontent(
            iv_subject = 'Newsletter {{name}}'
            iv_html    = '<html><body><p>Hello {{name}}</p></body></html>'
            iv_text    = 'Hello {{name}}' ) ).
        TRY.
            tag_se2_resource(
              |arn:aws:ses:{ lv_region }:{ lv_acct }:template/{ av_template_name }| ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
      CATCH /aws1/cx_se2alreadyexistsex.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_tmpl_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: cannot create shared template: { lo_tmpl_ex->get_text( ) }| ).
    ENDTRY.

    " -----------------------------------------------------------------------
    " Dedicated template for delete_email_template test.
    " -----------------------------------------------------------------------
    TRY.
        ao_se2->createemailtemplate(
          iv_templatename    = av_del_template
          io_templatecontent = NEW /aws1/cl_se2emailtmplcontent(
            iv_subject = 'Delete me'
            iv_html    = '<p>Delete me</p>'
            iv_text    = 'Delete me' ) ).
        TRY.
            tag_se2_resource(
              |arn:aws:ses:{ lv_region }:{ lv_acct }:template/{ av_del_template }| ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
      CATCH /aws1/cx_se2alreadyexistsex.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_dtpl_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: cannot create delete-template: { lo_dtpl_ex->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.


  METHOD class_teardown.
    " Remove all contacts then delete the shared list.
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

    TRY.
        ao_se2->deletecontactlist( iv_contactlistname = av_contact_list ).
      CATCH /aws1/cx_se2notfoundexception.
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    TRY.
        ao_se2->deleteemailtemplate( iv_templatename = av_template_name ).
      CATCH /aws1/cx_se2notfoundexception.
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    TRY.
        ao_se2->deleteemailtemplate( iv_templatename = av_del_template ).
      CATCH /aws1/cx_se2notfoundexception.
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  " =========================================================================
  " TEST: create_email_identity
  " =========================================================================
  METHOD create_email_identity.
    DATA(lv_id) = |se2tst{ uuid_suffix( ) }@example.com|.

    ao_se2_actions->create_email_identity( lv_id ).

    DATA(lo_resp) = ao_se2->getemailidentity( iv_emailidentity = lv_id ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_resp->get_identitytype( )
      exp = 'EMAIL_ADDRESS'
      msg = |create_email_identity: type mismatch for { lv_id }| ).

    TRY.
        tag_se2_resource(
          |arn:aws:ses:{ ao_session->get_region( ) }:{ ao_session->get_account_id( ) }:identity/{ lv_id }| ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    ao_se2->deleteemailidentity( iv_emailidentity = lv_id ).
  ENDMETHOD.


  " =========================================================================
  " TEST: create_contact_list
  " SES sandbox: 1 list per account.
  " Strategy:
  "   1. Delete the shared list (freeing the single slot).
  "   2. Call the action under test with a fresh name.
  "   3. Verify the new list exists.
  "   4. Delete it.
  "   5. Restore the shared list via ensure_contact_list.
  " =========================================================================
  METHOD create_contact_list.
    " Step 1 – clear all contacts then delete the shared list.
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
    TRY.
        ao_se2->deletecontactlist( iv_contactlistname = av_contact_list ).
      CATCH /aws1/cx_se2notfoundexception.
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Step 2 – call the action method under test.
    DATA(lv_new_list) = |se2-cl-{ uuid_suffix( ) }|.
    ao_se2_actions->create_contact_list( lv_new_list ).

    " Step 3 – verify the new list was created.
    DATA(lo_resp) = ao_se2->getcontactlist( iv_contactlistname = lv_new_list ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_resp->get_contactlistname( )
      exp = lv_new_list
      msg = 'create_contact_list: list name mismatch' ).

    TRY.
        tag_se2_resource(
          |arn:aws:ses:{ ao_session->get_region( ) }:{ ao_session->get_account_id( ) }:contact-list/{ lv_new_list }| ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Step 4 – delete the newly created list.
    ao_se2->deletecontactlist( iv_contactlistname = lv_new_list ).

    " Step 5 – restore the shared list for the remaining tests.
    ensure_contact_list( ).
  ENDMETHOD.


  " =========================================================================
  " TEST: create_email_template
  " =========================================================================
  METHOD create_email_template.
    DATA(lv_tmpl) = |se2-tmpl-{ uuid_suffix( ) }|.

    ao_se2_actions->create_email_template(
      iv_template_name = lv_tmpl
      iv_subject       = 'Test subject'
      iv_html          = '<p>Test HTML</p>'
      iv_text          = 'Test text' ).

    DATA(lo_resp) = ao_se2->getemailtemplate( iv_templatename = lv_tmpl ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_resp->get_templatename( )
      exp = lv_tmpl
      msg = 'create_email_template: name mismatch' ).

    TRY.
        tag_se2_resource(
          |arn:aws:ses:{ ao_session->get_region( ) }:{ ao_session->get_account_id( ) }:template/{ lv_tmpl }| ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    ao_se2->deleteemailtemplate( iv_templatename = lv_tmpl ).
  ENDMETHOD.


  " =========================================================================
  " TEST: create_contact
  " =========================================================================
  METHOD create_contact.
    DATA(lv_email) = |success+ct{ uuid_suffix( ) }@simulator.amazonses.com|.

    ao_se2_actions->create_contact(
      iv_contact_list_name = av_contact_list
      iv_email_address     = lv_email ).

    DATA(lo_resp) = ao_se2->listcontacts( iv_contactlistname = av_contact_list ).
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_resp->get_contacts( ) INTO DATA(lo_ct).
      IF lo_ct->get_emailaddress( ) = lv_email.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |create_contact: { lv_email } not found in list| ).

    ao_se2->deletecontact(
      iv_contactlistname = av_contact_list
      iv_emailaddress    = lv_email ).
  ENDMETHOD.


  " =========================================================================
  " TEST: send_email
  " Uses the SES simulator as both FROM and TO – no manual verification needed.
  " =========================================================================
  METHOD send_email.
    ao_se2_actions->send_email(
      iv_from_email_address = cv_sim_addr
      iv_to_email_address   = cv_sim_addr
      iv_subject            = 'ABAP SDK unit test – send_email'
      iv_html_body          = '<p>Unit test</p>'
      iv_text_body          = 'Unit test' ).

    cl_abap_unit_assert=>assert_true(
      act = abap_true
      msg = 'send_email: must complete without exception' ).
  ENDMETHOD.


  " =========================================================================
  " TEST: send_email_template
  " =========================================================================
  METHOD send_email_template.
    " Ensure the simulator contact is in the shared list.
    TRY.
        ao_se2->createcontact(
          iv_contactlistname = av_contact_list
          iv_emailaddress    = cv_sim_addr ).
      CATCH /aws1/cx_se2alreadyexistsex.
    ENDTRY.

    ao_se2_actions->send_email_template(
      iv_from_email_address = cv_sim_addr
      iv_to_email_address   = cv_sim_addr
      iv_template_name      = av_template_name
      iv_template_data      = '{"name":"ABAP Tester"}'
      iv_contact_list_name  = av_contact_list ).

    cl_abap_unit_assert=>assert_true(
      act = abap_true
      msg = 'send_email_template: must complete without exception' ).
  ENDMETHOD.


  " =========================================================================
  " TEST: list_contacts
  " =========================================================================
  METHOD list_contacts.
    DATA(lv_email) = |success+lc{ uuid_suffix( ) }@simulator.amazonses.com|.

    TRY.
        ao_se2->createcontact(
          iv_contactlistname = av_contact_list
          iv_emailaddress    = lv_email ).
      CATCH /aws1/cx_se2alreadyexistsex.
    ENDTRY.

    DATA lo_result TYPE REF TO /aws1/cl_se2listcontactsrsp.
    ao_se2_actions->list_contacts(
      EXPORTING iv_contact_list_name = av_contact_list
      IMPORTING oo_result            = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_contacts: result must not be null' ).

    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_result->get_contacts( ) INTO DATA(lo_ct).
      IF lo_ct->get_emailaddress( ) = lv_email.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_contacts: { lv_email } must appear in the result| ).

    ao_se2->deletecontact(
      iv_contactlistname = av_contact_list
      iv_emailaddress    = lv_email ).
  ENDMETHOD.


  " =========================================================================
  " TEST: delete_contact_list
  " Strategy:
  "   1. Ensure the shared list exists.
  "   2. Call the action method to delete it.
  "   3. Verify it is gone (GetContactList -> NotFoundException).
  "   4. Restore the shared list so subsequent tests are unaffected.
  " =========================================================================
  METHOD delete_contact_list.
    " Step 1 – ensure the shared list is present.
    " ensure_contact_list handles the case where it was already deleted.
    " However, at this point we must not trigger the BadRequestException path
    " (that would mean a different list exists, which we do not own).
    " Because class_setup and ensure_contact_list always set av_contact_list
    " to the one list that exists, we can simply try to create it.
    TRY.
        ao_se2->createcontactlist( iv_contactlistname = av_contact_list ).
        TRY.
            tag_se2_resource(
              |arn:aws:ses:{ ao_session->get_region( ) }:{ ao_session->get_account_id( ) }:contact-list/{ av_contact_list }| ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
      CATCH /aws1/cx_se2alreadyexistsex.
        " Already present – fine.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bex).
        " The limit is hit but the existing list must be ours (set in setup).
        " Check – if the listed name matches av_contact_list we are fine;
        " otherwise adopt it (handles edge cases in test ordering).
        DATA(lo_ll) = ao_se2->listcontactlists( ).
        DATA(lt_ll) = lo_ll->get_contactlists( ).
        IF lines( lt_ll ) > 0.
          READ TABLE lt_ll INDEX 1 INTO DATA(lo_ex_list).
          av_contact_list = lo_ex_list->get_contactlistname( ).
        ELSE.
          cl_abap_unit_assert=>fail(
            msg = |delete_contact_list: cannot ensure list: { lo_bex->get_text( ) }| ).
        ENDIF.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_pre).
        cl_abap_unit_assert=>fail(
          msg = |delete_contact_list: cannot ensure list: { lo_pre->get_text( ) }| ).
    ENDTRY.

    " Step 2 – call the action method under test.
    ao_se2_actions->delete_contact_list( av_contact_list ).

    " Step 3 – verify the list is gone.
    TRY.
        ao_se2->getcontactlist( iv_contactlistname = av_contact_list ).
        cl_abap_unit_assert=>fail(
          msg = |delete_contact_list: list { av_contact_list } should be gone| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected.
    ENDTRY.

    " Step 4 – restore the shared list for subsequent tests.
    ensure_contact_list( ).
  ENDMETHOD.


  " =========================================================================
  " TEST: delete_email_template
  " =========================================================================
  METHOD delete_email_template.
    " Ensure the dedicated delete-template exists.
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
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex).
        cl_abap_unit_assert=>fail(
          msg = |delete_email_template: cannot create prerequisite: { lo_ex->get_text( ) }| ).
    ENDTRY.

    ao_se2_actions->delete_email_template( av_del_template ).

    TRY.
        ao_se2->getemailtemplate( iv_templatename = av_del_template ).
        cl_abap_unit_assert=>fail(
          msg = |delete_email_template: { av_del_template } should be deleted| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected.
    ENDTRY.
  ENDMETHOD.


  " =========================================================================
  " TEST: delete_email_identity
  " =========================================================================
  METHOD delete_email_identity.
    DATA(lv_id) = |se2del{ uuid_suffix( ) }@example.com|.

    DATA lt_tags TYPE /aws1/cl_se2tag=>tt_taglist.
    APPEND NEW /aws1/cl_se2tag( iv_key = 'convert_test' iv_value = 'true' ) TO lt_tags.
    ao_se2->createemailidentity(
      iv_emailidentity = lv_id
      it_tags          = lt_tags ).

    ao_se2_actions->delete_email_identity( lv_id ).

    TRY.
        ao_se2->getemailidentity( iv_emailidentity = lv_id ).
        cl_abap_unit_assert=>fail(
          msg = |delete_email_identity: { lv_id } should be deleted| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected.
    ENDTRY.
  ENDMETHOD.


  " =========================================================================
  " TEST: get_email_identity
  " =========================================================================
  METHOD get_email_identity.
    DATA(lv_id) = |se2get{ uuid_suffix( ) }@example.com|.

    DATA lt_tags TYPE /aws1/cl_se2tag=>tt_taglist.
    APPEND NEW /aws1/cl_se2tag( iv_key = 'convert_test' iv_value = 'true' ) TO lt_tags.
    ao_se2->createemailidentity(
      iv_emailidentity = lv_id
      it_tags          = lt_tags ).

    DATA lo_result TYPE REF TO /aws1/cl_se2getemailidresponse.
    ao_se2_actions->get_email_identity(
      EXPORTING iv_email_identity = lv_id
      IMPORTING oo_result         = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'get_email_identity: result must not be null' ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_identitytype( )
      exp = 'EMAIL_ADDRESS'
      msg = 'get_email_identity: identity type must be EMAIL_ADDRESS' ).

    ao_se2->deleteemailidentity( iv_emailidentity = lv_id ).
  ENDMETHOD.


  " =========================================================================
  " TEST: send_bulk_email
  " =========================================================================
  METHOD send_bulk_email.
    DATA(lv_r1) = |success+be1{ uuid_suffix( ) }@simulator.amazonses.com|.
    DATA(lv_r2) = |success+be2{ uuid_suffix( ) }@simulator.amazonses.com|.

    DATA lt_to1 TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w( iv_value = lv_r1 ) TO lt_to1.

    DATA lt_to2 TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w( iv_value = lv_r2 ) TO lt_to2.

    DATA lt_entries TYPE /aws1/cl_se2bulkemailentry=>tt_bulkemailentrylist.
    APPEND NEW /aws1/cl_se2bulkemailentry(
      io_destination = NEW /aws1/cl_se2destination( it_toaddresses = lt_to1 ) ) TO lt_entries.
    APPEND NEW /aws1/cl_se2bulkemailentry(
      io_destination = NEW /aws1/cl_se2destination( it_toaddresses = lt_to2 ) ) TO lt_entries.

    DATA lo_result TYPE REF TO /aws1/cl_se2sendbulkemailrsp.
    ao_se2_actions->send_bulk_email(
      EXPORTING
        iv_from_address  = cv_sim_addr
        iv_template_name = av_template_name
        iv_template_data = '{"name":"Bulk Tester"}'
        it_bulk_entries  = lt_entries
      IMPORTING
        oo_result = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'send_bulk_email: result must not be null' ).

    DATA(lt_results) = lo_result->get_bulkemailentryresults( ).
    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_results )
      exp = 2
      msg = 'send_bulk_email: must return one result per entry' ).

    LOOP AT lt_results INTO DATA(lo_er).
      cl_abap_unit_assert=>assert_equals(
        act = lo_er->get_status( )
        exp = 'SUCCESS'
        msg = |send_bulk_email: entry status must be SUCCESS, got { lo_er->get_status( ) }| ).
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
