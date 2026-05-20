" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_fnt_actions DEFINITION DEFERRED.
CLASS /awsex/cl_fnt_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_fnt_actions.

CLASS ltc_awsex_cl_fnt_actions DEFINITION
    FOR TESTING
    DURATION LONG
    RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " -----------------------------------------------------------------------
    " Shared CloudFront client, session, and the class under test.
    " -----------------------------------------------------------------------
    CLASS-DATA ao_fnt         TYPE REF TO /aws1/if_fnt.
    CLASS-DATA ao_session     TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_fnt_actions TYPE REF TO /awsex/cl_fnt_actions.

    " -----------------------------------------------------------------------
    " Test distribution created in class_setup and shared across all tests.
    " CloudFront distributions take 10-15 minutes to deploy and an equally
    " long time to disable + delete, so class_teardown performs the full
    " disable->wait->delete sequence.  The DURATION LONG declaration permits
    " the total run time this requires.  The distribution is also tagged
    " convert_test=true so it can be found manually if teardown is interrupted.
    " -----------------------------------------------------------------------
    CLASS-DATA av_distribution_id  TYPE /aws1/fntstring.
    CLASS-DATA av_distribution_arn TYPE /aws1/fntstring.

    METHODS: list_distributions  FOR TESTING RAISING /aws1/cx_rt_generic,
             update_distribution FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown.

    " For class_setup / test methods: polls until Deployed; calls
    " cl_abap_unit_assert=>fail on timeout or API error so the test
    " is clearly marked as failed rather than hanging silently.
    CLASS-METHODS wait_for_deployed
      IMPORTING
        iv_distribution_id TYPE /aws1/fntstring
      RAISING
        /aws1/cx_rt_generic.

    " For class_teardown: same poll, but returns abap_false on timeout or
    " API error instead of calling assert=>fail.  Safe in a no-RAISING
    " context because cx_abap_unit_abort cannot escape.
    CLASS-METHODS wait_for_deployed_safe
      IMPORTING
        iv_distribution_id TYPE /aws1/fntstring
      RETURNING
        VALUE(rv_success)  TYPE abap_bool.

ENDCLASS.

