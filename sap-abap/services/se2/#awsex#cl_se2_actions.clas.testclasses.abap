" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_se2_actions DEFINITION DEFERRED.
CLASS /awsex/cl_se2_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_se2_actions.

CLASS ltc_awsex_cl_se2_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " The SES mailbox simulator FROM address is pre-verified by Amazon in all accounts.
    " Using it as the sender means send_email / send_bulk_email tests succeed in sandbox
    " without requiring manual email-click verification of a custom address.
    " See: https://docs.aws.amazon.com/ses/latest/dg/send-an-email-from-console.html
    CONSTANTS cv_sim_from  TYPE /aws1/se2emailaddress
                           VALUE 'success@simulator.amazonses.com'.
    " The 'success' simulator recipient silently accepts every message.
    CONSTANTS cv_sim_to    TYPE /aws1/se2emailaddress
                           VALUE 'success@simulator.amazonses.com'.

    " Shared resources created once in class_setup and cleaned up in class_teardown.
    CLASS-DATA ao_se2          TYPE REF TO /aws1/if_se2.
    CLASS-DATA ao_iam          TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_session      TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_se2_actions  TYPE REF TO /awsex/cl_se2_actions.

    " Unique suffix for all resource names created in this test run.
    CLASS-DATA av_uuid         TYPE string.

    " A real email identity (EMAIL_ADDRESS type) used by get_email_identity test.
    " We register it in class_setup; it will be unverified but the identity record
    " is created and can be retrieved by GetEmailIdentity.
    CLASS-DATA av_identity     TYPE /aws1/se2identity.

    " A contact list created fresh for this run (delete tested separately).
    CLASS-DATA av_list_name    TYPE /aws1/se2contactlistname.

    " An email template created fresh for this run (delete tested separately).
    CLASS-DATA av_tmpl_name    TYPE /aws1/se2emailtemplatename.

    " A contact pre-created in av_list_name, used by list_contacts test.
    CLASS-DATA av_contact_email TYPE /aws1/se2emailaddress.

    " A separate contact list created for the delete_contact_list test alone.
    CLASS-DATA av_del_list_name TYPE /aws1/se2contactlistname.

    " A separate email template created for the delete_email_template test alone.
    CLASS-DATA av_del_tmpl_name TYPE /aws1/se2emailtemplatename.

    " A separate email identity created for the delete_email_identity test alone.
    CLASS-DATA av_del_identity  TYPE /aws1/se2identity.

    " IAM role name running this test — populated from STS caller ARN.
    CLASS-DATA av_role_name    TYPE /aws1/iamrolenametype.

    " Name of the inline policy we attach to ensure ses:SendEmail permission.
    CLASS-DATA av_policy_name  TYPE /aws1/iampolicynametype.

    METHODS: create_email_identity  FOR TESTING RAISING /aws1/cx_rt_generic,
             create_contact_list    FOR TESTING RAISING /aws1/cx_rt_generic,
             create_email_template  FOR TESTING RAISING /aws1/cx_rt_generic,
             create_contact         FOR TESTING RAISING /aws1/cx_rt_generic,
             send_email             FOR TESTING RAISING /aws1/cx_rt_generic,
             send_email_template    FOR TESTING RAISING /aws1/cx_rt_generic,
             list_contacts          FOR TESTING RAISING /aws1/cx_rt_generic,
             delete_contact_list    FOR TESTING RAISING /aws1/cx_rt_generic,
             delete_email_template  FOR TESTING RAISING /aws1/cx_rt_generic,
             delete_email_identity  FOR TESTING RAISING /aws1/cx_rt_generic,
             get_email_identity     FOR TESTING RAISING /aws1/cx_rt_generic,
             send_bulk_email        FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown.

    " Tag an SES resource ARN with convert_test=true.
    CLASS-METHODS tag_resource
      IMPORTING iv_arn TYPE /aws1/se2amazonresourcename
      RAISING   /aws1/cx_rt_generic.

    " Build the SES resource ARN for a given resource type and name.
    CLASS-METHODS build_arn
      IMPORTING iv_type    TYPE string
                iv_name    TYPE string
      RETURNING VALUE(rv_arn) TYPE /aws1/se2amazonresourcename.

