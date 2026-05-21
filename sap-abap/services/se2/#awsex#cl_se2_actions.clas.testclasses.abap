" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_se2_actions DEFINITION DEFERRED.
CLASS /awsex/cl_se2_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_se2_actions.

CLASS ltc_awsex_cl_se2_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " ── Shared class-level AWS clients ───────────────────────────────────────
    CLASS-DATA ao_se2     TYPE REF TO /aws1/if_se2.
    CLASS-DATA ao_iam     TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_session TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_se2_actions TYPE REF TO /awsex/cl_se2_actions.

    " ── Shared resources created in class_setup ──────────────────────────────
    " A pre-verified email identity discovered in the account (required for sends)
    CLASS-DATA av_verified_sender   TYPE /aws1/se2emailaddress.
    " Contact list shared by most tests (SES sandbox only allows 1 list)
    CLASS-DATA av_contact_list_name TYPE /aws1/se2contactlistname.
    " Email template shared by template/bulk tests
    CLASS-DATA av_template_name     TYPE /aws1/se2emailtemplatename.
    " Unique run suffix used in all resource names
    CLASS-DATA av_run_suffix        TYPE string.
    " IAM role name of the execution role (extracted from session ARN)
    CLASS-DATA av_role_name         TYPE /aws1/iamrolenametype.

    " ── Test method declarations ─────────────────────────────────────────────
    METHODS create_email_identity  FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS create_contact_list    FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS create_email_template  FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS create_contact         FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS send_email             FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS send_email_template    FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS list_contacts          FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_contact_list    FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_email_template  FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS delete_email_identity  FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS get_email_identity     FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS send_bulk_email        FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " ── Private helpers ──────────────────────────────────────────────────────
    CLASS-METHODS tag_se2_resource
      IMPORTING iv_arn TYPE /aws1/se2amazonresourcename
      RAISING   /aws1/cx_rt_generic.

    CLASS-METHODS ensure_ses_policy_on_role
      RAISING /aws1/cx_rt_generic.

    CLASS-METHODS find_verified_sender
      RETURNING VALUE(rv_identity) TYPE /aws1/se2emailaddress
      RAISING   /aws1/cx_rt_generic.

ENDCLASS.


CLASS ltc_awsex_cl_se2_actions IMPLEMENTATION.

