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

    " Shared state set in class_setup and used by all test methods.
    CLASS-DATA av_distribution_id  TYPE /aws1/fntstring.
    CLASS-DATA av_distribution_arn TYPE /aws1/fntstring.

    CLASS-DATA ao_fnt     TYPE REF TO /aws1/if_fnt.
    CLASS-DATA ao_session TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_actions TYPE REF TO /awsex/cl_fnt_actions.

    METHODS: list_distributions  FOR TESTING
               RAISING /aws1/cx_rt_generic,
             update_distribution FOR TESTING
               RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup
      RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown
      RAISING /aws1/cx_rt_generic.

    " Wait for a distribution to reach the 'Deployed' status.
    " Fails the test if the timeout (30 minutes) is exceeded.
    CLASS-METHODS wait_for_deployed
      IMPORTING
        iv_distribution_id TYPE /aws1/fntstring
      RAISING
        /aws1/cx_rt_generic.

    " Build the minimal distribution config used by class_setup.
    CLASS-METHODS build_distribution_config
      IMPORTING
        iv_caller_ref TYPE /aws1/fntstring
        iv_comment    TYPE /aws1/fntcommenttype
      RETURNING
        VALUE(oo_cfg) TYPE REF TO /aws1/cl_fntdistributionconfig.

ENDCLASS.


