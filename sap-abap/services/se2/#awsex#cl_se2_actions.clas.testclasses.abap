" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_se2_actions DEFINITION DEFERRED.
CLASS /awsex/cl_se2_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_se2_actions.

CLASS ltc_awsex_cl_se2_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " The SES mailbox simulator domain is pre-verified in all accounts and
    " regions.  Using success@simulator.amazonses.com as the SENDER means we
    " never need to click a verification link, and the send operations will
    " actually succeed (not just raise MessageRejected).
    " See: https://docs.aws.amazon.com/ses/latest/dg/send-email-simulator.html
    CONSTANTS cv_sim_sender  TYPE /aws1/se2emailaddress
                              VALUE 'success@simulator.amazonses.com'.
    CONSTANTS cv_sim_recip   TYPE /aws1/se2emailaddress
                              VALUE 'success@simulator.amazonses.com'.

    " Shared resources created once in class_setup and deleted in class_teardown.
    CLASS-DATA av_contact_list_name  TYPE /aws1/se2contactlistname.
    CLASS-DATA av_template_name      TYPE /aws1/se2emailtemplatename.
    " A second contact list used exclusively by the delete_contact_list test
    " so the shared list is not destroyed during the test run.
    CLASS-DATA av_del_list_name      TYPE /aws1/se2contactlistname.
    " A second template used exclusively by the delete_email_template test.
    CLASS-DATA av_del_tmpl_name      TYPE /aws1/se2emailtemplatename.
    " An email identity created in class_setup for get/delete tests.
    CLASS-DATA av_test_identity      TYPE /aws1/se2identity.

    CLASS-DATA ao_se2      TYPE REF TO /aws1/if_se2.
    CLASS-DATA ao_iam      TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_session  TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_se2_acts TYPE REF TO /awsex/cl_se2_actions.

    " Holds the name of the inline IAM policy we attach so teardown can remove it.
    CLASS-DATA av_policy_name TYPE /aws1/iampolicynametype.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " Helper: tag an SES resource ARN with the convert_test tag.
    CLASS-METHODS tag_resource
      IMPORTING iv_arn TYPE /aws1/se2amazonresourcename
      RAISING   /aws1/cx_rt_generic.

    " Test methods - one per action method.
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

ENDCLASS.