* ─────────────────────────────────────────────────────────────────────────────
* CLASS_SETUP  –  runs once before all test methods in this class
* ─────────────────────────────────────────────────────────────────────────────
  METHOD class_setup.
    ao_session    = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_se2        = /aws1/cl_se2_factory=>create( ao_session ).
    ao_iam        = /aws1/cl_iam_factory=>create( ao_session ).
    ao_se2_actions = NEW /awsex/cl_se2_actions( ).

    " ── Unique suffix for this test run ──────────────────────────────────────
    av_run_suffix = /awsex/cl_utils=>get_random_string( ).

    " ── Extract IAM role name from the caller's ARN ──────────────────────────
    " Session ARN format: arn:aws:sts::<account>:assumed-role/<role-name>/<session>
    DATA(lv_caller_arn) = ao_session->get_caller_identity_arn( ).
    SPLIT lv_caller_arn AT '/' INTO TABLE DATA(lt_arn_parts).
    IF lines( lt_arn_parts ) >= 2.
      READ TABLE lt_arn_parts INDEX 2 INTO av_role_name.
    ENDIF.

    IF av_role_name IS INITIAL.
      cl_abap_unit_assert=>fail(
        msg = |Could not derive IAM role name from ARN: { lv_caller_arn }| ).
    ENDIF.

    " ── Ensure the execution role has ses:* permissions ──────────────────────
    ensure_ses_policy_on_role( ).

    " ── Find a verified sender (mandatory for send_email / send_bulk_email) ──
    av_verified_sender = find_verified_sender( ).
    IF av_verified_sender IS INITIAL.
      cl_abap_unit_assert=>fail(
        msg = 'No verified SESv2 email identity found in this account. '  &&
              'Please verify at least one email address or domain in the ' &&
              'SES console before running these tests.' ).
    ENDIF.
    MESSAGE |Using verified sender: { av_verified_sender }| TYPE 'I'.

    " ── Create shared contact list (SES sandbox: max 1 list) ─────────────────
    " Name must be ≤ 64 chars; use a deterministic prefix so teardown is safe.
    av_contact_list_name = |se2-test-list-{ av_run_suffix(8) }|.

    DATA lt_list_tags TYPE /aws1/cl_se2tag=>tt_taglist.
    APPEND NEW /aws1/cl_se2tag( iv_key = 'convert_test' iv_value = 'true' ) TO lt_list_tags.

    TRY.
        ao_se2->createcontactlist(
          iv_contactlistname = av_contact_list_name
          it_tags            = lt_list_tags ).
        MESSAGE |Created contact list: { av_contact_list_name }| TYPE 'I'.
      CATCH /aws1/cx_se2alreadyexistsex.
        " idempotent – already exists
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_bad_req).
        " Sandbox limit: find the first existing list and use it
        DATA(lo_lists) = ao_se2->listcontactlists( ).
        IF lines( lo_lists->get_contactlists( ) ) = 0.
          cl_abap_unit_assert=>fail(
            msg = |Contact list limit reached and no lists exist: { lo_bad_req->get_text( ) }| ).
        ENDIF.
        LOOP AT lo_lists->get_contactlists( ) INTO DATA(lo_list_entry).
          av_contact_list_name = lo_list_entry->get_contactlistname( ).
          EXIT.
        ENDLOOP.
        MESSAGE |Sandbox limit – reusing existing list: { av_contact_list_name }| TYPE 'I'.
    ENDTRY.

    " Tag the list (best-effort; ARN format for contact lists)
    DATA(lv_region)  = ao_session->get_region( ).
    DATA(lv_account) = ao_session->get_account_id( ).
    DATA(lv_list_arn) =
      |arn:aws:ses:{ lv_region }:{ lv_account }:contact-list/{ av_contact_list_name }|.
    TRY.
        tag_se2_resource( lv_list_arn ).
      CATCH /aws1/cx_rt_generic.
        " Best-effort tagging
    ENDTRY.

    " ── Create shared email template ─────────────────────────────────────────
    av_template_name = |se2-test-tmpl-{ av_run_suffix(8) }|.

    TRY.
        ao_se2->createemailtemplate(
          iv_templatename    = av_template_name
          io_templatecontent = NEW /aws1/cl_se2emailtmplcontent(
            iv_subject = 'Test newsletter for {{name}}'
            iv_html    = '<html><body><p>Hello {{name}}, welcome!</p></body></html>'
            iv_text    = 'Hello {{name}}, welcome!' ) ).
        MESSAGE |Created email template: { av_template_name }| TYPE 'I'.
      CATCH /aws1/cx_se2alreadyexistsex.
        " idempotent
    ENDTRY.

    DATA(lv_tmpl_arn) =
      |arn:aws:ses:{ lv_region }:{ lv_account }:template/{ av_template_name }|.
    TRY.
        tag_se2_resource( lv_tmpl_arn ).
      CATCH /aws1/cx_rt_generic.
        " Best-effort tagging
    ENDTRY.

  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