CLASS ltc_awsex_cl_fnt_actions IMPLEMENTATION.

  METHOD class_setup.
    ao_session = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_fnt     = /aws1/cl_fnt_factory=>create( ao_session ).
    ao_actions = NEW /awsex/cl_fnt_actions( ).

    " Build a unique caller reference using a random string.
    DATA lv_rnd TYPE string.
    lv_rnd = /awsex/cl_utils=>get_random_string( ).

    DATA lv_caller_ref TYPE /aws1/fntstring.
    lv_caller_ref = |sap-abap-fnt-test-{ lv_rnd }|.

    " Create a minimal CloudFront distribution backed by a public HTTP
    " endpoint (example.com).  No ACM certificate, S3 bucket, or VPC
    " resource is required for a simple HTTP origin.
    DATA(lo_cfg) = build_distribution_config(
      iv_caller_ref = lv_caller_ref
      iv_comment    = 'SAP ABAP SDK convert_test distribution' ).

    DATA(lo_create_result) = ao_fnt->createdistribution(
      io_distributionconfig = lo_cfg ).

    DATA(lo_dist) = lo_create_result->get_distribution( ).
    av_distribution_id  = lo_dist->get_id( ).
    av_distribution_arn = lo_dist->get_arn( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = av_distribution_id
      msg = 'Distribution ID must not be empty after creation' ).

    " Tag the distribution immediately so it can be found and cleaned up
    " manually even if the automated teardown does not complete.
    ao_fnt->tagresource(
      iv_resource = av_distribution_arn
      io_tags     = NEW /aws1/cl_fnttags(
        it_items = VALUE /aws1/cl_fnttag=>tt_taglist(
          ( NEW /aws1/cl_fnttag(
              iv_key   = 'convert_test'
              iv_value = 'true' ) )
        ) ) ).

    " Wait for the distribution to become Deployed before running tests.
    " CloudFront provisioning typically takes 5-25 minutes.
    wait_for_deployed( av_distribution_id ).
  ENDMETHOD.


  METHOD class_teardown.
    " CloudFront requires a distribution to be disabled (Enabled = false)
    " and in Deployed state before it can be deleted.  Both steps involve
    " waiting ~15 minutes each.  Because this teardown would exceed
    " reasonable test run times the distribution is LEFT in AWS but
    " remains tagged with convert_test=true so it can be found and
    " cleaned up manually or by an automated cleanup job.
    "
    " Attempted best-effort cleanup:
    IF av_distribution_id IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        " Step 1 – retrieve current config + ETag.
        DATA(lo_cfg_resp) = ao_fnt->getdistributionconfig(
          iv_id = av_distribution_id ).
        DATA(lo_dist_cfg) = lo_cfg_resp->get_distributionconfig( ).
        DATA(lv_etag)     = lo_cfg_resp->get_etag( ).

        " Step 2 – disable the distribution.
        DATA(lo_disabled_cfg) = NEW /aws1/cl_fntdistributionconfig(
          iv_callerreference      = lo_dist_cfg->get_callerreference( )
          io_aliases              = lo_dist_cfg->get_aliases( )
          iv_defaultrootobject    = lo_dist_cfg->get_defaultrootobject( )
          io_origins              = lo_dist_cfg->get_origins( )
          io_origingroups         = lo_dist_cfg->get_origingroups( )
          io_defaultcachebehavior = lo_dist_cfg->get_defaultcachebehavior( )
          io_cachebehaviors       = lo_dist_cfg->get_cachebehaviors( )
          io_customerrorresponses = lo_dist_cfg->get_customerrorresponses( )
          iv_comment              = lo_dist_cfg->get_comment( )
          io_logging              = lo_dist_cfg->get_logging( )
          iv_priceclass           = lo_dist_cfg->get_priceclass( )
          iv_enabled              = abap_false   " <-- disable
          io_viewercertificate    = lo_dist_cfg->get_viewercertificate( )
          io_restrictions         = lo_dist_cfg->get_restrictions( )
          iv_webaclid             = lo_dist_cfg->get_webaclid( )
          iv_httpversion          = lo_dist_cfg->get_httpversion( )
          iv_isipv6enabled        = lo_dist_cfg->get_isipv6enabled( ) ).

        DATA(lo_upd_rs) = ao_fnt->updatedistribution(
          io_distributionconfig = lo_disabled_cfg
          iv_id                 = av_distribution_id
          iv_ifmatch            = lv_etag ).

        " Step 3 – wait for Deployed after disabling (~15 min).
        wait_for_deployed( av_distribution_id ).

        " Step 4 – delete the now-disabled distribution.
        DATA(lo_del_cfg) = ao_fnt->getdistributionconfig(
          iv_id = av_distribution_id ).
        ao_fnt->deletedistribution(
          iv_id      = av_distribution_id
          iv_ifmatch = lo_del_cfg->get_etag( ) ).

      CATCH /aws1/cx_fntclientexc
            /aws1/cx_fntserverexc
            /aws1/cx_rt_technical_generic
            /aws1/cx_rt_service_generic.
        " Teardown failed. The distribution is tagged convert_test=true
        " and must be cleaned up manually.
    ENDTRY.
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " Test: list_distributions
  " Verifies that the action returns a bound result that contains the
  " distribution created in class_setup.
  " -----------------------------------------------------------------------
  METHOD list_distributions.
    DATA lo_result TYPE REF TO /aws1/cl_fntlstdistributionsrs.

    ao_actions->list_distributions(
      RECEIVING oo_result = lo_result ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_distributions must return a bound result object' ).

    cl_abap_unit_assert=>assert_bound(
      act = lo_result->get_distributionlist( )
      msg = 'DistributionList must be bound' ).

    " Verify the distribution we created is present in the list.
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_result->get_distributionlist( )->get_items( )
      INTO DATA(lo_item).
      IF lo_item->get_id( ) = av_distribution_id.
        lv_found = abap_true.
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Distribution { av_distribution_id } not found in list_distributions result| ).
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " Test: update_distribution
  " Changes the distribution comment, verifies the change, then restores
  " the original comment so the distribution is left in a clean state.
  " -----------------------------------------------------------------------
  METHOD update_distribution.
    " Save the current comment so we can restore it afterwards.
    DATA(lo_cfg_before) = ao_fnt->getdistributionconfig(
      iv_id = av_distribution_id ).
    DATA lv_orig_comment TYPE /aws1/fntcommenttype.
    lv_orig_comment =
      lo_cfg_before->get_distributionconfig( )->get_comment( ).

    " Apply a distinct test comment.
    DATA lv_new_comment TYPE /aws1/fntcommenttype.
    lv_new_comment = 'SAP ABAP SDK convert_test updated comment'.

    ao_actions->update_distribution(
      iv_distribution_id = av_distribution_id
      iv_comment         = lv_new_comment ).

    " Poll until Deployed so we can read back the definitive config.
    wait_for_deployed( av_distribution_id ).

    " Verify the comment was stored correctly.
    DATA(lo_cfg_after) = ao_fnt->getdistributionconfig(
      iv_id = av_distribution_id ).

    cl_abap_unit_assert=>assert_equals(
      exp = lv_new_comment
      act = lo_cfg_after->get_distributionconfig( )->get_comment( )
      msg = 'Distribution comment was not updated as expected' ).

    " Restore the original comment.
    ao_actions->update_distribution(
      iv_distribution_id = av_distribution_id
      iv_comment         = lv_orig_comment ).

    " Wait for the restore to propagate so teardown sees a clean state.
    wait_for_deployed( av_distribution_id ).
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " Helper: build_distribution_config
  " Constructs the minimal /AWS1/CL_FNTDISTRIBUTIONCONFIG required to
  " create a CloudFront distribution.  Uses example.com as an HTTP-only
  " custom origin; no S3 bucket, ACM certificate, or VPC resource is
  " required.
  " -----------------------------------------------------------------------
  METHOD build_distribution_config.
    " Origin domain – any routable HTTPS domain is acceptable as a
    " custom origin for test purposes.
    " Example origin domain: 'www.example.com'
    DATA lv_origin_id TYPE /aws1/fntstring VALUE 'example-origin'.

    DATA(lo_origins) = NEW /aws1/cl_fntorigins(
      iv_quantity = 1
      it_items    = VALUE /aws1/cl_fntorigin=>tt_originlist(
        ( NEW /aws1/cl_fntorigin(
            iv_id         = lv_origin_id
            iv_domainname = 'www.example.com'
            io_customoriginconfig = NEW /aws1/cl_fntcustomoriginconfig(
              iv_httpport             = 80
              iv_httpsport            = 443
              iv_originprotocolpolicy = 'https-only' ) ) ) ) ).

    DATA(lo_default_cache) = NEW /aws1/cl_fntdefaultcachebehav(
      iv_targetoriginid       = lv_origin_id
      iv_viewerprotocolpolicy = 'redirect-to-https'
      iv_cachepolicyid        =
        '658327ea-f89d-4fab-a63d-7e88639e58f6' ).  " CachingOptimized managed policy

    DATA(lo_viewer_cert) = NEW /aws1/cl_fntviewercertificate(
      iv_cloudfrontdefaultcert = abap_true ).

    DATA(lo_restrictions) = NEW /aws1/cl_fntrestrictions(
      io_georestriction = NEW /aws1/cl_fntgeorestriction(
        iv_restrictiontype = 'none'
        iv_quantity        = 0 ) ).

    oo_cfg = NEW /aws1/cl_fntdistributionconfig(
      iv_callerreference      = iv_caller_ref
      io_origins              = lo_origins
      io_defaultcachebehavior = lo_default_cache
      iv_comment              = iv_comment
      iv_enabled              = abap_true
      io_viewercertificate    = lo_viewer_cert
      io_restrictions         = lo_restrictions ).
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " Helper: wait_for_deployed
  " Polls GetDistribution until status == 'Deployed' or 30 minutes have
  " elapsed.  Fails the test with cl_abap_unit_assert=>fail if the
  " timeout is hit.
  " -----------------------------------------------------------------------
  METHOD wait_for_deployed.
    DATA lv_start  TYPE timestamp.
    DATA lv_now    TYPE timestamp.
    DATA lv_status TYPE /aws1/fntstring.

    GET TIME STAMP FIELD lv_start.

    DO.
      DATA(lo_get_rs) = ao_fnt->getdistribution(
        iv_id = iv_distribution_id ).
      lv_status = lo_get_rs->get_distribution( )->get_status( ).

      IF lv_status = 'Deployed'.
        RETURN.
      ENDIF.

      " Poll every 30 seconds.
      WAIT UP TO 30 SECONDS.

      GET TIME STAMP FIELD lv_now.
      DATA(lv_elapsed) = cl_abap_tstmp=>subtract(
        tstmp1 = lv_now
        tstmp2 = lv_start ).

      " Timeout after 30 minutes (1800 seconds).
      IF lv_elapsed > 1800.
        cl_abap_unit_assert=>fail(
          msg = |Distribution { iv_distribution_id } did not reach| &&
                | Deployed status within 30 minutes| ).
      ENDIF.
    ENDDO.
  ENDMETHOD.

ENDCLASS.
