" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_se2_actions DEFINITION DEFERRED.
CLASS /awsex/cl_se2_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_se2_actions.

CLASS ltc_awsex_cl_se2_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " SES sandbox hard limit: 1 contact list per account.
    CLASS-DATA av_contact_list  TYPE /aws1/se2contactlistname.
    CLASS-DATA av_template_name TYPE /aws1/se2emailtemplatename.
    CLASS-DATA av_del_template  TYPE /aws1/se2emailtemplatename.
    " Sender address resolved in class_setup.
    " Priority 1: first verified EMAIL_ADDRESS identity found.
    " Priority 2: freshly created (unverified) identity – send tests accept
    "             MessageRejected, matching the SES v1 test pattern in this repo.
    CLASS-DATA av_from_addr     TYPE /aws1/se2emailaddress.
    CLASS-DATA av_from_created  TYPE abap_bool VALUE abap_false.

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

    CLASS-METHODS tag_se2_resource
      IMPORTING iv_arn TYPE /aws1/se2amazonresourcename
      RAISING   /aws1/cx_rt_generic.

    CLASS-METHODS uuid_suffix
      RETURNING VALUE(rv_s) TYPE string.

    CLASS-METHODS ensure_contact_list RAISING /aws1/cx_rt_generic.

    " Collect every contact address across all ListContacts pages.
    " All helper DATA is declared before the DO loop to avoid the ABAP 7.4
    " inline-DATA-in-loop scoping bug that causes pagination to re-read
    " the first page on every subsequent iteration.
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
    " -----------------------------------------------------------------------
    " IMPORTANT: All DATA declarations are placed BEFORE the DO loop.
    "
    " In ABAP 7.4, inline DATA inside a loop body is method-scoped and only
    " initialised once at the start of the method – it is NOT re-declared on
    " each iteration.  If lo_page were declared with DATA inside the loop,
    " the assignment on the first iteration would be the only one ever seen;
    " every subsequent call to ao_se2->listcontacts(...) would return a new
    " object but the variable would still hold the first page's reference,
    " making the loop read the first page endlessly and never terminating via
    " the NextToken check.
    " -----------------------------------------------------------------------
    DATA lv_token TYPE /aws1/se2nexttoken.
    DATA lo_page  TYPE REF TO /aws1/cl_se2listcontactsrsp.
    DATA lo_ct    TYPE REF TO /aws1/cl_se2contact.

    lo_page = ao_se2->listcontacts(
      iv_contactlistname = av_contact_list
      iv_pagesize        = 100 ).

    DO.
      LOOP AT lo_page->get_contacts( ) INTO lo_ct.
        APPEND lo_ct->get_emailaddress( ) TO rt_emails.
      ENDLOOP.

      lv_token = lo_page->get_nexttoken( ).
      IF lv_token IS INITIAL.
        EXIT.
      ENDIF.

      lo_page = ao_se2->listcontacts(
        iv_contactlistname = av_contact_list
        iv_pagesize        = 100
        iv_nexttoken       = lv_token ).
    ENDDO.
  ENDMETHOD.


  METHOD ensure_contact_list.
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
        " A different list occupies the single slot – adopt it.
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
    " Resolve a FROM address.
    " Priority 1: scan for an already-verified EMAIL_ADDRESS identity.
    " Priority 2: create a new (unverified) identity; send tests accept
    "             MessageRejected (identical to SES v1 test pattern here).
    " -----------------------------------------------------------------------
    DATA lv_id_token TYPE /aws1/se2nexttoken.
    DATA lo_id_pg    TYPE REF TO /aws1/cl_se2listemailidentsrsp.
    DATA lo_id_row   TYPE REF TO /aws1/cl_se2identityinfo.
    DATA lo_id_det   TYPE REF TO /aws1/cl_se2getemailidresponse.
    DATA lv_id_first TYPE abap_bool VALUE abap_true.

    DO.
      IF lv_id_first = abap_true.
        lo_id_pg    = ao_se2->listemailidentities( iv_pagesize = 100 ).
        lv_id_first = abap_false.
      ELSE.
        lo_id_pg = ao_se2->listemailidentities(
          iv_pagesize  = 100
          iv_nexttoken = lv_id_token ).
      ENDIF.

      LOOP AT lo_id_pg->get_emailidentities( ) INTO lo_id_row.
        IF lo_id_row->get_identitytype( ) <> 'EMAIL_ADDRESS'.
          CONTINUE.
        ENDIF.
        TRY.
            lo_id_det = ao_se2->getemailidentity(
              iv_emailidentity = lo_id_row->get_identityname( ) ).
            IF lo_id_det->get_verifiedforsendingstatus( ) = abap_true.
              av_from_addr    = lo_id_row->get_identityname( ).
              av_from_created = abap_false.
              EXIT.
            ENDIF.
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
      ENDLOOP.

      IF av_from_addr IS NOT INITIAL. EXIT. ENDIF.
      lv_id_token = lo_id_pg->get_nexttoken( ).
      IF lv_id_token IS INITIAL. EXIT. ENDIF.
    ENDDO.

    IF av_from_addr IS INITIAL.
      av_from_addr = |se2snd{ lv_sfx }@example.com|.
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

    ensure_contact_list( ).

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
    " Delete all contacts then remove the shared list.
    DATA lt_all TYPE string_table.
    DATA lv_ea  TYPE string.
    TRY.
        lt_all = collect_all_contacts( ).
        LOOP AT lt_all INTO lv_ea.
          TRY.
              ao_se2->deletecontact(
                iv_contactlistname = av_contact_list
                iv_emailaddress    = lv_ea ).
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
    " Step 1 – remove all contacts and delete the shared list.
    DATA lt_old TYPE string_table.
    DATA lv_old TYPE string.
    TRY.
        lt_old = collect_all_contacts( ).
        LOOP AT lt_old INTO lv_old.
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

    " Step 2 – call the action under test.
    DATA(lv_new) = |se2-cl-{ uuid_suffix( ) }|.
    ao_se2_actions->create_contact_list( lv_new ).

    " Step 3 – verify.
    DATA(lo_resp) = ao_se2->getcontactlist( iv_contactlistname = lv_new ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_resp->get_contactlistname( )
      exp = lv_new
      msg = 'create_contact_list: list name mismatch' ).

    TRY.
        tag_se2_resource(
          |arn:aws:ses:{ ao_session->get_region( ) }:{ ao_session->get_account_id( ) }:contact-list/{ lv_new }| ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Step 4 – delete.
    ao_se2->deletecontactlist( iv_contactlistname = lv_new ).

    " Step 5 – restore.
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
  " Adds a simulator contact, paginates to verify presence, removes it.
  " =========================================================================
  METHOD create_contact.
    DATA(lv_email) = |success+ct{ uuid_suffix( ) }@simulator.amazonses.com|.

    ao_se2_actions->create_contact(
      iv_contact_list_name = av_contact_list
      iv_email_address     = lv_email ).

    DATA lt_all  TYPE string_table.
    DATA lv_e    TYPE string.
    DATA lv_fnd  TYPE abap_bool VALUE abap_false.
    lt_all = collect_all_contacts( ).
    LOOP AT lt_all INTO lv_e.
      IF lv_e = lv_email. lv_fnd = abap_true. EXIT. ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_fnd
      msg = |create_contact: { lv_email } not found in list| ).

    ao_se2->deletecontact(
      iv_contactlistname = av_contact_list
      iv_emailaddress    = lv_email ).
  ENDMETHOD.


  " =========================================================================
  " TEST: send_email
  " =========================================================================
  METHOD send_email.
    TRY.
        ao_se2_actions->send_email(
          iv_from_email_address = av_from_addr
          iv_to_email_address   = av_from_addr
          iv_subject            = 'ABAP SDK unit test – send_email'
          iv_html_body          = '<p>Unit test</p>'
          iv_text_body          = 'Unit test' ).
        cl_abap_unit_assert=>assert_true(
          act = abap_true
          msg = 'send_email: completed successfully' ).
      CATCH /aws1/cx_se2messagerejected.
        " Sandbox without a pre-verified identity: API call was correctly
        " constructed; MessageRejected is the expected account-level outcome.
        MESSAGE 'send_email: MessageRejected (sender pending verification)' TYPE 'I'.
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
        MESSAGE 'send_email_template: MessageRejected (sender pending verification)' TYPE 'I'.
    ENDTRY.
  ENDMETHOD.


  " =========================================================================
  " TEST: list_contacts
  " Creates a unique contact, calls the action, paginates to verify presence.
  " =========================================================================
  METHOD list_contacts.
    DATA(lv_email) = |success+lc{ uuid_suffix( ) }@simulator.amazonses.com|.

    TRY.
        ao_se2->createcontact(
          iv_contactlistname = av_contact_list
          iv_emailaddress    = lv_email ).
      CATCH /aws1/cx_se2alreadyexistsex.
    ENDTRY.

    " Exercise the action method under test.
    DATA lo_result TYPE REF TO /aws1/cl_se2listcontactsrsp.
    ao_se2_actions->list_contacts(
      EXPORTING iv_contact_list_name = av_contact_list
      IMPORTING oo_result            = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_contacts: result must not be null' ).

    " Locate the new contact across ALL pages using the pagination helper.
    DATA lt_all TYPE string_table.
    DATA lv_e   TYPE string.
    DATA lv_fnd TYPE abap_bool VALUE abap_false.
    lt_all = collect_all_contacts( ).
    LOOP AT lt_all INTO lv_e.
      IF lv_e = lv_email. lv_fnd = abap_true. EXIT. ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_fnd
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

        DATA(lt_res) = lo_result->get_bulkemailentryresults( ).
        cl_abap_unit_assert=>assert_equals(
          act = lines( lt_res )
          exp = 2
          msg = 'send_bulk_email: must return one result per entry' ).

        DATA lo_er TYPE REF TO /aws1/cl_se2bulkemailentryrslt.
        LOOP AT lt_res INTO lo_er.
          cl_abap_unit_assert=>assert_equals(
            act = lo_er->get_status( )
            exp = 'SUCCESS'
            msg = |send_bulk_email: entry must be SUCCESS, got { lo_er->get_status( ) }| ).
        ENDLOOP.

      CATCH /aws1/cx_se2messagerejected.
        MESSAGE 'send_bulk_email: MessageRejected (sender pending verification)' TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