CLASS ltc_awsex_cl_fnt_actions IMPLEMENTATION.

  " =========================================================================
  " class_setup
  " =========================================================================
  METHOD class_setup.
    DATA lv_uuid_string   TYPE string.
    " Declared as /aws1/fntstring (= TYPE STRING) so they are type-compatible
    " with the /aws1/cl_fntorigin and /aws1/cl_fntdefaultcachebehav constructors.
    " Inline DATA(...) = 'literal' would infer type c, which is not compatible.
    DATA lv_origin_domain TYPE /aws1/fntstring.
    DATA lv_origin_id     TYPE /aws1/fntstring.
    DATA lo_create_result TYPE REF TO /aws1/cl_fntcredistributionrs.
    DATA lo_distribution  TYPE REF TO /aws1/cl_fntdistribution.

    ao_session     = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_fnt         = /aws1/cl_fnt_factory=>create( ao_session ).
    ao_fnt_actions = NEW /awsex/cl_fnt_actions( ).

    " -----------------------------------------------------------------------
    " Build a minimal valid CloudFront distribution config.
    " CallerReference must be unique per creation attempt.
    " -----------------------------------------------------------------------
    lv_uuid_string = /awsex/cl_utils=>get_random_string( ).
    CONDENSE lv_uuid_string NO-GAPS.

    " Unique caller reference, e.g. 'abap-test-A1B2C3D4E5'
    DATA(lv_caller_ref) = |abap-test-{ lv_uuid_string }|.
    " Example origin domain: 'docs.aws.amazon.com'
    lv_origin_domain = |docs.aws.amazon.com|.
    lv_origin_id     = |docs-origin|.

    DATA(lo_dist_config) = NEW /aws1/cl_fntdistributionconfig(
      iv_callerreference      = lv_caller_ref
      iv_comment              = 'ABAP SDK convert_test distribution'
      iv_enabled              = abap_true
      iv_httpversion          = 'http2'
      iv_priceclass           = 'PriceClass_100'
      io_origins = NEW /aws1/cl_fntorigins(
        iv_quantity = 1
        it_items    = VALUE /aws1/cl_fntorigin=>tt_originlist(
          ( NEW /aws1/cl_fntorigin(
              iv_id         = lv_origin_id
              iv_domainname = lv_origin_domain
              io_customoriginconfig = NEW /aws1/cl_fntcustomoriginconfig(
                iv_httpport             = 80
                iv_httpsport            = 443
                iv_originprotocolpolicy = 'https-only'
                io_originsslprotocols   = NEW /aws1/cl_fntoriginsslprotocols(
                  iv_quantity = 1
                  it_items    = VALUE /aws1/cl_fntsslprotocolslist_w=>tt_sslprotocolslist(
                    ( NEW /aws1/cl_fntsslprotocolslist_w( 'TLSv1.2' ) )
                  )
                )
              )
          ) )
        )
      )
      io_defaultcachebehavior = NEW /aws1/cl_fntdefaultcachebehav(
        iv_targetoriginid       = lv_origin_id
        iv_viewerprotocolpolicy = 'allow-all'
        " AWS-managed CachingOptimized policy - stable ID across all accounts/regions
        iv_cachepolicyid        = '658327ea-f89d-4fab-a63d-7e88639e58f6'
      )
      io_restrictions = NEW /aws1/cl_fntrestrictions(
        io_georestriction = NEW /aws1/cl_fntgeorestriction(
          iv_restrictiontype = 'none'
          iv_quantity        = 0
        )
      )
      io_viewercertificate = NEW /aws1/cl_fntviewercertificate(
        iv_cloudfrontdefaultcert = abap_true
      )
    ).

    TRY.
        lo_create_result = ao_fnt->createdistribution(
          io_distributionconfig = lo_dist_config ).
      CATCH /aws1/cx_fntclientexc INTO DATA(lo_cx).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: createdistribution failed - { lo_cx->get_text( ) }| ).
      CATCH /aws1/cx_fntserverexc INTO DATA(lo_sx).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: createdistribution server error - { lo_sx->get_text( ) }| ).
    ENDTRY.

    lo_distribution     = lo_create_result->get_distribution( ).
    av_distribution_id  = lo_distribution->get_id( ).
    av_distribution_arn = lo_distribution->get_arn( ).

    IF av_distribution_id IS INITIAL.
      cl_abap_unit_assert=>fail(
        msg = 'class_setup: distribution ID is empty after creation' ).
    ENDIF.

    " Tag with convert_test=true so the distribution can be found manually
    " if class_teardown is interrupted before completing deletion.
    TRY.
        ao_fnt->tagresource(
          iv_resource = av_distribution_arn
          io_tags     = NEW /aws1/cl_fnttags(
            it_items = VALUE /aws1/cl_fnttag=>tt_taglist(
              ( NEW /aws1/cl_fnttag(
                  iv_key   = 'convert_test'
                  iv_value = 'true' ) )
            )
          )
        ).
      CATCH /aws1/cx_fntclientexc /aws1/cx_fntserverexc INTO DATA(lo_tag_ex).
        MESSAGE |class_setup: tagging failed - { lo_tag_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.

    " Wait until the distribution is Deployed before running tests.
    " UpdateDistribution requires the current ETag, which is only reliable
    " once the distribution has reached Deployed status.
    wait_for_deployed( av_distribution_id ).

  ENDMETHOD.

  " =========================================================================
  " class_teardown  - no RAISING; every step in its own TRY/CATCH
  " =========================================================================
  METHOD class_teardown.
    " -----------------------------------------------------------------------
    " CloudFront deletion sequence:
    "   1. Disable the distribution via UpdateDistribution (enabled = false)
    "   2. Wait for status = 'Deployed'  (async, ~10-15 min)
    "   3. Delete the distribution via DeleteDistribution
    "
    " Each step is in its own TRY/CATCH so a failure in one step does not
    " prevent the others from running.  If deletion fails, the distribution
    " remains tagged convert_test=true for manual cleanup.
    "
    " wait_for_deployed_safe is used here (not wait_for_deployed) because
    " class_teardown has no RAISING clause.  wait_for_deployed calls
    " cl_abap_unit_assert=>fail internally, which raises cx_abap_unit_abort
    " -- a subclass of cx_static_check that is NOT caught by
    " CATCH /aws1/cx_rt_generic, and would escape class_teardown unchecked.
    " wait_for_deployed_safe returns abap_false instead of asserting.
    " -----------------------------------------------------------------------
    IF av_distribution_id IS INITIAL.
      RETURN.
    ENDIF.

    " --- Step 1: read current config + ETag, then disable -----------------
    DATA lv_etag TYPE /aws1/fntstring.
    TRY.
        DATA(lo_cfg_resp) = ao_fnt->getdistributionconfig(
          iv_id = av_distribution_id ).
        lv_etag = lo_cfg_resp->get_etag( ).
        DATA(lo_cfg) = lo_cfg_resp->get_distributionconfig( ).

        " Rebuild the config with enabled = false; all other fields unchanged.
        DATA(lo_disabled_cfg) = NEW /aws1/cl_fntdistributionconfig(
          iv_callerreference      = lo_cfg->get_callerreference( )
          io_aliases              = lo_cfg->get_aliases( )
          iv_defaultrootobject    = lo_cfg->get_defaultrootobject( )
          io_origins              = lo_cfg->get_origins( )
          io_origingroups         = lo_cfg->get_origingroups( )
          io_defaultcachebehavior = lo_cfg->get_defaultcachebehavior( )
          io_cachebehaviors       = lo_cfg->get_cachebehaviors( )
          io_customerrorresponses = lo_cfg->get_customerrorresponses( )
          iv_comment              = lo_cfg->get_comment( )
          io_logging              = lo_cfg->get_logging( )
          iv_priceclass           = lo_cfg->get_priceclass( )
          iv_enabled              = abap_false
          io_viewercertificate    = lo_cfg->get_viewercertificate( )
          io_restrictions         = lo_cfg->get_restrictions( )
          iv_webaclid             = lo_cfg->get_webaclid( )
          iv_httpversion          = lo_cfg->get_httpversion( )
          iv_isipv6enabled        = lo_cfg->get_isipv6enabled( ) ).

        DATA(lo_upd_result) = ao_fnt->updatedistribution(
          io_distributionconfig = lo_disabled_cfg
          iv_id                 = av_distribution_id
          iv_ifmatch            = lv_etag ).
        lv_etag = lo_upd_result->get_etag( ).
        MESSAGE |class_teardown: distribution { av_distribution_id } disabled| TYPE 'I'.
      CATCH /aws1/cx_fntclientexc /aws1/cx_fntserverexc INTO DATA(lo_dis_ex).
        MESSAGE |class_teardown: disable failed - { lo_dis_ex->get_text( ) }| TYPE 'I'.
        RETURN.  " Cannot delete without disabling first.
    ENDTRY.

    " --- Step 2: wait for Deployed after disable --------------------------
    " Use wait_for_deployed_safe: returns abap_false on error/timeout
    " instead of calling assert=>fail, so no exception can escape teardown.
    DATA(lv_deployed) = wait_for_deployed_safe( av_distribution_id ).
    IF lv_deployed = abap_false.
      MESSAGE |class_teardown: distribution { av_distribution_id } did not reach| &&
              | Deployed after disable; skipping delete.| &&
              | Tagged convert_test=true for manual cleanup.| TYPE 'I'.
      RETURN.
    ENDIF.

    " Refresh ETag after deployment of the disable change.
    TRY.
        DATA(lo_etag_resp) = ao_fnt->getdistributionconfig( iv_id = av_distribution_id ).
        lv_etag = lo_etag_resp->get_etag( ).
      CATCH /aws1/cx_fntclientexc /aws1/cx_fntserverexc INTO DATA(lo_etag_ex).
        MESSAGE |class_teardown: ETag refresh failed - { lo_etag_ex->get_text( ) }| TYPE 'I'.
        RETURN.
    ENDTRY.

    " --- Step 3: delete ---------------------------------------------------
    TRY.
        ao_fnt->deletedistribution(
          iv_id      = av_distribution_id
          iv_ifmatch = lv_etag ).
        MESSAGE |class_teardown: distribution { av_distribution_id } deleted| TYPE 'I'.
      CATCH /aws1/cx_fntclientexc /aws1/cx_fntserverexc INTO DATA(lo_del_ex).
        MESSAGE |class_teardown: delete failed - { lo_del_ex->get_text( ) }| &&
                | Distribution { av_distribution_id } tagged convert_test=true| &&
                | for manual cleanup.| TYPE 'I'.
    ENDTRY.

  ENDMETHOD.

  " =========================================================================
  " wait_for_deployed  - for use in class_setup and test methods only.
  " Calls cl_abap_unit_assert=>fail on timeout/error so the test is clearly
  " marked failed.  Do NOT call from class_teardown.
  " =========================================================================
  METHOD wait_for_deployed.
    " Poll every 30 s for up to 35 attempts (~17.5 min).
    " Matches the AWS CLI 'cloudfront wait distribution-deployed' waiter.
    CONSTANTS cv_max_polls TYPE i VALUE 35.
    CONSTANTS cv_poll_secs TYPE i VALUE 30.

    DATA lv_status     TYPE /aws1/fntstring.
    DATA lo_get_result TYPE REF TO /aws1/cl_fntgetdistributionrs.

    DATA(lo_fnt_local) = /aws1/cl_fnt_factory=>create(
      /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ) ).

    DO cv_max_polls TIMES.
      TRY.
          lo_get_result = lo_fnt_local->getdistribution( iv_id = iv_distribution_id ).
          lv_status = lo_get_result->get_distribution( )->get_status( ).
        CATCH /aws1/cx_fntclientexc /aws1/cx_fntserverexc INTO DATA(lo_poll_ex).
          cl_abap_unit_assert=>fail(
            msg = |wait_for_deployed: GetDistribution failed - { lo_poll_ex->get_text( ) }| ).
      ENDTRY.

      IF lv_status = 'Deployed'.
        RETURN.
      ENDIF.

      WAIT UP TO cv_poll_secs SECONDS.
    ENDDO.

    cl_abap_unit_assert=>fail(
      msg = |Distribution { iv_distribution_id } did not reach 'Deployed' after| &&
            | { cv_max_polls } polls of { cv_poll_secs }s each.| ).
  ENDMETHOD.

  " =========================================================================
  " wait_for_deployed_safe  - for use in class_teardown only.
  " Returns abap_true when Deployed, abap_false on timeout or API error.
  " Never raises; never calls assert=>fail.
  " =========================================================================
  METHOD wait_for_deployed_safe.
    CONSTANTS cv_max_polls TYPE i VALUE 35.
    CONSTANTS cv_poll_secs TYPE i VALUE 30.

    DATA lv_status     TYPE /aws1/fntstring.
    DATA lo_get_result TYPE REF TO /aws1/cl_fntgetdistributionrs.

    rv_success = abap_false.

    DATA(lo_fnt_local) = /aws1/cl_fnt_factory=>create(
      /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ) ).

    DO cv_max_polls TIMES.
      TRY.
          lo_get_result = lo_fnt_local->getdistribution( iv_id = iv_distribution_id ).
          lv_status = lo_get_result->get_distribution( )->get_status( ).
        CATCH /aws1/cx_fntclientexc /aws1/cx_fntserverexc INTO DATA(lo_poll_ex).
          " Log the error and return false - do not assert.
          MESSAGE |wait_for_deployed_safe: poll error - { lo_poll_ex->get_text( ) }| TYPE 'I'.
          RETURN.
      ENDTRY.

      IF lv_status = 'Deployed'.
        rv_success = abap_true.
        RETURN.
      ENDIF.

      WAIT UP TO cv_poll_secs SECONDS.
    ENDDO.

    " Timeout: return false without asserting.
    MESSAGE |wait_for_deployed_safe: distribution { iv_distribution_id }| &&
            | did not reach 'Deployed' after { cv_max_polls } polls.| TYPE 'I'.
  ENDMETHOD.

  " =========================================================================
  " TEST: list_distributions
  " =========================================================================
  METHOD list_distributions.
    " class_setup created and deployed a distribution, so there is guaranteed
    " to be at least one distribution in the account.
    DATA(lo_result) = ao_fnt_actions->list_distributions( ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_distributions must return a bound result object' ).

    DATA(lo_dist_list) = lo_result->get_distributionlist( ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_dist_list
      msg = 'DistributionList must be bound in the ListDistributions response' ).

    " Declared quantity must equal the actual item count.
    DATA(lv_quantity) = lo_dist_list->get_quantity( ).
    DATA(lt_items)    = lo_dist_list->get_items( ).
    cl_abap_unit_assert=>assert_equals(
      exp = lv_quantity
      act = lines( lt_items )
      msg = |ListDistributions: declared quantity { lv_quantity }| &&
            | does not match item count { lines( lt_items ) }| ).

    " At least one distribution must be returned (the one from class_setup).
    cl_abap_unit_assert=>assert_true(
      act = boolc( lv_quantity >= 1 )
      msg = 'ListDistributions must return at least the distribution created in class_setup' ).

    " Every distribution must have a non-empty domain name.
    LOOP AT lt_items INTO DATA(lo_dist_summ).
      cl_abap_unit_assert=>assert_not_initial(
        act = lo_dist_summ->get_domainname( )
        msg = |Distribution { lo_dist_summ->get_id( ) } has an empty domain name| ).
    ENDLOOP.

    " The distribution created in class_setup must appear in the list.
    DATA(lv_found) = abap_false.
    LOOP AT lt_items INTO DATA(lo_item).
      IF lo_item->get_id( ) = av_distribution_id.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.
    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Distribution { av_distribution_id } created in class_setup| &&
            | was not found in the ListDistributions result| ).
  ENDMETHOD.

  " =========================================================================
  " TEST: update_distribution
  " =========================================================================
  METHOD update_distribution.
    " Use the distribution created and deployed in class_setup.
    IF av_distribution_id IS INITIAL.
      cl_abap_unit_assert=>fail(
        msg = 'update_distribution: av_distribution_id is empty; class_setup must have failed.' ).
    ENDIF.

    " Read the original comment so we can restore it afterwards.
    DATA lv_orig_comment TYPE /aws1/fntcommenttype.
    TRY.
        DATA(lo_cfg_resp) = ao_fnt->getdistributionconfig( iv_id = av_distribution_id ).
        lv_orig_comment = lo_cfg_resp->get_distributionconfig( )->get_comment( ).
      CATCH /aws1/cx_fntclientexc /aws1/cx_fntserverexc INTO DATA(lo_read_ex).
        cl_abap_unit_assert=>fail(
          msg = |update_distribution: could not read current config -| &&
                | { lo_read_ex->get_text( ) }| ).
    ENDTRY.

    " Call the action method under test.
    " Example comment: 'ABAP SDK convert_test update'
    DATA(lv_test_comment) = CONV /aws1/fntcommenttype( 'ABAP SDK convert_test update' ).

    DATA(lo_result) = ao_fnt_actions->update_distribution(
      iv_distribution_id = av_distribution_id
      iv_new_comment     = lv_test_comment ).

    " Assert directly on the returned result object.
    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'update_distribution must return a bound result object' ).

    DATA(lv_new_etag) = lo_result->get_etag( ).
    cl_abap_unit_assert=>assert_not_initial(
      act = lv_new_etag
      msg = 'UpdateDistribution response must contain a non-empty ETag' ).

    " The new ETag must differ from the one submitted, confirming the service
    " accepted and versioned the change.
    DATA(lv_submitted_etag) = lo_cfg_resp->get_etag( ).
    cl_abap_unit_assert=>assert_differs(
      exp = lv_submitted_etag
      act = lv_new_etag
      msg = |New ETag after update must differ from the submitted ETag| &&
            | (submitted: { lv_submitted_etag }, received: { lv_new_etag })| ).

    " Restore the original comment (best-effort; failure does not fail the test).
    TRY.
        ao_fnt_actions->update_distribution(
          iv_distribution_id = av_distribution_id
          iv_new_comment     = lv_orig_comment ).
      CATCH /aws1/cx_fntclientexc /aws1/cx_fntserverexc INTO DATA(lo_restore_ex).
        MESSAGE |update_distribution: could not restore original comment| &&
                | - { lo_restore_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