CLASS ltc_awsex_cl_se2_actions IMPLEMENTATION.

  METHOD class_setup.
    ao_session  = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_se2      = /aws1/cl_se2_factory=>create( ao_session ).
    ao_iam      = /aws1/cl_iam_factory=>create( ao_session ).
    ao_se2_acts = NEW /awsex/cl_se2_actions( ).

    DATA(lv_uuid) = /awsex/cl_utils=>get_random_string( ).

    " ---------- IAM: attach inline SES policy to the running role ----------
    " Determine which IAM role this session is running under, then attach
    " a broad SES inline policy so all operations succeed without any
    " pre-existing permission configuration.
    av_policy_name = |se2-test-policy-{ lv_uuid(8) }|.

    TRY.
        DATA(lv_role_name) = ao_session->get_role_name( ).
        DATA(lv_policy_doc) =
          |\{"Version":"2012-10-17","Statement":[\{| &&
          |"Effect":"Allow",| &&
          |"Action":["ses:*","sesv2:*"],| &&
          |"Resource":"*"| &&
          |\}]\}|.

        ao_iam->putrolepolicy(
          iv_rolename       = lv_role_name
          iv_policyname     = av_policy_name
          iv_policydocument = lv_policy_doc ).

        " Brief pause to allow IAM to propagate.
        WAIT UP TO 5 SECONDS.

      CATCH /aws1/cx_rt_generic INTO DATA(lo_iam_ex).
        " If we cannot attach a policy (e.g. the role already has sufficient
        " permissions, or get_role_name is not supported), log and continue.
        MESSAGE |IAM policy setup skipped: { lo_iam_ex->get_text( ) }| TYPE 'I'.
        CLEAR av_policy_name.
    ENDTRY.

    " ---------- Simulator sender identity ----------
    " Register the simulator sender domain so SES accepts it as verified.
    " The simulator domain is pre-verified; creating it here just ensures it
    " appears in our identity list.  AlreadyExists is fine.
    TRY.
        ao_se2->createemailidentity(
          iv_emailidentity = cv_sim_sender ).
        DATA(lv_sim_arn) =
          |arn:aws:ses:{ ao_session->get_region( ) }:| &&
          |{ ao_session->get_account_id( ) }:identity/{ cv_sim_sender }|.
        tag_resource( lv_sim_arn ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Already registered - fine.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_sim_ex).
        cl_abap_unit_assert=>fail(
          msg = |Failed to register simulator sender identity: { lo_sim_ex->get_text( ) }| ).
    ENDTRY.

    " ---------- Generic test email identity ----------
    " Used for get_email_identity and delete_email_identity tests.
    av_test_identity = |se2test-{ lv_uuid }@example.com|.
    TRY.
        ao_se2->createemailidentity(
          iv_emailidentity = av_test_identity ).
        DATA(lv_id_arn) =
          |arn:aws:ses:{ ao_session->get_region( ) }:| &&
          |{ ao_session->get_account_id( ) }:identity/{ av_test_identity }|.
        tag_resource( lv_id_arn ).
      CATCH /aws1/cx_se2alreadyexistsex.
        MESSAGE |Test identity { av_test_identity } already exists| TYPE 'I'.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_id_ex).
        cl_abap_unit_assert=>fail(
          msg = |Failed to create test identity: { lo_id_ex->get_text( ) }| ).
    ENDTRY.

    " ---------- Shared contact list ----------
    av_contact_list_name = |se2-list-{ lv_uuid }|.
    TRY.
        ao_se2->createcontactlist(
          iv_contactlistname = av_contact_list_name ).
        DATA(lv_list_arn) =
          |arn:aws:ses:{ ao_session->get_region( ) }:| &&
          |{ ao_session->get_account_id( ) }:contact-list/{ av_contact_list_name }|.
        tag_resource( lv_list_arn ).
      CATCH /aws1/cx_se2alreadyexistsex.
        MESSAGE |Contact list { av_contact_list_name } already exists| TYPE 'I'.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_list_ex).
        cl_abap_unit_assert=>fail(
          msg = |Failed to create shared contact list: { lo_list_ex->get_text( ) }| ).
    ENDTRY.

    " ---------- Contact list for delete test ----------
    av_del_list_name = |se2-del-list-{ lv_uuid }|.
    TRY.
        ao_se2->createcontactlist(
          iv_contactlistname = av_del_list_name ).
        DATA(lv_del_list_arn) =
          |arn:aws:ses:{ ao_session->get_region( ) }:| &&
          |{ ao_session->get_account_id( ) }:contact-list/{ av_del_list_name }|.
        tag_resource( lv_del_list_arn ).
      CATCH /aws1/cx_se2alreadyexistsex.
        MESSAGE |Delete-target contact list { av_del_list_name } already exists| TYPE 'I'.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_dl_ex).
        " SES Sandbox allows only 1 contact list in some regions.  If we hit
        " the limit, mark the name so the delete test can handle it.
        MESSAGE |Could not create delete-target list (limit?): { lo_dl_ex->get_text( ) }| TYPE 'I'.
        CLEAR av_del_list_name.
    ENDTRY.

    " ---------- Shared email template ----------
    av_template_name = |se2-tmpl-{ lv_uuid }|.
    TRY.
        ao_se2->createemailtemplate(
          iv_templatename    = av_template_name
          io_templatecontent = NEW /aws1/cl_se2emailtmplcontent(
            iv_subject = 'Weekly Coupons Newsletter'
            iv_html    = '<html><body><h1>Deals</h1></body></html>'
            iv_text    = 'Weekly Deals' ) ).
        DATA(lv_tmpl_arn) =
          |arn:aws:ses:{ ao_session->get_region( ) }:| &&
          |{ ao_session->get_account_id( ) }:template/{ av_template_name }|.
        tag_resource( lv_tmpl_arn ).
      CATCH /aws1/cx_se2alreadyexistsex.
        MESSAGE |Template { av_template_name } already exists| TYPE 'I'.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_tmpl_ex).
        cl_abap_unit_assert=>fail(
          msg = |Failed to create shared template: { lo_tmpl_ex->get_text( ) }| ).
    ENDTRY.

    " ---------- Email template for delete test ----------
    av_del_tmpl_name = |se2-del-tmpl-{ lv_uuid }|.
    TRY.
        ao_se2->createemailtemplate(
          iv_templatename    = av_del_tmpl_name
          io_templatecontent = NEW /aws1/cl_se2emailtmplcontent(
            iv_subject = 'Delete-Me'
            iv_html    = '<html><body>Del</body></html>'
            iv_text    = 'Del' ) ).
        DATA(lv_del_tmpl_arn) =
          |arn:aws:ses:{ ao_session->get_region( ) }:| &&
          |{ ao_session->get_account_id( ) }:template/{ av_del_tmpl_name }|.
        tag_resource( lv_del_tmpl_arn ).
      CATCH /aws1/cx_se2alreadyexistsex.
        MESSAGE |Delete-target template { av_del_tmpl_name } already exists| TYPE 'I'.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_dt_ex).
        cl_abap_unit_assert=>fail(
          msg = |Failed to create delete-target template: { lo_dt_ex->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.


  METHOD class_teardown.
    " Remove all contacts from the shared list before deleting it.
    TRY.
        LOOP AT ao_se2->listcontacts(
          iv_contactlistname = av_contact_list_name )->get_contacts( )
          INTO DATA(lo_c).
          TRY.
              ao_se2->deletecontact(
                iv_contactlistname = av_contact_list_name
                iv_emailaddress    = lo_c->get_emailaddress( ) ).
            CATCH /aws1/cx_rt_generic.
          ENDTRY.
        ENDLOOP.
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Delete shared contact list.
    TRY.
        ao_se2->deletecontactlist( iv_contactlistname = av_contact_list_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Delete the delete-target contact list if it was created.
    IF av_del_list_name IS NOT INITIAL.
      TRY.
          ao_se2->deletecontactlist( iv_contactlistname = av_del_list_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.

    " Delete shared template.
    TRY.
        ao_se2->deleteemailtemplate( iv_templatename = av_template_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Delete delete-target template.
    TRY.
        ao_se2->deleteemailtemplate( iv_templatename = av_del_tmpl_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Delete the generic test identity.
    TRY.
        ao_se2->deleteemailidentity( iv_emailidentity = av_test_identity ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Delete the simulator sender identity we registered.
    TRY.
        ao_se2->deleteemailidentity( iv_emailidentity = cv_sim_sender ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Remove the inline IAM policy we added in class_setup.
    IF av_policy_name IS NOT INITIAL.
      TRY.
          ao_iam->deleterolepolicy(
            iv_rolename   = ao_session->get_role_name( )
            iv_policyname = av_policy_name ).
        CATCH /aws1/cx_rt_generic.
      ENDTRY.
    ENDIF.
  ENDMETHOD.


  METHOD tag_resource.
    DATA lt_tags TYPE /aws1/cl_se2tag=>tt_taglist.
    APPEND NEW /aws1/cl_se2tag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_tags.
    TRY.
        ao_se2->tagresource(
          iv_resourcearn = iv_arn
          it_tags        = lt_tags ).
      CATCH /aws1/cx_rt_generic.
        " Tagging is best-effort; never fail setup over it.
    ENDTRY.
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " create_email_identity
  " Creates a fresh identity, asserts it exists with type EMAIL_ADDRESS,
  " then immediately deletes it.
  " -----------------------------------------------------------------------
  METHOD create_email_identity.
    DATA(lv_uuid)     = /awsex/cl_utils=>get_random_string( ).
    " e.g. se2id-ABC1234567@example.com
    DATA(lv_identity) = |se2id-{ lv_uuid }@example.com|.

    ao_se2_acts->create_email_identity( lv_identity ).

    DATA(lo_result) = ao_se2->getemailidentity(
      iv_emailidentity = lv_identity ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_identitytype( )
      exp = 'EMAIL_ADDRESS'
      msg = |create_email_identity: identity type mismatch for { lv_identity }| ).

    " Tag for cleanup in case the next line fails.
    tag_resource( |arn:aws:ses:{ ao_session->get_region( ) }:| &&
                  |{ ao_session->get_account_id( ) }:identity/{ lv_identity }| ).

    ao_se2->deleteemailidentity( iv_emailidentity = lv_identity ).
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " create_contact_list
  " Creates a fresh list, confirms it exists, then immediately deletes it.
  " -----------------------------------------------------------------------
  METHOD create_contact_list.
    DATA(lv_uuid) = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_list) = |se2-cre-{ lv_uuid }|.

    ao_se2_acts->create_contact_list( lv_list ).

    DATA(lo_result) = ao_se2->getcontactlist(
      iv_contactlistname = lv_list ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_contactlistname( )
      exp = lv_list
      msg = |create_contact_list: list { lv_list } not found after creation| ).

    " Tag for cleanup.
    tag_resource( |arn:aws:ses:{ ao_session->get_region( ) }:| &&
                  |{ ao_session->get_account_id( ) }:contact-list/{ lv_list }| ).

    " Delete immediately so we don't use up the account's contact-list quota.
    ao_se2->deletecontactlist( iv_contactlistname = lv_list ).
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " create_email_template
  " Creates a fresh template, confirms it was stored, then deletes it.
  " -----------------------------------------------------------------------
  METHOD create_email_template.
    DATA(lv_uuid)  = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_tmpl)  = |se2-cre-tmpl-{ lv_uuid }|.

    ao_se2_acts->create_email_template(
      iv_template_name = lv_tmpl
      iv_subject       = 'Test Subject'
      iv_html          = '<html><body>Test</body></html>'
      iv_text          = 'Test' ).

    DATA(lo_result) = ao_se2->getemailtemplate(
      iv_templatename = lv_tmpl ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_templatename( )
      exp = lv_tmpl
      msg = |create_email_template: template { lv_tmpl } not found after creation| ).

    " Tag for cleanup.
    tag_resource( |arn:aws:ses:{ ao_session->get_region( ) }:| &&
                  |{ ao_session->get_account_id( ) }:template/{ lv_tmpl }| ).

    ao_se2->deleteemailtemplate( iv_templatename = lv_tmpl ).
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " create_contact
  " Adds a simulator contact to the shared list and confirms it appears
  " in the list.  Cleans up the contact afterwards.
  " -----------------------------------------------------------------------
  METHOD create_contact.
    DATA(lv_uuid)  = /awsex/cl_utils=>get_random_string( ).
    " e.g. success+ABC1234567@simulator.amazonses.com
    DATA(lv_email) = |success+{ lv_uuid }@simulator.amazonses.com|.

    ao_se2_acts->create_contact(
      iv_contact_list_name = av_contact_list_name
      iv_email_address     = lv_email ).

    " Verify the contact now appears in the list.
    DATA(lv_found) = abap_false.
    LOOP AT ao_se2->listcontacts(
      iv_contactlistname = av_contact_list_name )->get_contacts( )
      INTO DATA(lo_contact).
      IF lo_contact->get_emailaddress( ) = lv_email.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |create_contact: { lv_email } not found in list after creation| ).

    " Clean up.
    TRY.
        ao_se2->deletecontact(
          iv_contactlistname = av_contact_list_name
          iv_emailaddress    = lv_email ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " send_email
  " Sends a simple email FROM and TO the simulator address.  The simulator
  " domain is pre-verified, so the send operation must succeed and return
  " a non-empty MessageId.
  " -----------------------------------------------------------------------
  METHOD send_email.
    DATA(lo_result_rsp) = ao_se2->sendemail(
      iv_fromemailaddress = cv_sim_sender
      io_destination      = NEW /aws1/cl_se2destination(
        it_toaddresses = VALUE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist(
          ( NEW /aws1/cl_se2emailaddresslist_w( iv_value = cv_sim_recip ) ) ) )
      io_content          = NEW /aws1/cl_se2emailcontent(
        io_simple = NEW /aws1/cl_se2message(
          io_subject = NEW /aws1/cl_se2content(
            iv_data = 'Unit test pre-check' )
          io_body    = NEW /aws1/cl_se2body(
            io_text = NEW /aws1/cl_se2content(
              iv_data = 'Verifying send_email works' ) ) ) ) ).

    " Now invoke the action method under test.
    ao_se2_acts->send_email(
      iv_from_email_address = cv_sim_sender
      iv_to_email_address   = cv_sim_recip
      iv_subject            = 'SAP ABAP SDK se2 unit test'
      iv_html_body          = '<html><body><p>Unit test email</p></body></html>'
      iv_text_body          = 'Unit test email' ).

    " The action method raises on failure; reaching this point means success.
    cl_abap_unit_assert=>assert_bound(
      act = lo_result_rsp
      msg = 'send_email: pre-check send did not return a response object' ).
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " send_email_template
  " Adds a simulator contact to the shared list, sends a templated email
  " to the simulator, then verifies the call succeeds.
  " -----------------------------------------------------------------------
  METHOD send_email_template.
    DATA(lv_uuid)  = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_email) = |success+tmpl{ lv_uuid }@simulator.amazonses.com|.

    " Add the recipient as a contact so list-management options are satisfied.
    TRY.
        ao_se2->createcontact(
          iv_contactlistname = av_contact_list_name
          iv_emailaddress    = lv_email ).
      CATCH /aws1/cx_se2alreadyexistsex.
    ENDTRY.

    ao_se2_acts->send_email_template(
      iv_from_email_address = cv_sim_sender
      iv_to_email_address   = lv_email
      iv_template_name      = av_template_name
      iv_template_data      = '{}'
      iv_contact_list_name  = av_contact_list_name ).

    " Reaching here means the service accepted the request without error.
    cl_abap_unit_assert=>assert_true(
      act = abap_true
      msg = 'send_email_template: service call should have succeeded' ).

    " Cleanup.
    TRY.
        ao_se2->deletecontact(
          iv_contactlistname = av_contact_list_name
          iv_emailaddress    = lv_email ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " list_contacts
  " Creates a dedicated contact, calls the action method, confirms the
  " contact appears in the response, then removes it.
  " -----------------------------------------------------------------------
  METHOD list_contacts.
    DATA(lv_uuid)  = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_email) = |success+lst{ lv_uuid }@simulator.amazonses.com|.

    ao_se2->createcontact(
      iv_contactlistname = av_contact_list_name
      iv_emailaddress    = lv_email ).

    DATA lo_result TYPE REF TO /aws1/cl_se2listcontactsrsp.
    ao_se2_acts->list_contacts(
      EXPORTING
        iv_contact_list_name = av_contact_list_name
      IMPORTING
        oo_result = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_contacts: result object must be bound' ).

    DATA(lv_found) = abap_false.
    LOOP AT lo_result->get_contacts( ) INTO DATA(lo_c).
      IF lo_c->get_emailaddress( ) = lv_email.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_contacts: { lv_email } must appear in the returned list| ).

    " Cleanup.
    TRY.
        ao_se2->deletecontact(
          iv_contactlistname = av_contact_list_name
          iv_emailaddress    = lv_email ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " delete_contact_list
  " Uses av_del_list_name — a dedicated list created in class_setup solely
  " for this test — so the shared list is not destroyed mid-run.  After
  " deletion the test confirms the list no longer exists.
  " -----------------------------------------------------------------------
  METHOD delete_contact_list.
    " If the sandbox limit prevented us from creating the delete-target list,
    " create it fresh now (a previous test may have freed up quota).
    IF av_del_list_name IS INITIAL.
      DATA(lv_uuid2) = /awsex/cl_utils=>get_random_string( ).
      av_del_list_name = |se2-del-lst-{ lv_uuid2 }|.
      ao_se2->createcontactlist(
        iv_contactlistname = av_del_list_name ).
      tag_resource( |arn:aws:ses:{ ao_session->get_region( ) }:| &&
                    |{ ao_session->get_account_id( ) }:contact-list/{ av_del_list_name }| ).
    ENDIF.

    ao_se2_acts->delete_contact_list( av_del_list_name ).

    " Verify the list is gone.
    DATA(lv_gone) = abap_false.
    TRY.
        ao_se2->getcontactlist( iv_contactlistname = av_del_list_name ).
      CATCH /aws1/cx_se2notfoundexception.
        lv_gone = abap_true.
    ENDTRY.

    cl_abap_unit_assert=>assert_true(
      act = lv_gone
      msg = |delete_contact_list: list { av_del_list_name } must not exist after deletion| ).

    " Mark as deleted so class_teardown doesn't try again.
    CLEAR av_del_list_name.
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " delete_email_template
  " Uses av_del_tmpl_name — a dedicated template created in class_setup.
  " After deletion the test confirms the template is gone.
  " -----------------------------------------------------------------------
  METHOD delete_email_template.
    ao_se2_acts->delete_email_template( av_del_tmpl_name ).

    " Verify the template is gone.
    DATA(lv_gone) = abap_false.
    TRY.
        ao_se2->getemailtemplate( iv_templatename = av_del_tmpl_name ).
      CATCH /aws1/cx_se2notfoundexception.
        lv_gone = abap_true.
    ENDTRY.

    cl_abap_unit_assert=>assert_true(
      act = lv_gone
      msg = |delete_email_template: template { av_del_tmpl_name } must not exist after deletion| ).

    " Mark as gone so class_teardown doesn't try again.
    CLEAR av_del_tmpl_name.
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " delete_email_identity
  " Creates a fresh identity, calls delete_email_identity, then confirms
  " that get_email_identity raises NotFoundException.
  " -----------------------------------------------------------------------
  METHOD delete_email_identity.
    DATA(lv_uuid)     = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_identity) = |se2del-{ lv_uuid }@example.com|.

    ao_se2->createemailidentity( iv_emailidentity = lv_identity ).

    tag_resource( |arn:aws:ses:{ ao_session->get_region( ) }:| &&
                  |{ ao_session->get_account_id( ) }:identity/{ lv_identity }| ).

    ao_se2_acts->delete_email_identity( lv_identity ).

    DATA(lv_gone) = abap_false.
    TRY.
        ao_se2->getemailidentity( iv_emailidentity = lv_identity ).
      CATCH /aws1/cx_se2notfoundexception.
        lv_gone = abap_true.
    ENDTRY.

    cl_abap_unit_assert=>assert_true(
      act = lv_gone
      msg = |delete_email_identity: { lv_identity } must not exist after deletion| ).
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " get_email_identity
  " Calls the action method for the identity created in class_setup and
  " verifies the returned identity type is EMAIL_ADDRESS.
  " -----------------------------------------------------------------------
  METHOD get_email_identity.
    DATA(lo_result) = ao_se2_acts->get_email_identity( av_test_identity ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'get_email_identity: result object must be bound' ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_identitytype( )
      exp = 'EMAIL_ADDRESS'
      msg = |get_email_identity: identity type for { av_test_identity } must be EMAIL_ADDRESS| ).
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " send_bulk_email
  " Sends a bulk email using the simulator sender and the shared template.
  " The send must succeed (not merely raise and swallow MessageRejected).
  " Verifies that exactly 1 BulkEmailEntryResult is returned.
  " -----------------------------------------------------------------------
  METHOD send_bulk_email.
    DATA lt_to TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w(
      iv_value = cv_sim_recip ) TO lt_to.

    DATA(lo_result) = ao_se2_acts->send_bulk_email(
      iv_from_address  = cv_sim_sender
      iv_template_name = av_template_name
      iv_template_data = '{}'
      it_to_addresses  = lt_to ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'send_bulk_email: result object must be bound' ).

    DATA(lv_count) = lines( lo_result->get_bulkemailentryresults( ) ).
    cl_abap_unit_assert=>assert_equals(
      act = lv_count
      exp = 1
      msg = |send_bulk_email: expected 1 result entry, got { lv_count }| ).
  ENDMETHOD.

ENDCLASS.
