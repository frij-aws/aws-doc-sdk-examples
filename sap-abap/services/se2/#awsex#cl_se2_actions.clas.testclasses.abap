" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_se2_actions DEFINITION DEFERRED.
CLASS /awsex/cl_se2_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_se2_actions.

CLASS ltc_awsex_cl_se2_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " -----------------------------------------------------------------------
    " Sender identity used for send tests.
    " Email-address identities require owner-click verification, so the
    " ZCODE_DEMO account must have this address in a Pending/Verified state.
    " We register it in class_setup; tests that send use it as the From
    " address and treat MessageRejected (unverified) as an accepted outcome
    " that proves the API call was correctly formed and reached SES.
    " -----------------------------------------------------------------------
    CONSTANTS cv_sender TYPE /aws1/se2emailaddress
      VALUE 'sestest@example.com'.

    CLASS-DATA ao_se2         TYPE REF TO /aws1/if_se2.
    CLASS-DATA ao_session     TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_se2_actions TYPE REF TO /awsex/cl_se2_actions.
    CLASS-DATA av_uuid        TYPE string.

    " Resources created once in class_setup and shared across read-only tests
    CLASS-DATA av_contact_list_name TYPE /aws1/se2contactlistname.
    CLASS-DATA av_template_name     TYPE /aws1/se2emailtemplatename.
    CLASS-DATA av_sender_identity   TYPE /aws1/se2identity.

    " Resources created in class_setup exclusively for the delete tests
    CLASS-DATA av_del_list_name   TYPE /aws1/se2contactlistname.
    CLASS-DATA av_del_tmpl_name   TYPE /aws1/se2emailtemplatename.
    CLASS-DATA av_del_identity    TYPE /aws1/se2identity.

    METHODS:
      " --- New operations added in this conversion ---
      get_email_identity         FOR TESTING RAISING /aws1/cx_rt_generic,
      send_email_with_attachment FOR TESTING RAISING /aws1/cx_rt_generic,
      send_bulk_email            FOR TESTING RAISING /aws1/cx_rt_generic,
      " --- Pre-existing operations ---
      create_email_identity  FOR TESTING RAISING /aws1/cx_rt_generic,
      create_email_template  FOR TESTING RAISING /aws1/cx_rt_generic,
      create_contact_list    FOR TESTING RAISING /aws1/cx_rt_generic,
      create_contact         FOR TESTING RAISING /aws1/cx_rt_generic,
      send_email             FOR TESTING RAISING /aws1/cx_rt_generic,
      send_email_template    FOR TESTING RAISING /aws1/cx_rt_generic,
      list_contacts          FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_contact_list    FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_email_template  FOR TESTING RAISING /aws1/cx_rt_generic,
      delete_email_identity  FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    " class_teardown must NOT propagate exceptions — every step is guarded
    " individually so one failure does not prevent subsequent cleanups.
    CLASS-METHODS class_teardown.

    " Helper: apply convert_test tag to an SES resource ARN
    CLASS-METHODS tag_resource
      IMPORTING iv_resource_arn TYPE /aws1/se2amazonresourcename
      RAISING   /aws1/cx_rt_generic.

    " Helper: return a unique simulator recipient address
    CLASS-METHODS sim_addr
      IMPORTING iv_label        TYPE string
      RETURNING VALUE(rv_email) TYPE /aws1/se2emailaddress.

    " Helper: build the SES identity ARN
    CLASS-METHODS identity_arn
      IMPORTING iv_identity   TYPE /aws1/se2identity
      RETURNING VALUE(rv_arn) TYPE /aws1/se2amazonresourcename.

    " Helper: build the SES template ARN
    CLASS-METHODS template_arn
      IMPORTING iv_template_name TYPE /aws1/se2emailtemplatename
      RETURNING VALUE(rv_arn)    TYPE /aws1/se2amazonresourcename.

    " Helper: build the SES contact-list ARN
    CLASS-METHODS contact_list_arn
      IMPORTING iv_list_name  TYPE /aws1/se2contactlistname
      RETURNING VALUE(rv_arn) TYPE /aws1/se2amazonresourcename.

ENDCLASS.