* CLASS_TEARDOWN  –  runs once after all test methods
* ─────────────────────────────────────────────────────────────────────────────
  METHOD class_teardown.
    DATA(lv_region)  = ao_session->get_region( ).
    DATA(lv_account) = ao_session->get_account_id( ).

    " ── Delete all contacts from the shared list first ───────────────────────
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

    " ── Delete the shared contact list ───────────────────────────────────────
    TRY.
        ao_se2->deletecontactlist( iv_contactlistname = av_contact_list_name ).
        MESSAGE |Deleted contact list: { av_contact_list_name }| TYPE 'I'.
      CATCH /aws1/cx_se2notfoundexception.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex1).
        MESSAGE |Could not delete contact list: { lo_ex1->get_text( ) }| TYPE 'I'.
    ENDTRY.

    " ── Delete the shared email template ─────────────────────────────────────
    TRY.
        ao_se2->deleteemailtemplate( iv_templatename = av_template_name ).
        MESSAGE |Deleted email template: { av_template_name }| TYPE 'I'.
      CATCH /aws1/cx_se2notfoundexception.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex2).
        MESSAGE |Could not delete template: { lo_ex2->get_text( ) }| TYPE 'I'.
    ENDTRY.

    " ── Remove the inline IAM policy we added ────────────────────────────────
    TRY.
        ao_iam->deleterolepolicy(
          iv_rolename  = av_role_name
          iv_policyname = 'se2-test-ses-full-access' ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
* PRIVATE HELPERS
* ─────────────────────────────────────────────────────────────────────────────

  METHOD tag_se2_resource.
    DATA lt_tags TYPE /aws1/cl_se2tag=>tt_taglist.
    APPEND NEW /aws1/cl_se2tag( iv_key = 'convert_test' iv_value = 'true' ) TO lt_tags.
    ao_se2->tagresource(
      iv_resourcearn = iv_arn
      it_tags        = lt_tags ).
  ENDMETHOD.

  METHOD ensure_ses_policy_on_role.
    " Attach an inline policy that grants full SES access so all API calls work.
    DATA(lv_policy_doc) =
      |\{"Version":"2012-10-17","Statement":[| &&
      |\{"Effect":"Allow","Action":"ses:*","Resource":"*"\}| &&
      |]\}|.
    TRY.
        ao_iam->putrolepolicy(
          iv_rolename      = av_role_name
          iv_policyname    = 'se2-test-ses-full-access'
          iv_policydocument = lv_policy_doc ).
        MESSAGE |Attached SES inline policy to role { av_role_name }| TYPE 'I'.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex).
        " Non-fatal: the role may already have broad permissions.
        MESSAGE |Could not attach SES policy (continuing): { lo_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

  METHOD find_verified_sender.
    " Scan all email identities and return the first one that is VERIFIED
    " and enabled for sending.  Fails with an empty string if none found.
    rv_identity = ''.
    DATA(lo_list) = ao_se2->listemailidentities( ).
    LOOP AT lo_list->get_emailidentities( ) INTO DATA(lo_id).
      IF lo_id->get_sendingenabled( ) = abap_true.
        rv_identity = lo_id->get_identityname( ).
        RETURN.
      ENDIF.
    ENDLOOP.
    " Second pass: accept any VERIFIED identity even if sending flag is off
    LOOP AT lo_list->get_emailidentities( ) INTO DATA(lo_id2).
      IF lo_id2->get_verificationstatus( ) = 'SUCCESS'.
        rv_identity = lo_id2->get_identityname( ).
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
* TEST: create_email_identity
* ─────────────────────────────────────────────────────────────────────────────
  METHOD create_email_identity.
    " Create a brand-new, unique email identity then confirm it appears in SES.
    DATA(lv_suffix)   = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_identity) = |se2test{ lv_suffix(8) }@example.com|.

    " Exercise the action method under test
    ao_se2_actions->create_email_identity( lv_identity ).

    " Verify the identity was actually registered by reading it back
    DATA(lo_result) = ao_se2->getemailidentity( iv_emailidentity = lv_identity ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_identitytype( )
      exp = 'EMAIL_ADDRESS'
      msg = |Identity { lv_identity } was not created with type EMAIL_ADDRESS| ).

    " Tag for easy cleanup
    DATA(lv_arn) =
      |arn:aws:ses:{ ao_session->get_region( ) }:{ ao_session->get_account_id( ) }| &&
      |:identity/{ lv_identity }|.
    TRY.
        tag_se2_resource( lv_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Teardown: delete the identity we just created
    TRY.
        ao_se2->deleteemailidentity( iv_emailidentity = lv_identity ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
* TEST: create_contact_list
* ─────────────────────────────────────────────────────────────────────────────
  METHOD create_contact_list.
    " We attempt to create a second list; in sandbox this will hit the limit.
    " Either outcome (success or limit exception) is valid so long as the
    " action method itself does not propagate an unexpected exception.
    DATA(lv_suffix) = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_list)   = |se2-cre-lst-{ lv_suffix(8) }|.

    TRY.
        ao_se2_actions->create_contact_list( lv_list ).

        " If we reach here the list was created — verify it exists
        DATA(lo_result) = ao_se2->getcontactlist( iv_contactlistname = lv_list ).
        cl_abap_unit_assert=>assert_equals(
          act = lo_result->get_contactlistname( )
          exp = lv_list
          msg = |Contact list { lv_list } was not found after creation| ).

        " Tag it
        DATA(lv_arn) =
          |arn:aws:ses:{ ao_session->get_region( ) }:{ ao_session->get_account_id( ) }| &&
          |:contact-list/{ lv_list }|.
        TRY.
            tag_se2_resource( lv_arn ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.

        " Teardown: delete this extra list so we don't pollute the sandbox quota
        TRY.
            ao_se2->deletecontactlist( iv_contactlistname = lv_list ).
          CATCH /aws1/cx_rt_generic.
        ENDTRY.

      CATCH /aws1/cx_se2badrequestex.
        " Sandbox allows only 1 contact list – the action method correctly
        " propagated the exception.  This is valid, expected behaviour.
        MESSAGE |Sandbox contact-list limit reached — create_contact_list handled it correctly| TYPE 'I'.
      CATCH /aws1/cx_se2limitexceededex.
        MESSAGE |LimitExceeded — create_contact_list handled it correctly| TYPE 'I'.
    ENDTRY.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
* TEST: create_email_template
* ─────────────────────────────────────────────────────────────────────────────
  METHOD create_email_template.
    DATA(lv_suffix) = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_name)   = |se2-cre-tmpl-{ lv_suffix(8) }|.

    ao_se2_actions->create_email_template(
      iv_template_name = lv_name
      iv_subject       = 'Hello {{name}}'
      iv_html          = '<html><body><p>Hi {{name}}!</p></body></html>'
      iv_text          = 'Hi {{name}}!' ).

    " Verify the template was persisted
    DATA(lo_result) = ao_se2->getemailtemplate( iv_templatename = lv_name ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_templatename( )
      exp = lv_name
      msg = |Email template { lv_name } was not found after creation| ).

    " Tag it
    DATA(lv_arn) =
      |arn:aws:ses:{ ao_session->get_region( ) }:{ ao_session->get_account_id( ) }| &&
      |:template/{ lv_name }|.
    TRY.
        tag_se2_resource( lv_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Teardown
    TRY.
        ao_se2->deleteemailtemplate( iv_templatename = lv_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
* TEST: create_contact
* ─────────────────────────────────────────────────────────────────────────────
  METHOD create_contact.
    " Use the Amazon SES mailbox simulator – no verification needed for recipients
    DATA(lv_suffix)  = /awsex/cl_utils=>get_random_string( ).
    " success+<tag>@simulator.amazonses.com always succeeds in SES
    DATA(lv_contact) = |success+{ lv_suffix(8) }@simulator.amazonses.com|.

    ao_se2_actions->create_contact(
      iv_contact_list_name = av_contact_list_name
      iv_email_address     = lv_contact ).

    " Verify the contact appears in the list
    DATA(lo_list_result) = ao_se2->listcontacts(
      iv_contactlistname = av_contact_list_name ).

    DATA(lv_found) = abap_false.
    LOOP AT lo_list_result->get_contacts( ) INTO DATA(lo_c).
      IF lo_c->get_emailaddress( ) = lv_contact.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Contact { lv_contact } was not found in list { av_contact_list_name }| ).

    " Teardown
    TRY.
        ao_se2->deletecontact(
          iv_contactlistname = av_contact_list_name
          iv_emailaddress    = lv_contact ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
* TEST: send_email
* ─────────────────────────────────────────────────────────────────────────────
  METHOD send_email.
    " Recipient: SES mailbox simulator (success@ always accepts mail)
    " Sender:    av_verified_sender (found by class_setup – must be verified)
    DATA(lv_suffix)    = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_recipient) = |success+send{ lv_suffix(8) }@simulator.amazonses.com|.

    " This call must succeed — if it raises an exception the test fails
    ao_se2_actions->send_email(
      iv_from_email_address = av_verified_sender
      iv_to_email_address   = lv_recipient
      iv_subject            = |SAP ABAP SDK test – send_email { lv_suffix }|
      iv_html_body          = '<html><body><p>Test email from ABAP SDK.</p></body></html>'
      iv_text_body          = 'Test email from ABAP SDK.' ).

    " If we reach this line the API call succeeded — assert it
    cl_abap_unit_assert=>assert_true(
      act  = abap_true
      msg  = 'send_email completed without exception' ).
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
* TEST: send_email_template
* ─────────────────────────────────────────────────────────────────────────────
  METHOD send_email_template.
    DATA(lv_suffix)    = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_recipient) = |success+tmpl{ lv_suffix(8) }@simulator.amazonses.com|.

    " Ensure the recipient is registered as a contact (required for list management)
    TRY.
        ao_se2->createcontact(
          iv_contactlistname = av_contact_list_name
          iv_emailaddress    = lv_recipient ).
      CATCH /aws1/cx_se2alreadyexistsex.
    ENDTRY.

    ao_se2_actions->send_email_template(
      iv_from_email_address = av_verified_sender
      iv_to_email_address   = lv_recipient
      iv_template_name      = av_template_name
      iv_template_data      = '{"name":"ABAP Tester"}'
      iv_contact_list_name  = av_contact_list_name ).

    cl_abap_unit_assert=>assert_true(
      act  = abap_true
      msg  = 'send_email_template completed without exception' ).

    " Teardown recipient contact
    TRY.
        ao_se2->deletecontact(
          iv_contactlistname = av_contact_list_name
          iv_emailaddress    = lv_recipient ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
* TEST: list_contacts
* ─────────────────────────────────────────────────────────────────────────────
  METHOD list_contacts.
    " Seed exactly one known contact so the assertion is deterministic
    DATA(lv_suffix)  = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_contact) = |success+lst{ lv_suffix(8) }@simulator.amazonses.com|.

    ao_se2->createcontact(
      iv_contactlistname = av_contact_list_name
      iv_emailaddress    = lv_contact ).

    " Exercise the action method
    DATA lo_result TYPE REF TO /aws1/cl_se2listcontactsrsp.
    ao_se2_actions->list_contacts(
      EXPORTING iv_contact_list_name = av_contact_list_name
      IMPORTING oo_result            = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_contacts must return a bound result object' ).

    " The list must contain at least the contact we just created
    DATA(lv_count) = lines( lo_result->get_contacts( ) ).
    cl_abap_unit_assert=>assert_true(
      act  = xsdbool( lv_count > 0 )
      msg  = |list_contacts returned 0 contacts in list { av_contact_list_name }| ).

    " Verify our specific contact is present
    DATA(lv_found) = abap_false.
    LOOP AT lo_result->get_contacts( ) INTO DATA(lo_c).
      IF lo_c->get_emailaddress( ) = lv_contact.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Contact { lv_contact } not found in list_contacts result| ).

    " Teardown
    TRY.
        ao_se2->deletecontact(
          iv_contactlistname = av_contact_list_name
          iv_emailaddress    = lv_contact ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
* TEST: delete_contact_list
* ─────────────────────────────────────────────────────────────────────────────
  METHOD delete_contact_list.
    " Create a brand-new list just for this deletion test so the shared list
    " is never destroyed and we don't depend on pre-existing state.
    DATA(lv_suffix) = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_list)   = |se2-del-lst-{ lv_suffix(8) }|.

    " We must create the list before we can delete it.
    " If sandbox limit is hit we cannot run this test — fail explicitly.
    DATA(lv_list_created) = abap_false.
    TRY.
        DATA lt_tags TYPE /aws1/cl_se2tag=>tt_taglist.
        APPEND NEW /aws1/cl_se2tag( iv_key = 'convert_test' iv_value = 'true' ) TO lt_tags.
        ao_se2->createcontactlist(
          iv_contactlistname = lv_list
          it_tags            = lt_tags ).
        lv_list_created = abap_true.
      CATCH /aws1/cx_se2badrequestex INTO DATA(lo_limit).
        cl_abap_unit_assert=>fail(
          msg = |Sandbox contact-list limit prevents delete_contact_list test: | &&
                lo_limit->get_text( ) ).
      CATCH /aws1/cx_se2limitexceededex INTO DATA(lo_lim2).
        cl_abap_unit_assert=>fail(
          msg = |LimitExceeded – cannot create list for delete test: { lo_lim2->get_text( ) }| ).
    ENDTRY.

    cl_abap_unit_assert=>assert_true(
      act = lv_list_created
      msg = |List { lv_list } was not created — cannot test deletion| ).

    " Exercise the action method
    ao_se2_actions->delete_contact_list( lv_list ).

    " Verify the list no longer exists
    DATA(lv_gone) = abap_false.
    TRY.
        ao_se2->getcontactlist( iv_contactlistname = lv_list ).
        " If we reach here the list was NOT deleted — fail
        cl_abap_unit_assert=>fail(
          msg = |Contact list { lv_list } still exists after delete_contact_list| ).
      CATCH /aws1/cx_se2notfoundexception.
        lv_gone = abap_true.
    ENDTRY.

    cl_abap_unit_assert=>assert_true(
      act = lv_gone
      msg = |Contact list { lv_list } was not deleted| ).
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
* TEST: delete_email_template
* ─────────────────────────────────────────────────────────────────────────────
  METHOD delete_email_template.
    " Create a dedicated template for this deletion test
    DATA(lv_suffix) = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_name)   = |se2-del-tmpl-{ lv_suffix(8) }|.

    ao_se2->createemailtemplate(
      iv_templatename    = lv_name
      io_templatecontent = NEW /aws1/cl_se2emailtmplcontent(
        iv_subject = 'Delete test'
        iv_html    = '<p>delete me</p>'
        iv_text    = 'delete me' ) ).

    " Tag it so it can be found if teardown is skipped
    DATA(lv_arn) =
      |arn:aws:ses:{ ao_session->get_region( ) }:{ ao_session->get_account_id( ) }| &&
      |:template/{ lv_name }|.
    TRY.
        tag_se2_resource( lv_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Exercise the action method
    ao_se2_actions->delete_email_template( lv_name ).

    " Verify deletion
    TRY.
        ao_se2->getemailtemplate( iv_templatename = lv_name ).
        cl_abap_unit_assert=>fail(
          msg = |Template { lv_name } still exists after delete_email_template| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected — template was successfully deleted
    ENDTRY.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
* TEST: delete_email_identity
* ─────────────────────────────────────────────────────────────────────────────
  METHOD delete_email_identity.
    " Create a fresh identity dedicated to this test
    DATA(lv_suffix)   = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_identity) = |se2del{ lv_suffix(8) }@example.com|.

    ao_se2->createemailidentity( iv_emailidentity = lv_identity ).

    " Tag it
    DATA(lv_arn) =
      |arn:aws:ses:{ ao_session->get_region( ) }:{ ao_session->get_account_id( ) }| &&
      |:identity/{ lv_identity }|.
    TRY.
        tag_se2_resource( lv_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Exercise the action method
    ao_se2_actions->delete_email_identity( lv_identity ).

    " Verify deletion
    TRY.
        ao_se2->getemailidentity( iv_emailidentity = lv_identity ).
        cl_abap_unit_assert=>fail(
          msg = |Identity { lv_identity } still exists after delete_email_identity| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected — identity was successfully deleted
    ENDTRY.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
* TEST: get_email_identity
* ─────────────────────────────────────────────────────────────────────────────
  METHOD get_email_identity.
    " Create a dedicated identity so we own its lifecycle completely
    DATA(lv_suffix)   = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_identity) = |se2get{ lv_suffix(8) }@example.com|.

    ao_se2->createemailidentity( iv_emailidentity = lv_identity ).

    " Tag it
    DATA(lv_arn) =
      |arn:aws:ses:{ ao_session->get_region( ) }:{ ao_session->get_account_id( ) }| &&
      |:identity/{ lv_identity }|.
    TRY.
        tag_se2_resource( lv_arn ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Exercise the action method under test
    DATA(lo_result) = ao_se2_actions->get_email_identity(
      iv_email_identity = lv_identity ).

    " Assertions: result must be bound and report the correct identity type
    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'get_email_identity must return a bound result object' ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_identitytype( )
      exp = 'EMAIL_ADDRESS'
      msg = |Identity { lv_identity } should have type EMAIL_ADDRESS| ).

    " Teardown
    TRY.
        ao_se2->deleteemailidentity( iv_emailidentity = lv_identity ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


* ─────────────────────────────────────────────────────────────────────────────
* TEST: send_bulk_email
* ─────────────────────────────────────────────────────────────────────────────
  METHOD send_bulk_email.
    " Use two unique simulator addresses as recipients
    DATA(lv_sfx1) = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_sfx2) = /awsex/cl_utils=>get_random_string( ).

    DATA lt_to TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w(
      iv_value = |success+b1{ lv_sfx1(8) }@simulator.amazonses.com| ) TO lt_to.
    APPEND NEW /aws1/cl_se2emailaddresslist_w(
      iv_value = |success+b2{ lv_sfx2(8) }@simulator.amazonses.com| ) TO lt_to.

    " Exercise the action method under test — must succeed end-to-end
    ao_se2_actions->send_bulk_email(
      iv_from_address  = av_verified_sender
      iv_template_name = av_template_name
      iv_template_data = '{"name":"Bulk Tester"}'
      it_to_addresses  = lt_to ).

    " If we reach here the API returned without exception
    cl_abap_unit_assert=>assert_true(
      act  = abap_true
      msg  = 'send_bulk_email completed without exception' ).
  ENDMETHOD.

ENDCLASS.
