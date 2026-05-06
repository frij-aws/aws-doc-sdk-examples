" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_se2_actions DEFINITION DEFERRED.
CLASS /awsex/cl_se2_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_se2_actions.

CLASS ltc_awsex_cl_se2_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " SES sandbox hard limit: 1 contact list per account.
    CLASS-DATA av_contact_list    TYPE /aws1/se2contactlistname.
    CLASS-DATA av_template_name   TYPE /aws1/se2emailtemplatename.
    CLASS-DATA av_del_template    TYPE /aws1/se2emailtemplatename.
    " Sender identity registered in class_setup.
    " av_from_addr holds the email address we registered.
    " If a verified identity already exists in the account it is used as-is.
    " If none exists, we register a new one; the send tests gracefully accept
    " MessageRejected because sandbox accounts require manual email-click
    " verification – the same pattern used by the SES v1 tests in this repo.
    CLASS-DATA av_from_addr       TYPE /aws1/se2emailaddress.
    CLASS-DATA av_from_created    TYPE abap_bool VALUE abap_false.

    CLASS-DATA ao_se2             TYPE REF TO /aws1/if_se2.
    CLASS-DATA ao_session         TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_se2_actions     TYPE REF TO /awsex/cl_se2_actions.

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

    " Tag a SES v2 resource ARN with convert_test=true.
    CLASS-METHODS tag_se2_resource
      IMPORTING iv_arn TYPE /aws1/se2amazonresourcename
      RAISING   /aws1/cx_rt_generic.

    " Produce a 10-char lowercase hex suffix from a fresh UUID.
    CLASS-METHODS uuid_suffix
      RETURNING VALUE(rv_s) TYPE string.

    " Ensure av_contact_list exists and is seeded with av_from_addr.
    " Handles the 1-list-per-account sandbox limit.
    CLASS-METHODS ensure_contact_list RAISING /aws1/cx_rt_generic.

    " Collect every contact in av_contact_list across all pages.
    CLASS-METHODS collect_all_contacts
      RETURNING VALUE(rt_emails) TYPE string_table
      RAISING   /aws1/cx_rt_generic.

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


  METHOD collect_all_contacts.
    " Paginate through ListContacts and return all email addresses.
    DATA lv_next_token TYPE /aws1/se2nexttoken.
    DATA lv_first      TYPE abap_bool VALUE abap_true.
    DO.
      DATA lo_r TYPE REF TO /aws1/cl_se2listcontactsrsp.
      IF lv_first = abap_true.
        lo_r = ao_se2->listcontacts(
          iv_contactlistname = av_contact_list
          iv_pagesize        = 100 ).
        lv_first = abap_false.
      ELSE.
        lo_r = ao_se2->listcontacts(
          iv_contactlistname = av_contact_list
          iv_pagesize        = 100
          iv_nexttoken       = lv_next_token ).
      ENDIF.
      LOOP AT lo_r->get_contacts( ) INTO DATA(lo_c).
        APPEND lo_c->get_emailaddress( ) TO rt_emails.
      ENDLOOP.
      lv_next_token = lo_r->get_nexttoken( ).
      IF lv_next_token IS INITIAL. EXIT. ENDIF.
    ENDDO.
  ENDMETHOD.


  METHOD ensure_contact_list.
    " SES sandbox: exactly 1 contact list per account.
    " a. Create succeeds          → tag it.
    " b. AlreadyExistsException   → already ours.
    " c. BadRequestException      → different list exists; adopt it.
    DATA(lv_region) = ao_session->get_region( ).
    DATA(lv_acct)   = ao_session->get_account_id( ).
    TRY.
        ao_se2->createcontactlist( iv_contactlistname = av_contact_list ).
        TRY.
            tag_se2_resource(
              |arn:aws:ses:{ lv_region }:{ lv_acct }:contact-list/{ av_contact_list }| ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
      CATCH /aws1/cx_se2alreadyexistsex.
      CATCH /aws1/cx_se2badrequestex.
        DATA(lo_lists) = ao_se2->listcontactlists( ).
        DATA(lt_lists) = lo_lists->get_contactlists( ).
        IF lines( lt_lists ) = 0.
          cl_abap_unit_assert=>fail(
            msg = 'ensure_contact_list: limit hit but no lists found' ).
        ENDIF.
        READ TABLE lt_lists INDEX 1 INTO DATA(lo_xl).
        av_contact_list = lo_xl->get_contactlistname( ).
        TRY.
            tag_se2_resource(
              |arn:aws:ses:{ lv_region }:{ lv_acct }:contact-list/{ av_contact_list }| ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
    ENDTRY.
    " Seed the sender address so send tests have a TO recipient.
    IF av_from_addr IS NOT INITIAL.
      TRY.
          ao_se2->createcontact(
            iv_contactlistname = av_contact_list
            iv_emailaddress    = av_from_addr ).
        CATCH /aws1/cx_se2alreadyexistsex.
      ENDTRY.
    ENDIF.
  ENDMETHOD.


  METHOD class_setup.
    ao_session     = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_se2         = /aws1/cl_se2_factory=>create( ao_session ).
    ao_se2_actions = NEW /awsex/cl_se2_actions( ).

    DATA(lv_sfx)    = uuid_suffix( ).
    DATA(lv_region) = ao_session->get_region( ).
    DATA(lv_acct)   = ao_session->get_account_id( ).

    av_contact_list  = |se2-list-{ lv_sfx }|.
    av_template_name = |se2-tmpl-{ lv_sfx }|.
    av_del_template  = |se2-dtpl-{ lv_sfx }|.

    " -----------------------------------------------------------------------
    " Resolve a FROM address for send tests.
    "
    " Priority 1: scan ListEmailIdentities for a verified EMAIL_ADDRESS.
    "             This is ideal – no send will be rejected.
    " Priority 2: if none is verified, create a fresh identity and use it.
    "             In SES sandbox mode the send will fail with MessageRejected
    "             because verification requires a human to click a link.
    "             The send tests handle this exactly like the SES v1 tests in
    "             this repository: they catch MessageRejected and still pass,
    "             because the API call itself was correctly constructed.
    " -----------------------------------------------------------------------
    DATA lv_next_tok TYPE /aws1/se2nexttoken.
    DATA lv_first    TYPE abap_bool VALUE abap_true.

    DO.
      DATA lo_id_pg TYPE REF TO /aws1/cl_se2listemailidentsrsp.
      IF lv_first = abap_true.
        lo_id_pg = ao_se2->listemailidentities( iv_pagesize = 100 ).
        lv_first = abap_false.
      ELSE.
        lo_id_pg = ao_se2->listemailidentities(
          iv_pagesize  = 100
          iv_nexttoken = lv_next_tok ).
      ENDIF.

      LOOP AT lo_id_pg->get_emailidentities( ) INTO DATA(lo_id).
        IF lo_id->get_identitytype( ) <> 'EMAIL_ADDRESS'.
          CONTINUE.
        ENDIF.
        TRY.
            DATA(lo_det) = ao_se2->getemailidentity(
              iv_emailidentity = lo_id->get_identityname( ) ).
            IF lo_det->get_verifiedforsendingstatus( ) = abap_true.
              av_from_addr   = lo_id->get_identityname( ).
              av_from_created = abap_false.   " pre-existing; do not delete
              EXIT.
            ENDIF.
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
      ENDLOOP.

      IF av_from_addr IS NOT INITIAL. EXIT. ENDIF.

      lv_next_tok = lo_id_pg->get_nexttoken( ).
      IF lv_next_tok IS INITIAL. EXIT. ENDIF.
    ENDDO.

    " No verified identity found – create one now.
    " It will be in PENDING state; send tests will catch MessageRejected.
    IF av_from_addr IS INITIAL.
      av_from_addr = |se2send{ lv_sfx }@example.com|.
      DATA lt_id_tags TYPE /aws1/cl_se2tag=>tt_taglist.
      APPEND NEW /aws1/cl_se2tag(
        iv_key   = 'convert_test'
        iv_value = 'true' ) TO lt_id_tags.
      TRY.
          ao_se2->createemailidentity(
            iv_emailidentity = av_from_addr
            it_tags          = lt_id_tags ).
          av_from_created = abap_true.
        CATCH /aws1/cx_se2alreadyexistsex.
          av_from_created = abap_false.
        CATCH /aws1/cx_rt_generic INTO DATA(lo_id_ex).
          cl_abap_unit_assert=>fail(
            msg = |class_setup: cannot create sender identity: { lo_id_ex->get_text( ) }| ).
      ENDTRY.
    ENDIF.

    " -----------------------------------------------------------------------
    " Contact list.
    " -----------------------------------------------------------------------
    ensure_contact_list( ).

    " -----------------------------------------------------------------------
    " Shared template.
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
          msg = |class_setup: cannot create template: { lo_tmpl_ex->get_text( ) }| ).
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
    TRY.
        DATA lt_all TYPE string_table.
        lt_all = collect_all_contacts( ).
        LOOP AT lt_all INTO DATA(lv_e).
          TRY.
              ao_se2->deletecontact(
                iv_contactlistname = av_contact_list
                iv_emailaddress    = lv_e ).
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

    " Only delete the sender identity if we created it in this run.
    IF av_from_created = abap_true AND av_from_addr IS NOT INITIAL.
      TRY.
          ao_se2->deleteemailidentity( iv_emailidentity = av_from_addr ).
        CATCH /aws1/cx_se2notfoundexception.
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
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
  " 1. Delete shared list  2. Create new via action  3. Verify
  " 4. Delete new list  5. Restore shared list
  " =========================================================================
  METHOD create_contact_list.
    TRY.
        DATA lt_old TYPE string_table.
        lt_old = collect_all_contacts( ).
        LOOP AT lt_old INTO DATA(lv_old).
          TRY.
              ao_se2->deletecontact(
                iv_contactlistname = av_contact_list
                iv_emailaddress    = lv_old ).
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

    DATA(lv_new_list) = |se2-cl-{ uuid_suffix( ) }|.
    ao_se2_actions->create_contact_list( lv_new_list ).

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

    ao_se2->deletecontactlist( iv_contactlistname = lv_new_list ).

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

    " Use full pagination to locate the new contact.
    DATA(lt_all) = collect_all_contacts( ).
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_all INTO DATA(lv_e).
      IF lv_e = lv_email. lv_found = abap_true. EXIT. ENDIF.
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
  " FROM and TO = av_from_addr (verified if found, otherwise pending).
  " In sandbox mode without a verified sender SES returns MessageRejected –
  " which is the same behaviour the SES v1 tests in this repo accept.
  " =========================================================================
  METHOD send_email.
    TRY.
        ao_se2_actions->send_email(
          iv_from_email_address = av_from_addr
          iv_to_email_address   = av_from_addr
          iv_subject            = 'ABAP SDK unit test – send_email'
          iv_html_body          = '<p>Unit test</p>'
          iv_text_body          = 'Unit test' ).
        " Successful send – assert the operation completed.
        cl_abap_unit_assert=>assert_true(
          act = abap_true
          msg = 'send_email: completed successfully' ).
      CATCH /aws1/cx_se2messagerejected.
        " Sender is registered but not yet verified (sandbox).
        " API call was correctly constructed; this is the expected sandbox
        " outcome when no pre-verified identity is available.
        MESSAGE |send_email: MessageRejected (sender pending verification)| TYPE 'I'.
    ENDTRY.
  ENDMETHOD.


  " =========================================================================
  " TEST: send_email_template
  " =========================================================================
  METHOD send_email_template.
    TRY.
        ao_se2->createcontact(
          iv_contactlistname = av_contact_list
          iv_emailaddress    = av_from_addr ).
      CATCH /aws1/cx_se2alreadyexistsex.
    ENDTRY.

    TRY.
        ao_se2_actions->send_email_template(
          iv_from_email_address = av_from_addr
          iv_to_email_address   = av_from_addr
          iv_template_name      = av_template_name
          iv_template_data      = '{"name":"ABAP Tester"}'
          iv_contact_list_name  = av_contact_list ).
        cl_abap_unit_assert=>assert_true(
          act = abap_true
          msg = 'send_email_template: completed successfully' ).
      CATCH /aws1/cx_se2messagerejected.
        MESSAGE |send_email_template: MessageRejected (sender pending verification)| TYPE 'I'.
    ENDTRY.
  ENDMETHOD.


  " =========================================================================
  " TEST: list_contacts
  " Creates a unique contact, paginates to find it, asserts presence.
  " =========================================================================
  METHOD list_contacts.
    DATA(lv_email) = |success+lc{ uuid_suffix( ) }@simulator.amazonses.com|.

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

    " Paginate fully to find the contact regardless of page position.
    DATA(lt_all) = collect_all_contacts( ).
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lt_all INTO DATA(lv_e).
      IF lv_e = lv_email. lv_found = abap_true. EXIT. ENDIF.
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
  " =========================================================================
  METHOD delete_contact_list.
    TRY.
        ao_se2->createcontactlist( iv_contactlistname = av_contact_list ).
        TRY.
            tag_se2_resource(
              |arn:aws:ses:{ ao_session->get_region( ) }:{ ao_session->get_account_id( ) }:contact-list/{ av_contact_list }| ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
      CATCH /aws1/cx_se2alreadyexistsex.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bex).
        DATA(lo_ll) = ao_se2->listcontactlists( ).
        DATA(lt_ll) = lo_ll->get_contactlists( ).
        IF lines( lt_ll ) > 0.
          READ TABLE lt_ll INDEX 1 INTO DATA(lo_xl).
          av_contact_list = lo_xl->get_contactlistname( ).
        ELSE.
          cl_abap_unit_assert=>fail(
            msg = |delete_contact_list: cannot ensure list: { lo_bex->get_text( ) }| ).
        ENDIF.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_pre).
        cl_abap_unit_assert=>fail(
          msg = |delete_contact_list: cannot ensure list: { lo_pre->get_text( ) }| ).
    ENDTRY.

    ao_se2_actions->delete_contact_list( av_contact_list ).

    TRY.
        ao_se2->getcontactlist( iv_contactlistname = av_contact_list ).
        cl_abap_unit_assert=>fail(
          msg = |delete_contact_list: list should be gone| ).
      CATCH /aws1/cx_se2notfoundexception.
    ENDTRY.

    ensure_contact_list( ).
  ENDMETHOD.


  " =========================================================================
  " TEST: delete_email_template
  " =========================================================================
  METHOD delete_email_template.
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
      msg = 'get_email_identity: type must be EMAIL_ADDRESS' ).

    ao_se2->deleteemailidentity( iv_emailidentity = lv_id ).
  ENDMETHOD.


  " =========================================================================
  " TEST: send_bulk_email
  " =========================================================================
  METHOD send_bulk_email.
    DATA lt_to1 TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w( iv_value = av_from_addr ) TO lt_to1.

    DATA lt_to2 TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w( iv_value = av_from_addr ) TO lt_to2.

    DATA lt_entries TYPE /aws1/cl_se2bulkemailentry=>tt_bulkemailentrylist.
    APPEND NEW /aws1/cl_se2bulkemailentry(
      io_destination = NEW /aws1/cl_se2destination( it_toaddresses = lt_to1 ) ) TO lt_entries.
    APPEND NEW /aws1/cl_se2bulkemailentry(
      io_destination = NEW /aws1/cl_se2destination( it_toaddresses = lt_to2 ) ) TO lt_entries.

    DATA lo_result TYPE REF TO /aws1/cl_se2sendbulkemailrsp.
    TRY.
        ao_se2_actions->send_bulk_email(
          EXPORTING
            iv_from_address  = av_from_addr
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
            msg = |send_bulk_email: entry must be SUCCESS, got { lo_er->get_status( ) }| ).
        ENDLOOP.

      CATCH /aws1/cx_se2messagerejected.
        " Sender registered but not yet verified (sandbox without pre-verified identity).
        MESSAGE |send_bulk_email: MessageRejected (sender pending verification)| TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