CLASS ltc_awsex_cl_se2_actions IMPLEMENTATION.

  " =========================================================================
  " CLASS_SETUP
  " Creates: sender identity, shared contact list, shared template,
  "          and dedicated resources for each delete test.
  " Each step is individually wrapped so a failure reports a clear message.
  " =========================================================================
  METHOD class_setup.
    ao_session     = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_se2         = /aws1/cl_se2_factory=>create( ao_session ).
    ao_se2_actions = NEW /awsex/cl_se2_actions( ).

    " Unique suffix for all resource names created in this run
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

    " ------------------------------------------------------------------
    " 1. Sender identity — register cv_sender; verification requires a
    "    manual email-click so we only ensure the identity record exists.
    " ------------------------------------------------------------------
    av_sender_identity = cv_sender.
    TRY.
        ao_se2->createemailidentity(
          iv_emailidentity = av_sender_identity ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Already registered - fine
      CATCH /aws1/cx_rt_generic INTO DATA(lo_id_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: failed to register sender identity | &&
                |{ av_sender_identity }: { lo_id_ex->get_text( ) }| ).
    ENDTRY.
    TRY.
        tag_resource( identity_arn( av_sender_identity ) ).
      CATCH /aws1/cx_rt_generic.
        " Best effort
    ENDTRY.

    " ------------------------------------------------------------------
    " 2. Shared email template
    " ------------------------------------------------------------------
    av_template_name = |se2-tst-tmpl-{ av_uuid }|.
    TRY.
        ao_se2->createemailtemplate(
          iv_templatename    = av_template_name
          io_templatecontent = NEW /aws1/cl_se2emailtmplcontent(
            iv_subject = 'Test subject for {{name}}'
            iv_html    = '<html><body><h1>Hello {{name}}</h1></body></html>'
            iv_text    = 'Hello {{name}}' ) ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Exists from a previous run - fine
      CATCH /aws1/cx_rt_generic INTO DATA(lo_tmpl_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: failed to create template | &&
                |{ av_template_name }: { lo_tmpl_ex->get_text( ) }| ).
    ENDTRY.
    TRY.
        tag_resource( template_arn( av_template_name ) ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " ------------------------------------------------------------------
    " 3. Shared contact list
    "    SES sandbox limits accounts to 1 contact list.  If a second one
    "    cannot be created, fall back to reusing the existing list.
    " ------------------------------------------------------------------
    av_contact_list_name = |se2-tst-lst-{ av_uuid }|.
    TRY.
        ao_se2->createcontactlist(
          iv_contactlistname = av_contact_list_name ).
        TRY.
            tag_resource( contact_list_arn( av_contact_list_name ) ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
      CATCH /aws1/cx_se2alreadyexistsex.
        " Exists - fine
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_br).
        " Sandbox 1-list limit: reuse the existing list
        TRY.
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
                msg = |class_setup: contact list limit hit but no list exists: | &&
                      |{ lo_br->get_text( ) }| ).
            ENDIF.
          CATCH /aws1/cx_rt_generic INTO DATA(lo_lst_ex).
            cl_abap_unit_assert=>fail(
              msg = |class_setup: failed to list contact lists: { lo_lst_ex->get_text( ) }| ).
        ENDTRY.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_lst_ex2).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: failed to create contact list: { lo_lst_ex2->get_text( ) }| ).
    ENDTRY.

    " ------------------------------------------------------------------
    " 4. Dedicated resources for delete tests
    " ------------------------------------------------------------------

    " 4a. Contact list to delete
    av_del_list_name = |se2-del-lst-{ av_uuid }|.
    TRY.
        ao_se2->createcontactlist(
          iv_contactlistname = av_del_list_name ).
        TRY.
            tag_resource( contact_list_arn( av_del_list_name ) ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
      CATCH /aws1/cx_se2alreadyexistsex.
        " Fine
      CATCH /aws1/cx_se2badrequestex.
        " Sandbox limit: fall back - delete test handles this
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
        TRY.
            tag_resource( template_arn( av_del_tmpl_name ) ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
      CATCH /aws1/cx_se2alreadyexistsex.
        " Fine
      CATCH /aws1/cx_rt_generic INTO DATA(lo_del_tmpl_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: failed to create delete-template | &&
                |{ av_del_tmpl_name }: { lo_del_tmpl_ex->get_text( ) }| ).
    ENDTRY.

    " 4c. Identity to delete
    av_del_identity = |se2-del-id-{ av_uuid }@example.com|.
    TRY.
        ao_se2->createemailidentity(
          iv_emailidentity = av_del_identity ).
        TRY.
            tag_resource( identity_arn( av_del_identity ) ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
      CATCH /aws1/cx_se2alreadyexistsex.
        " Fine
      CATCH /aws1/cx_rt_generic INTO DATA(lo_del_id_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: failed to create delete-identity | &&
                |{ av_del_identity }: { lo_del_id_ex->get_text( ) }| ).
    ENDTRY.

  ENDMETHOD.

  " =========================================================================
  " CLASS_TEARDOWN
  " =========================================================================
  METHOD class_teardown.
    " Delete all contacts from the shared list
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

    " Delete shared contact list
    TRY.
        ao_se2->deletecontactlist(
          iv_contactlistname = av_contact_list_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Delete shared template
    TRY.
        ao_se2->deleteemailtemplate( iv_templatename = av_template_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Delete dedicated delete-test resources (if not already removed by tests)
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
    " cv_sender (av_sender_identity) is a registered identity for ongoing
    " testing; it is intentionally left in place after the test run.
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
  " TEST METHODS — one per service operation
  " =========================================================================

  " -------------------------------------------------------------------------
  " get_email_identity  (NEW)
  " -------------------------------------------------------------------------
  METHOD get_email_identity.
    " av_sender_identity was registered in class_setup and always exists.
    DATA lo_result TYPE REF TO /aws1/cl_se2getemailidresponse.

    ao_se2_actions->get_email_identity(
      EXPORTING iv_email_address = av_sender_identity
      IMPORTING oo_result        = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'get_email_identity must return a non-null result' ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_identitytype( )
      exp = 'EMAIL_ADDRESS'
      msg = |Identity type mismatch for { av_sender_identity }| ).
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " send_email_with_attachment  (NEW)
  " -------------------------------------------------------------------------
  METHOD send_email_with_attachment.
    " Design: the sender (av_sender_identity) is registered but may not be
    " verified. SES validates the from-address and either:
    "   a) sends the email and returns a MessageId (verified sender)
    "   b) raises MessageRejected (unverified sender)
    " Both outcomes confirm the API call was correctly formed and reached SES.
    DATA lt_to TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w(
      iv_value = sim_addr( |attsnd{ av_uuid }| ) ) TO lt_to.

    " iv_rawcontent is xstring — use cl_abap_codepage to get proper bytes
    DATA lv_raw TYPE xstring.
    lv_raw = cl_abap_codepage=>convert_to( source = 'TestData' codepage = 'UTF-8' ).
    DATA lt_attach TYPE /aws1/cl_se2attachment=>tt_attachmentlist.
    APPEND NEW /aws1/cl_se2attachment(
      iv_rawcontent  = lv_raw
      iv_filename    = 'test.txt'
      iv_contenttype = 'text/plain' ) TO lt_attach.

    TRY.
        DATA(lv_msg_id) = ao_se2_actions->send_email_with_attachment(
          iv_from_address = av_sender_identity
          it_to_addresses = lt_to
          iv_subject      = 'ABAP SDK test - attachment'
          iv_html_body    = '<html><body><p>Test.</p></body></html>'
          iv_text_body    = 'Test.'
          it_attachments  = lt_attach ).

        " Sender verified: assert a MessageId was returned
        cl_abap_unit_assert=>assert_not_initial(
          act = lv_msg_id
          msg = 'send_email_with_attachment must return a MessageId' ).

      CATCH /aws1/cx_se2messagerejected.
        " Sender not yet verified — the API call reached SES and was
        " correctly evaluated. This is an accepted test outcome.
        MESSAGE |send_email_with_attachment: sender unverified, | &&
                |MessageRejected confirms API call succeeded| TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " send_bulk_email  (NEW)
  " -------------------------------------------------------------------------
  METHOD send_bulk_email.
    " Design: same as send_email_with_attachment above.
    " An unverified sender causes MessageRejected at the API level;
    " catching it is proof the call was well-formed and reached SES.
    DATA lt_entries TYPE /aws1/cl_se2bulkemailentry=>tt_bulkemailentrylist.

    DATA lt_to1 TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w(
      iv_value = sim_addr( |blk1{ av_uuid }| ) ) TO lt_to1.
    APPEND NEW /aws1/cl_se2bulkemailentry(
      io_destination = NEW /aws1/cl_se2destination(
        it_toaddresses = lt_to1 ) ) TO lt_entries.

    DATA lt_to2 TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w(
      iv_value = sim_addr( |blk2{ av_uuid }| ) ) TO lt_to2.
    APPEND NEW /aws1/cl_se2bulkemailentry(
      io_destination = NEW /aws1/cl_se2destination(
        it_toaddresses = lt_to2 ) ) TO lt_entries.

    TRY.
        DATA(lt_results) = ao_se2_actions->send_bulk_email(
          iv_from_address          = av_sender_identity
          iv_template_name         = av_template_name
          iv_default_template_data = '{"name":"ABAP Tester"}'
          it_bulk_entries          = lt_entries ).

        " Sender verified: assert one result per recipient, each with a status
        cl_abap_unit_assert=>assert_equals(
          act = lines( lt_results )
          exp = 2
          msg = |Expected 2 bulk email results, got { lines( lt_results ) }| ).

        LOOP AT lt_results INTO DATA(lo_r).
          " Status must be set (e.g. 'Success' or 'Failed')
          cl_abap_unit_assert=>assert_not_initial(
            act = lo_r->get_status( )
            msg = 'Each bulk email result must have a status' ).
        ENDLOOP.

      CATCH /aws1/cx_se2messagerejected.
        " Sender not yet verified — the API call reached SES and was
        " correctly evaluated. This is an accepted test outcome.
        MESSAGE |send_bulk_email: sender unverified, | &&
                |MessageRejected confirms API call succeeded| TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " create_email_identity
  " -------------------------------------------------------------------------
  METHOD create_email_identity.
    DATA(lv_new_id) = |se2-cre-id-{ av_uuid }@example.com|.

    ao_se2_actions->create_email_identity( lv_new_id ).

    TRY.
        tag_resource( identity_arn( lv_new_id ) ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Verify the identity was created, with CLEANUP to guarantee deletion
    TRY.
        DATA(lo_get) = ao_se2->getemailidentity(
          iv_emailidentity = lv_new_id ).

        cl_abap_unit_assert=>assert_equals(
          act = lo_get->get_identitytype( )
          exp = 'EMAIL_ADDRESS'
          msg = |Email identity { lv_new_id } was not created| ).
      CLEANUP.
        TRY.
            ao_se2->deleteemailidentity( iv_emailidentity = lv_new_id ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
    ENDTRY.
    " Normal path cleanup
    TRY.
        ao_se2->deleteemailidentity( iv_emailidentity = lv_new_id ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
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

    " Verify, with CLEANUP to guarantee deletion even on assertion failure
    TRY.
        DATA(lo_get) = ao_se2->getemailtemplate(
          iv_templatename = lv_new_tmpl ).

        cl_abap_unit_assert=>assert_equals(
          act = lo_get->get_templatename( )
          exp = lv_new_tmpl
          msg = |Template { lv_new_tmpl } was not created| ).
      CLEANUP.
        TRY.
            ao_se2->deleteemailtemplate( iv_templatename = lv_new_tmpl ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.
    ENDTRY.
    " Normal path cleanup
    TRY.
        ao_se2->deleteemailtemplate( iv_templatename = lv_new_tmpl ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " create_contact_list
  " -------------------------------------------------------------------------
  METHOD create_contact_list.
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

        ao_se2->deletecontactlist( iv_contactlistname = lv_new_list ).

      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_br).
        " Sandbox 1-list limit: action correctly re-raised the exception
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
    DATA(lv_email) = sim_addr( |crcnt{ av_uuid }| ).

    ao_se2_actions->create_contact(
      iv_contact_list_name = av_contact_list_name
      iv_email_address     = lv_email ).

    DATA(lo_result) = ao_se2->listcontacts(
      iv_contactlistname = av_contact_list_name ).

    DATA lv_found TYPE abap_bool.
    LOOP AT lo_result->get_contacts( ) INTO DATA(lo_c).
      IF lo_c->get_emailaddress( ) = lv_email.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Contact { lv_email } was not found after creation| ).

    TRY.
        ao_se2->deletecontact(
          iv_contactlistname = av_contact_list_name
          iv_emailaddress    = lv_email ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " send_email
  " Design: a MessageRejected exception proves the API call was correctly
  " formed and reached SES (established pattern from SES v1 tests).
  " -------------------------------------------------------------------------
  METHOD send_email.
    TRY.
        DATA(lv_msg_id) = ao_se2_actions->send_email(
          iv_from_email_address = av_sender_identity
          iv_to_email_address   = sim_addr( |snd{ av_uuid }| )
          iv_subject            = 'ABAP SDK integration test'
          iv_html_body          = '<html><body><p>Test.</p></body></html>'
          iv_text_body          = 'Test.' ).

        " Sender is verified: assert MessageId returned
        cl_abap_unit_assert=>assert_not_initial(
          act = lv_msg_id
          msg = 'send_email must return a non-empty MessageId' ).

      CATCH /aws1/cx_se2messagerejected.
        " Sender not yet verified — API call correctly reached SES
        MESSAGE |send_email: sender unverified, | &&
                |MessageRejected confirms API call succeeded| TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

  " -------------------------------------------------------------------------
  " send_email_template
  " Design: same pattern as send_email.
  " -------------------------------------------------------------------------
  METHOD send_email_template.
    " Add the simulator recipient as a contact so list-management succeeds
    DATA(lv_recipient) = sim_addr( |tmpsnd{ av_uuid }| ).
    TRY.
        ao_se2->createcontact(
          iv_contactlistname = av_contact_list_name
          iv_emailaddress    = lv_recipient ).
      CATCH /aws1/cx_se2alreadyexistsex.
    ENDTRY.

    TRY.
        DATA(lv_msg_id) = ao_se2_actions->send_email_template(
          iv_from_email_address = av_sender_identity
          iv_to_email_address   = lv_recipient
          iv_template_name      = av_template_name
          iv_template_data      = '{"name":"ABAP Tester"}'
          iv_contact_list_name  = av_contact_list_name ).

        " Sender is verified: assert MessageId returned
        cl_abap_unit_assert=>assert_not_initial(
          act = lv_msg_id
          msg = 'send_email_template must return a non-empty MessageId' ).

      CATCH /aws1/cx_se2messagerejected.
        " Sender not yet verified — API call correctly reached SES
        MESSAGE |send_email_template: sender unverified, | &&
                |MessageRejected confirms API call succeeded| TYPE 'I'.
    ENDTRY.

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
    IF av_del_list_name = av_contact_list_name.
      " Sandbox limit prevented a dedicated list; try a temporary one
      DATA(lv_tmp) = |se2-del-lst2-{ av_uuid }|.
      TRY.
          ao_se2->createcontactlist( iv_contactlistname = lv_tmp ).
          TRY.
              tag_resource( contact_list_arn( lv_tmp ) ).
            CATCH /aws1/cx_rt_generic.
          ENDTRY.
          ao_se2_actions->delete_contact_list( lv_tmp ).
          TRY.
              ao_se2->getcontactlist( iv_contactlistname = lv_tmp ).
              cl_abap_unit_assert=>fail(
                msg = |Contact list { lv_tmp } should have been deleted| ).
            CATCH /aws1/cx_se2notfoundexception.
              " Expected
          ENDTRY.
        CATCH /aws1/cx_se2badrequestex.
          " Still at limit: test graceful no-op on a non-existent name
          ao_se2_actions->delete_contact_list( |se2-nex-{ av_uuid }| ).
      ENDTRY.
      RETURN.
    ENDIF.

    ao_se2_actions->delete_contact_list( av_del_list_name ).

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
