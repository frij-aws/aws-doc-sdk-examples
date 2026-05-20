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
    " long time to disable + delete, so the distribution is intentionally
    " NOT cleaned up automatically.  It is tagged with convert_test=true so
    " that it can be found and removed manually or via a cleanup script.
    " -----------------------------------------------------------------------
    CLASS-DATA av_distribution_id  TYPE /aws1/fntstring.
    CLASS-DATA av_distribution_arn TYPE /aws1/fntstring.

    METHODS: list_distributions  FOR TESTING RAISING /aws1/cx_rt_generic,
             update_distribution FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " Helper – poll GetDistribution until status = 'Deployed' or timeout.
    CLASS-METHODS wait_for_deployed
      IMPORTING
        iv_distribution_id TYPE /aws1/fntstring
      RAISING
        /aws1/cx_rt_generic.

ENDCLASS.

CLASS ltc_awsex_cl_fnt_actions IMPLEMENTATION.

  " =========================================================================
  " class_setup
  " =========================================================================
  METHOD class_setup.
    DATA lv_uuid_string TYPE string.
    DATA lo_create_result TYPE REF TO /aws1/cl_fntcredistributionrs.
    DATA lo_distribution TYPE REF TO /aws1/cl_fntdistribution.

    ao_session     = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_fnt         = /aws1/cl_fnt_factory=>create( ao_session ).
    ao_fnt_actions = NEW /awsex/cl_fnt_actions( ).

    " -----------------------------------------------------------------------
    " Build a minimal, valid CloudFront distribution configuration.
    "
    " Origin: a public S3 static-website endpoint (no OAI needed).
    " We use a well-known public bucket domain as a placeholder origin so the
    " distribution is created without error.  The exact origin content is
    " irrelevant for these unit tests.
    "
    " CallerReference: must be unique per creation attempt.
    " -----------------------------------------------------------------------
    lv_uuid_string = /awsex/cl_utils=>get_random_string( ).
    CONDENSE lv_uuid_string NO-GAPS.

    " Unique caller reference: 'abap-test-' + random suffix
    DATA(lv_caller_ref) = |abap-test-{ lv_uuid_string }|.

    " Origin domain – a publicly accessible HTTPS endpoint.
    " Using the AWS documentation static site as a harmless origin placeholder.
    " Example origin domain: 'docs.aws.amazon.com'
    DATA(lv_origin_domain) = 'docs.aws.amazon.com'.
    DATA(lv_origin_id)     = 'docs-origin'.

    " -----------------------------------------------------------------------
    " Assemble the minimum required DistributionConfig:
    "   - One HTTP/S origin (custom origin config)
    "   - Default cache behaviour pointing at that origin
    "   - No aliases (CNAMEs)
    "   - CloudFront default viewer certificate
    "   - No geo-restriction
    "   - PriceClass_100 (US, Canada, Europe only – cheapest)
    " -----------------------------------------------------------------------
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
        iv_targetoriginid        = lv_origin_id
        iv_viewerprotocolpolicy  = 'allow-all'
        iv_cachepolicyid         = '658327ea-f89d-4fab-a63d-7e88639e58f6'
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

    " -----------------------------------------------------------------------
    " Create the distribution and capture its ID and ARN.
    " -----------------------------------------------------------------------
    TRY.
        lo_create_result = ao_fnt->createdistribution(
          io_distributionconfig = lo_dist_config ).
      CATCH /aws1/cx_fntclientexc INTO DATA(lo_cx).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: createdistribution failed – { lo_cx->get_text( ) }| ).
      CATCH /aws1/cx_fntserverexc INTO DATA(lo_sx).
        cl_abap_unit_assert=>fail(
          msg = |class_setup: createdistribution server error – { lo_sx->get_text( ) }| ).
    ENDTRY.

    lo_distribution        = lo_create_result->get_distribution( ).
    av_distribution_id     = lo_distribution->get_id( ).
    av_distribution_arn    = lo_distribution->get_arn( ).

    IF av_distribution_id IS INITIAL.
      cl_abap_unit_assert=>fail(
        msg = 'class_setup: distribution ID is empty after creation' ).
    ENDIF.

    " -----------------------------------------------------------------------
    " Tag the distribution so it can be found and cleaned up manually.
    " CloudFront TagResource uses the distribution ARN as the resource key.
    " -----------------------------------------------------------------------
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
        " Tagging failure is not a fatal error; log and continue.
        MESSAGE |class_setup: tagging failed – { lo_tag_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.

    " -----------------------------------------------------------------------
    " Wait until the distribution reaches 'Deployed' status.
    " This is required before update_distribution can succeed.
    " -----------------------------------------------------------------------
    wait_for_deployed( av_distribution_id ).

  ENDMETHOD.

  " =========================================================================
  " class_teardown
  " =========================================================================
  METHOD class_teardown.
    " -----------------------------------------------------------------------
    " CloudFront distributions require two slow async operations to delete:
    "   1. Disable the distribution  (waits for Deployed, ~10-15 min)
    "   2. Delete the distribution   (waits for Deployed, ~10-15 min)
    "
    " Performing both steps here would make the test suite take 30+ minutes.
    " Instead the distribution is tagged with convert_test=true (done in
    " class_setup) and must be cleaned up manually or by a cleanup script.
    " -----------------------------------------------------------------------
    MESSAGE |CloudFront distribution { av_distribution_id } is tagged| &&
            | convert_test=true and must be cleaned up manually.| TYPE 'I'.
  ENDMETHOD.

  " =========================================================================
  " wait_for_deployed  (private helper)
  " =========================================================================
  METHOD wait_for_deployed.
    " Poll GetDistribution every 30 seconds for up to 35 attempts (~17 min).
    " This matches the AWS CLI waiter 'distribution-deployed' behaviour.
    CONSTANTS cv_max_polls TYPE i VALUE 35.
    CONSTANTS cv_poll_secs TYPE i VALUE 30.

    DATA lv_status TYPE /aws1/fntstring.
    DATA lo_get_result TYPE REF TO /aws1/cl_fntgetdistributionrs.

    DATA(lo_fnt_local) = /aws1/cl_fnt_factory=>create(
      /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ) ).

    DO cv_max_polls TIMES.
      TRY.
          lo_get_result = lo_fnt_local->getdistribution( iv_id = iv_distribution_id ).
          lv_status = lo_get_result->get_distribution( )->get_status( ).
        CATCH /aws1/cx_fntclientexc /aws1/cx_fntserverexc INTO DATA(lo_poll_ex).
          cl_abap_unit_assert=>fail(
            msg = |wait_for_deployed: GetDistribution failed – { lo_poll_ex->get_text( ) }| ).
      ENDTRY.

      IF lv_status = 'Deployed'.
        RETURN.
      ENDIF.

      WAIT UP TO cv_poll_secs SECONDS.
    ENDDO.

    " If we reach here the distribution never became Deployed.
    cl_abap_unit_assert=>fail(
      msg = |Distribution { iv_distribution_id } did not reach 'Deployed' status| &&
            | after { cv_max_polls } polls of { cv_poll_secs }s each.| ).
  ENDMETHOD.

  " =========================================================================
  " TEST: list_distributions
  " =========================================================================
  METHOD list_distributions.
    " -------------------------------------------------------------------
    " Prerequisite: class_setup created and deployed a distribution, so
    " the account is guaranteed to have at least one distribution and the
    " list result will be non-empty and the quantity will match item count.
    " -------------------------------------------------------------------
    DATA(lo_result) = ao_fnt_actions->list_distributions( ).

    " Result object must be bound.
    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_distributions must return a bound result object' ).

    " The DistributionList wrapper must be present.
    DATA(lo_dist_list) = lo_result->get_distributionlist( ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_dist_list
      msg = 'DistributionList must be bound in the ListDistributions response' ).

    " The declared quantity must equal the number of items returned.
    DATA(lv_quantity) = lo_dist_list->get_quantity( ).
    DATA(lt_items)    = lo_dist_list->get_items( ).
    cl_abap_unit_assert=>assert_equals(
      exp = lv_quantity
      act = lines( lt_items )
      msg = |ListDistributions: declared quantity { lv_quantity }| &&
            | does not match item count { lines( lt_items ) }| ).

    " There must be at least one distribution (the one we created).
    cl_abap_unit_assert=>assert_true(
      act  = boolc( lv_quantity >= 1 )
      msg  = 'ListDistributions must return at least the distribution created in class_setup' ).

    " Every returned distribution must have a non-empty domain name.
    LOOP AT lt_items INTO DATA(lo_dist_summ).
      cl_abap_unit_assert=>assert_not_initial(
        act = lo_dist_summ->get_domainname( )
        msg = |Distribution { lo_dist_summ->get_id( ) }| &&
              | has an empty domain name| ).
    ENDLOOP.

    " The distribution we created must appear in the list.
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
            | was not found in ListDistributions result| ).
  ENDMETHOD.

  " =========================================================================
  " TEST: update_distribution
  " =========================================================================
  METHOD update_distribution.
    " -------------------------------------------------------------------
    " Use the distribution created and deployed in class_setup.
    " We modify the comment, verify the change, then restore the original.
    " -------------------------------------------------------------------
    IF av_distribution_id IS INITIAL.
      cl_abap_unit_assert=>fail(
        msg = 'update_distribution: av_distribution_id is empty;' &&
              ' class_setup must have failed.' ).
    ENDIF.

    " --- Read the original comment so we can restore it -----------------
    DATA(lo_cfg_resp)     = ao_fnt->getdistributionconfig( iv_id = av_distribution_id ).
    DATA(lo_orig_cfg)     = lo_cfg_resp->get_distributionconfig( ).
    DATA(lv_orig_comment) = lo_orig_cfg->get_comment( ).

    " --- Apply the test comment ------------------------------------------
    " Example comment: 'ABAP SDK convert_test update'
    DATA(lv_test_comment) = CONV /aws1/fntcommenttype( 'ABAP SDK convert_test update' ).

    ao_fnt_actions->update_distribution(
      iv_distribution_id = av_distribution_id
      iv_new_comment     = lv_test_comment ).

    " Wait briefly for the config change to propagate (config updates are
    " near-instant; we do NOT need to wait for 'Deployed' here because the
    " GetDistributionConfig API returns the pending config immediately).
    WAIT UP TO 5 SECONDS.

    " --- Verify the comment was stored -----------------------------------
    DATA(lo_check_resp)      = ao_fnt->getdistributionconfig( iv_id = av_distribution_id ).
    DATA(lv_updated_comment) = lo_check_resp->get_distributionconfig( )->get_comment( ).

    cl_abap_unit_assert=>assert_equals(
      exp = lv_test_comment
      act = lv_updated_comment
      msg = |update_distribution: comment was not updated on distribution| &&
            | { av_distribution_id }. Expected '{ lv_test_comment }'| &&
            | but got '{ lv_updated_comment }'| ).

    " --- Restore the original comment (best-effort; cosmetic) -----------
    TRY.
        ao_fnt_actions->update_distribution(
          iv_distribution_id = av_distribution_id
          iv_new_comment     = lv_orig_comment ).
      CATCH /aws1/cx_fntclientexc /aws1/cx_fntserverexc INTO DATA(lo_restore_ex).
        MESSAGE |update_distribution: could not restore original comment| &&
                | – { lo_restore_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