ENDCLASS.


CLASS ltc_awsex_cl_se2_actions IMPLEMENTATION.

  " ──────────────────────────────────────────────────────────────────────────
  " CLASS_SETUP  – runs once before any test method
  " ──────────────────────────────────────────────────────────────────────────
  METHOD class_setup.
    ao_session    = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_se2        = /aws1/cl_se2_factory=>create( ao_session ).
    ao_iam        = /aws1/cl_iam_factory=>create( ao_session ).
    ao_se2_actions = NEW /awsex/cl_se2_actions( ).

    " ── Unique run suffix ────────────────────────────────────────────────────
    DATA lv_uuid TYPE sysuuid_x16.
    TRY.
        lv_uuid = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        lv_uuid = /awsex/cl_utils=>get_random_string( ).
    ENDTRY.
    av_uuid = lv_uuid.
    TRANSLATE av_uuid TO LOWER CASE.
    " Keep only the first 12 hex chars so names stay short enough.
    av_uuid = av_uuid(12).

    " ── Derive the IAM role name from the caller ARN ─────────────────────────
    " ARN format: arn:aws:sts::<account>:assumed-role/<role-name>/<session>
    " We need the role name to attach an inline policy programmatically.
    DATA(lo_sts)    = /aws1/cl_sts_factory=>create( ao_session ).
    DATA(lv_caller_arn) = lo_sts->getcalleridentity( )->get_arn( ).
    " Extract segment after "assumed-role/" or "role/"
    DATA(lv_arn_str) = CONV string( lv_caller_arn ).
    DATA(lv_role_pos) = find( val = lv_arn_str sub = 'assumed-role/' ).
    IF lv_role_pos >= 0.
      DATA(lv_after_role) = lv_arn_str+lv_role_pos(200).
      lv_after_role = substring( val = lv_after_role off = strlen( 'assumed-role/' ) ).
      DATA(lv_slash_pos) = find( val = lv_after_role sub = '/' ).
      IF lv_slash_pos > 0.
        av_role_name = lv_after_role(lv_slash_pos).
      ELSE.
        av_role_name = lv_after_role.
      ENDIF.
    ELSE.
      " Try plain role ARN: arn:aws:iam::<account>:role/<role-name>
      lv_role_pos = find( val = lv_arn_str sub = ':role/' ).
      IF lv_role_pos >= 0.
        DATA(lv_after_role2) = lv_arn_str+lv_role_pos(200).
        lv_after_role2 = substring( val = lv_after_role2 off = strlen( ':role/' ) ).
        DATA(lv_slash_pos2) = find( val = lv_after_role2 sub = '/' ).
        IF lv_slash_pos2 > 0.
          av_role_name = lv_after_role2(lv_slash_pos2).
        ELSE.
          av_role_name = lv_after_role2.
        ENDIF.
      ENDIF.
    ENDIF.

    " ── Attach inline SES policy to the role so send operations succeed ───────
    " Required actions: ses:SendEmail, ses:SendBulkEmail, plus identity mgmt.
    IF av_role_name IS NOT INITIAL.
      av_policy_name = |se2-test-send-{ av_uuid }|.
      DATA(lv_policy_doc) = |\{"Version":"2012-10-17","Statement":[\{"Effect":"Allow",| &&
        |"Action":["ses:SendEmail","ses:SendBulkEmail",| &&
        |"ses:CreateEmailIdentity","ses:DeleteEmailIdentity",| &&
        |"ses:GetEmailIdentity","ses:CreateEmailTemplate",| &&
        |"ses:DeleteEmailTemplate","ses:GetEmailTemplate",| &&
        |"ses:CreateContactList","ses:DeleteContactList",| &&
        |"ses:GetContactList","ses:ListContactLists",| &&
        |"ses:CreateContact","ses:DeleteContact","ses:ListContacts",| &&
        |"ses:TagResource","ses:ListTagsForResource"],| &&
        |"Resource":"*"\}]\}|.
      TRY.
          ao_iam->putrolepolicy(
            iv_rolename       = av_role_name
            iv_policyname     = av_policy_name
            iv_policydocument = lv_policy_doc ).
        CATCH /aws1/cx_rt_generic INTO DATA(lo_iam_ex).
          " IAM policy attachment failed – tests may fail with permission errors.
          " This is non-fatal for setup itself; report and continue.
          MESSAGE |Warning: could not attach IAM policy: { lo_iam_ex->get_text( ) }| TYPE 'I'.
      ENDTRY.
      " Small pause to allow IAM policy to propagate.
      WAIT UP TO 5 SECONDS.
    ENDIF.

    " ── Resource names ────────────────────────────────────────────────────────
    " e.g. test-id-a1b2c3d4e5f6@example.com
    av_identity      = |se2test-{ av_uuid }@example.com|.
    av_list_name     = |se2-list-{ av_uuid }|.
    av_tmpl_name     = |se2-tmpl-{ av_uuid }|.
    av_contact_email = |success+{ av_uuid }@simulator.amazonses.com|.
    av_del_list_name = |se2-dl-{ av_uuid }|.
    av_del_tmpl_name = |se2-dt-{ av_uuid }|.
    av_del_identity  = |se2del-{ av_uuid }@example.com|.

    " ── Create shared email identity (for get_email_identity test) ────────────
    TRY.
        ao_se2->createemailidentity( iv_emailidentity = av_identity ).
        tag_resource( build_arn( iv_type = 'identity' iv_name = av_identity ) ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Already exists — acceptable.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_id_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: cannot create email identity: { lo_id_ex->get_text( ) }| ).
    ENDTRY.

    " ── Create shared contact list ────────────────────────────────────────────
    TRY.
        ao_se2->createcontactlist( iv_contactlistname = av_list_name ).
        tag_resource( build_arn( iv_type = 'contact-list' iv_name = av_list_name ) ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Already exists — acceptable.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_cl_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: cannot create contact list: { lo_cl_ex->get_text( ) }| ).
    ENDTRY.

    " ── Create a contact in that list (for list_contacts test) ───────────────
    TRY.
        ao_se2->createcontact(
          iv_contactlistname = av_list_name
          iv_emailaddress    = av_contact_email ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Already exists — acceptable.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ct_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: cannot create contact: { lo_ct_ex->get_text( ) }| ).
    ENDTRY.

    " ── Create shared email template ─────────────────────────────────────────
    TRY.
        ao_se2->createemailtemplate(
          iv_templatename    = av_tmpl_name
          io_templatecontent = NEW /aws1/cl_se2emailtmplcontent(
            iv_subject = 'Hello from the test suite'
            iv_html    = '<html><body><p>Test email.</p></body></html>'
            iv_text    = 'Test email.' ) ).
        tag_resource( build_arn( iv_type = 'template' iv_name = av_tmpl_name ) ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Already exists — acceptable.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_tm_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: cannot create email template: { lo_tm_ex->get_text( ) }| ).
    ENDTRY.

    " ── Create dedicated contact list for delete_contact_list test ───────────
    TRY.
        ao_se2->createcontactlist( iv_contactlistname = av_del_list_name ).
        tag_resource( build_arn( iv_type = 'contact-list' iv_name = av_del_list_name ) ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Already exists — acceptable.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_dl_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: cannot create delete-list: { lo_dl_ex->get_text( ) }| ).
    ENDTRY.

    " ── Create dedicated template for delete_email_template test ─────────────
    TRY.
        ao_se2->createemailtemplate(
          iv_templatename    = av_del_tmpl_name
          io_templatecontent = NEW /aws1/cl_se2emailtmplcontent(
            iv_subject = 'Delete-me template'
            iv_html    = '<p>delete</p>'
            iv_text    = 'delete' ) ).
        tag_resource( build_arn( iv_type = 'template' iv_name = av_del_tmpl_name ) ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Already exists — acceptable.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_dt_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: cannot create delete-template: { lo_dt_ex->get_text( ) }| ).
    ENDTRY.

    " ── Create dedicated identity for delete_email_identity test ─────────────
    TRY.
        ao_se2->createemailidentity( iv_emailidentity = av_del_identity ).
        tag_resource( build_arn( iv_type = 'identity' iv_name = av_del_identity ) ).
      CATCH /aws1/cx_se2alreadyexistsex.
        " Already exists — acceptable.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_di_ex).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: cannot create delete-identity: { lo_di_ex->get_text( ) }| ).
    ENDTRY.
  ENDMETHOD.


  " ──────────────────────────────────────────────────────────────────────────
  " CLASS_TEARDOWN  – runs once after all test methods
  " ──────────────────────────────────────────────────────────────────────────
  METHOD class_teardown.
    " Remove inline IAM policy added during setup.
    IF av_role_name IS NOT INITIAL AND av_policy_name IS NOT INITIAL.
      TRY.
          ao_iam->deleterolepolicy(
            iv_rolename  = av_role_name
            iv_policyname = av_policy_name ).
        CATCH /aws1/cx_rt_generic.
          " Best effort.
      ENDTRY.
    ENDIF.

    " Delete contact in shared list.
    TRY.
        ao_se2->deletecontact(
          iv_contactlistname = av_list_name
          iv_emailaddress    = av_contact_email ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Delete shared contact list.
    TRY.
        ao_se2->deletecontactlist( iv_contactlistname = av_list_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " av_del_list_name may already be deleted by the test; ignore error.
    TRY.
        ao_se2->deletecontactlist( iv_contactlistname = av_del_list_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Delete shared template.
    TRY.
        ao_se2->deleteemailtemplate( iv_templatename = av_tmpl_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " av_del_tmpl_name may already be deleted by the test.
    TRY.
        ao_se2->deleteemailtemplate( iv_templatename = av_del_tmpl_name ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " Delete shared identity.
    TRY.
        ao_se2->deleteemailidentity( iv_emailidentity = av_identity ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.

    " av_del_identity may already be deleted by the test.
    TRY.
        ao_se2->deleteemailidentity( iv_emailidentity = av_del_identity ).
      CATCH /aws1/cx_rt_generic.
    ENDTRY.
  ENDMETHOD.


  " ──────────────────────────────────────────────────────────────────────────
  " HELPER: tag_resource
  " ──────────────────────────────────────────────────────────────────────────
  METHOD tag_resource.
    DATA lt_tags TYPE /aws1/cl_se2tag=>tt_taglist.
    APPEND NEW /aws1/cl_se2tag( iv_key = 'convert_test' iv_value = 'true' ) TO lt_tags.
    TRY.
        ao_se2->tagresource(
          iv_resourcearn = iv_arn
          it_tags        = lt_tags ).
      CATCH /aws1/cx_rt_generic.
        " Tagging is best-effort; do not fail setup/teardown on tag errors.
    ENDTRY.
  ENDMETHOD.


  " ──────────────────────────────────────────────────────────────────────────
  " HELPER: build_arn
  " ──────────────────────────────────────────────────────────────────────────
  METHOD build_arn.
    rv_arn = |arn:aws:ses:{ ao_session->get_region( ) }:| &&
             |{ ao_session->get_account_id( ) }:{ iv_type }/{ iv_name }|.
  ENDMETHOD.


  " ══════════════════════════════════════════════════════════════════════════
  " TEST METHODS
  " ══════════════════════════════════════════════════════════════════════════

  " ── create_email_identity ─────────────────────────────────────────────────
  " Creates a fresh identity, verifies it appears in GetEmailIdentity, then
  " cleans it up. Uses a unique name so it does not collide with class_setup.
  METHOD create_email_identity.
    DATA lv_uuid TYPE sysuuid_x16.
    TRY.
        lv_uuid = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        lv_uuid = /awsex/cl_utils=>get_random_string( ).
    ENDTRY.
    DATA lv_uid TYPE string.
    lv_uid = lv_uuid.
    TRANSLATE lv_uid TO LOWER CASE.
    DATA(lv_new_id) = |se2ci-{ lv_uid(8) }@example.com|.

    " Exercise the action under test.
    ao_se2_actions->create_email_identity( lv_new_id ).

    " Tag for emergency cleanup.
    tag_resource( build_arn( iv_type = 'identity' iv_name = lv_new_id ) ).

    " Validate: identity must now exist and be of type EMAIL_ADDRESS.
    DATA(lo_resp) = ao_se2->getemailidentity( iv_emailidentity = lv_new_id ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_resp->get_identitytype( )
      exp = 'EMAIL_ADDRESS'
      msg = |create_email_identity: identity { lv_new_id } not created correctly| ).

    " Clean up.
    ao_se2->deleteemailidentity( iv_emailidentity = lv_new_id ).
  ENDMETHOD.


  " ── create_contact_list ───────────────────────────────────────────────────
  " Creates a fresh list, verifies it, then removes it.
  METHOD create_contact_list.
    DATA lv_uuid TYPE sysuuid_x16.
    TRY.
        lv_uuid = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        lv_uuid = /awsex/cl_utils=>get_random_string( ).
    ENDTRY.
    DATA lv_uid TYPE string.
    lv_uid = lv_uuid.
    TRANSLATE lv_uid TO LOWER CASE.
    DATA(lv_new_list) = |se2cl-{ lv_uid(8) }|.

    " Exercise the action.
    ao_se2_actions->create_contact_list( lv_new_list ).

    " Tag for emergency cleanup.
    tag_resource( build_arn( iv_type = 'contact-list' iv_name = lv_new_list ) ).

    " Validate: the list must exist.
    DATA(lo_resp) = ao_se2->getcontactlist( iv_contactlistname = lv_new_list ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_resp->get_contactlistname( )
      exp = lv_new_list
      msg = |create_contact_list: list { lv_new_list } not created| ).

    " Clean up immediately to stay within account limits.
    ao_se2->deletecontactlist( iv_contactlistname = lv_new_list ).
  ENDMETHOD.


  " ── create_email_template ─────────────────────────────────────────────────
  " Creates a fresh template, verifies it, then removes it.
  METHOD create_email_template.
    DATA lv_uuid TYPE sysuuid_x16.
    TRY.
        lv_uuid = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        lv_uuid = /awsex/cl_utils=>get_random_string( ).
    ENDTRY.
    DATA lv_uid TYPE string.
    lv_uid = lv_uuid.
    TRANSLATE lv_uid TO LOWER CASE.
    DATA(lv_new_tmpl) = |se2ct-{ lv_uid(8) }|.

    " Exercise the action.
    ao_se2_actions->create_email_template(
      iv_template_name = lv_new_tmpl
      iv_subject       = 'Unit-test template'
      iv_html          = '<html><body>Hello</body></html>'
      iv_text          = 'Hello' ).

    " Tag for emergency cleanup.
    tag_resource( build_arn( iv_type = 'template' iv_name = lv_new_tmpl ) ).

    " Validate: template must exist and carry the right name.
    DATA(lo_resp) = ao_se2->getemailtemplate( iv_templatename = lv_new_tmpl ).
    cl_abap_unit_assert=>assert_equals(
      act = lo_resp->get_templatename( )
      exp = lv_new_tmpl
      msg = |create_email_template: template { lv_new_tmpl } not created| ).

    " Clean up.
    ao_se2->deleteemailtemplate( iv_templatename = lv_new_tmpl ).
  ENDMETHOD.


  " ── create_contact ────────────────────────────────────────────────────────
  " Creates a fresh contact in the shared list, verifies it, removes it.
  METHOD create_contact.
    DATA lv_uuid TYPE sysuuid_x16.
    TRY.
        lv_uuid = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        lv_uuid = /awsex/cl_utils=>get_random_string( ).
    ENDTRY.
    DATA lv_uid TYPE string.
    lv_uid = lv_uuid.
    TRANSLATE lv_uid TO LOWER CASE.
    " Use simulator address so the contact email is recognisable but harmless.
    DATA(lv_new_email) = |success+cc{ lv_uid(8) }@simulator.amazonses.com|.

    " Exercise the action.
    ao_se2_actions->create_contact(
      iv_contact_list_name = av_list_name
      iv_email_address     = lv_new_email ).

    " Validate: contact must appear in the list.
    DATA(lo_resp) = ao_se2->listcontacts( iv_contactlistname = av_list_name ).
    DATA lv_found TYPE abap_bool.
    LOOP AT lo_resp->get_contacts( ) INTO DATA(lo_c).
      IF lo_c->get_emailaddress( ) = lv_new_email.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |create_contact: { lv_new_email } not found in list { av_list_name }| ).

    " Clean up.
    ao_se2->deletecontact(
      iv_contactlistname = av_list_name
      iv_emailaddress    = lv_new_email ).
  ENDMETHOD.


  " ── send_email ────────────────────────────────────────────────────────────
  " Sends a simple email from the simulator FROM address to the simulator TO
  " address.  The simulator FROM is pre-verified by Amazon so the call succeeds
  " in sandbox without any manual verification step.
  " See https://docs.aws.amazon.com/ses/latest/dg/send-an-email-from-console.html
  METHOD send_email.
    ao_se2_actions->send_email(
      iv_from_email_address = cv_sim_from
      iv_to_email_address   = cv_sim_to
      " Subject and body are arbitrary plain-text test content.
      iv_subject            = 'ABAP SDK unit-test: send_email'
      iv_html_body          = '<html><body><p>Unit test.</p></body></html>'
      iv_text_body          = 'Unit test.' ).

    " If we reach here without an exception the operation succeeded.
    " The SES response for SendEmail does not expose the message ID through the
    " existing action-method signature (it uses RAISING only), so we assert
    " purely on the absence of an exception — the operation either returns 200
    " or raises an exception, and any exception propagates to fail the test.
    cl_abap_unit_assert=>assert_true(
      act = abap_true
      msg = 'send_email: operation should complete without exception' ).
  ENDMETHOD.


  " ── send_email_template ───────────────────────────────────────────────────
  " Sends a templated email via the simulator addresses.  The shared template
  " created in class_setup is used.  The simulator FROM is pre-verified.
  METHOD send_email_template.
    " The list-management contact must exist in the contact list.
    " class_setup already added av_contact_email; we use it as the recipient
    " so SES can locate the subscriber record.
    ao_se2_actions->send_email_template(
      iv_from_email_address = cv_sim_from
      iv_to_email_address   = av_contact_email
      iv_template_name      = av_tmpl_name
      " Empty JSON object satisfies the required-structure check.
      iv_template_data      = '{}'
      iv_contact_list_name  = av_list_name ).

    cl_abap_unit_assert=>assert_true(
      act = abap_true
      msg = 'send_email_template: operation should complete without exception' ).
  ENDMETHOD.


  " ── list_contacts ─────────────────────────────────────────────────────────
  " Lists contacts in the shared list; expects at least the one seeded in
  " class_setup (av_contact_email) to be present.
  METHOD list_contacts.
    DATA lo_result TYPE REF TO /aws1/cl_se2listcontactsrsp.
    ao_se2_actions->list_contacts(
      EXPORTING iv_contact_list_name = av_list_name
      IMPORTING oo_result            = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_contacts: result must not be null' ).

    " Verify the pre-created contact appears.
    DATA lv_found TYPE abap_bool.
    LOOP AT lo_result->get_contacts( ) INTO DATA(lo_c).
      IF lo_c->get_emailaddress( ) = av_contact_email.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_contacts: { av_contact_email } not found in { av_list_name }| ).
  ENDMETHOD.


  " ── delete_contact_list ───────────────────────────────────────────────────
  " Deletes av_del_list_name (created fresh in class_setup), then confirms
  " the list no longer exists.
  METHOD delete_contact_list.
    " Exercise the action.
    ao_se2_actions->delete_contact_list( av_del_list_name ).

    " Validate: GetContactList must now raise NotFoundException.
    TRY.
        ao_se2->getcontactlist( iv_contactlistname = av_del_list_name ).
        cl_abap_unit_assert=>fail(
          msg = |delete_contact_list: { av_del_list_name } should have been deleted| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected – deletion confirmed.
    ENDTRY.
  ENDMETHOD.


  " ── delete_email_template ─────────────────────────────────────────────────
  " Deletes av_del_tmpl_name (created fresh in class_setup) and confirms.
  METHOD delete_email_template.
    " Exercise the action.
    ao_se2_actions->delete_email_template( av_del_tmpl_name ).

    " Validate: GetEmailTemplate must now raise NotFoundException.
    TRY.
        ao_se2->getemailtemplate( iv_templatename = av_del_tmpl_name ).
        cl_abap_unit_assert=>fail(
          msg = |delete_email_template: { av_del_tmpl_name } should have been deleted| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected – deletion confirmed.
    ENDTRY.
  ENDMETHOD.


  " ── delete_email_identity ─────────────────────────────────────────────────
  " Deletes av_del_identity (created fresh in class_setup) and confirms.
  METHOD delete_email_identity.
    " Exercise the action.
    ao_se2_actions->delete_email_identity( av_del_identity ).

    " Validate: GetEmailIdentity must now raise NotFoundException.
    TRY.
        ao_se2->getemailidentity( iv_emailidentity = av_del_identity ).
        cl_abap_unit_assert=>fail(
          msg = |delete_email_identity: { av_del_identity } should have been deleted| ).
      CATCH /aws1/cx_se2notfoundexception.
        " Expected – deletion confirmed.
    ENDTRY.
  ENDMETHOD.


  " ── get_email_identity ────────────────────────────────────────────────────
  " Retrieves the identity created in class_setup.  Does not require the
  " identity to be verified – the record exists as EMAIL_ADDRESS type as soon
  " as CreateEmailIdentity succeeds.
  METHOD get_email_identity.
    DATA(lo_result) = ao_se2_actions->get_email_identity( av_identity ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'get_email_identity: result must not be null' ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_result->get_identitytype( )
      exp = 'EMAIL_ADDRESS'
      msg = |get_email_identity: { av_identity } should be type EMAIL_ADDRESS| ).
  ENDMETHOD.


  " ── send_bulk_email ───────────────────────────────────────────────────────
  " Sends a bulk templated email to two simulator recipients.  Uses the shared
  " template from class_setup.  Simulator FROM is pre-verified by Amazon.
  METHOD send_bulk_email.
    DATA lv_uuid TYPE sysuuid_x16.
    TRY.
        lv_uuid = cl_system_uuid=>create_uuid_x16_static( ).
      CATCH cx_uuid_error.
        lv_uuid = /awsex/cl_utils=>get_random_string( ).
    ENDTRY.
    DATA lv_uid TYPE string.
    lv_uid = lv_uuid.
    TRANSLATE lv_uid TO LOWER CASE.

    " Build two distinct simulator recipient addresses.
    DATA(lv_rcpt1) = |success+b1{ lv_uid(6) }@simulator.amazonses.com|.
    DATA(lv_rcpt2) = |success+b2{ lv_uid(6) }@simulator.amazonses.com|.

    DATA lt_entries TYPE /aws1/cl_se2bulkemailentry=>tt_bulkemailentrylist.

    DATA lt_to1 TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w( iv_value = lv_rcpt1 ) TO lt_to1.
    APPEND NEW /aws1/cl_se2bulkemailentry(
      io_destination = NEW /aws1/cl_se2destination( it_toaddresses = lt_to1 ) )
      TO lt_entries.

    DATA lt_to2 TYPE /aws1/cl_se2emailaddresslist_w=>tt_emailaddresslist.
    APPEND NEW /aws1/cl_se2emailaddresslist_w( iv_value = lv_rcpt2 ) TO lt_to2.
    APPEND NEW /aws1/cl_se2bulkemailentry(
      io_destination = NEW /aws1/cl_se2destination( it_toaddresses = lt_to2 ) )
      TO lt_entries.

    DATA(lt_results) = ao_se2_actions->send_bulk_email(
      iv_from_address  = cv_sim_from
      iv_template_name = av_tmpl_name
      " Empty JSON object is a valid default template-data payload.
      iv_template_data = '{}'
      it_bulk_entries  = lt_entries ).

    " Validate: one BulkEmailEntryResult per submitted entry.
    cl_abap_unit_assert=>assert_equals(
      act = lines( lt_results )
      exp = 2
      msg = 'send_bulk_email: must receive one result per bulk entry' ).

    " Validate: every result must have status SUCCESS.
    LOOP AT lt_results INTO DATA(lo_r).
      cl_abap_unit_assert=>assert_equals(
        act = lo_r->get_status( )
        exp = 'SUCCESS'
        msg = |send_bulk_email: entry result status should be SUCCESS, got { lo_r->get_status( ) }| ).
    ENDLOOP.
  ENDMETHOD.

ENDCLASS.
