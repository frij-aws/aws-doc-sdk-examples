" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS ltc_awsex_cl_fnt_actions DEFINITION DEFERRED.
CLASS /awsex/cl_fnt_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_fnt_actions.

CLASS ltc_awsex_cl_fnt_actions DEFINITION
    FOR TESTING
    DURATION SHORT
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

    " class_teardown must not declare RAISING — all exceptions caught internally.
    CLASS-METHODS class_teardown.

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

    " Build a unique caller reference using the utility random-string helper.
    DATA lv_rnd TYPE string.
    lv_rnd = /awsex/cl_utils=>get_random_string( ).

    DATA lv_caller_ref TYPE /aws1/fntstring.
    lv_caller_ref = |sap-abap-fnt-test-{ lv_rnd }|.

    " Create a minimal CloudFront distribution backed by www.example.com as an
    " HTTPS custom origin.  No S3 bucket, ACM certificate, or VPC resource is
    " required.  The distribution is created synchronously — the API returns
    " immediately with status InProgress while CloudFront propagates globally.
    " All tests assert only on the synchronous API response, so no polling
    " for Deployed status is needed.
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

    " Tag the distribution immediately with convert_test=true so it can be
    " found and cleaned up manually if teardown does not complete.
    ao_fnt->tagresource(
      iv_resource = av_distribution_arn
      io_tags     = NEW /aws1/cl_fnttags(
        it_items = VALUE /aws1/cl_fnttag=>tt_taglist(
          ( NEW /aws1/cl_fnttag(
              iv_key   = 'convert_test'
              iv_value = 'true' ) )
        ) ) ).
  ENDMETHOD.


  METHOD class_teardown.
    " CloudFront distributions must be disabled before they can be deleted,
    " and both the disable-update and the deletion require the distribution
    " to be in Deployed state, which takes ~15 minutes.  Waiting here would
    " exceed any reasonable test-runner timeout.
    "
    " Strategy: attempt a direct delete (succeeds only if already Deployed
    " and disabled).  On any error, leave the resource in AWS — it is tagged
    " convert_test=true for manual or scheduled cleanup.
    "
    " Each step is wrapped in its own TRY/CATCH so a failure in one step
    " does not prevent subsequent steps from running, and no exception
    " escapes this method.

    IF av_distribution_id IS INITIAL.
      RETURN.
    ENDIF.

    " Step 1 – retrieve current ETag needed for any update/delete call.
    DATA lv_etag        TYPE /aws1/fntstring.
    DATA lo_dist_cfg    TYPE REF TO /aws1/cl_fntdistributionconfig.
    TRY.
        DATA(lo_cfg_resp) = ao_fnt->getdistributionconfig(
          iv_id = av_distribution_id ).
        lv_etag     = lo_cfg_resp->get_etag( ).
        lo_dist_cfg = lo_cfg_resp->get_distributionconfig( ).
      CATCH /aws1/cx_fntclientexc
            /aws1/cx_fntserverexc
            /aws1/cx_rt_technical_generic
            /aws1/cx_rt_service_generic.
        " Cannot read config — distribution is tagged; leave for manual cleanup.
        RETURN.
    ENDTRY.

    " Step 2 – attempt to disable the distribution.
    " This will fail with CannotUpdateEntity if the distribution is still
    " InProgress, which is expected.  Continue to Step 3 regardless.
    DATA lv_disabled_etag TYPE /aws1/fntstring.
    TRY.
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
          iv_enabled              = abap_false
          io_viewercertificate    = lo_dist_cfg->get_viewercertificate( )
          io_restrictions         = lo_dist_cfg->get_restrictions( )
          iv_webaclid             = lo_dist_cfg->get_webaclid( )
          iv_httpversion          = lo_dist_cfg->get_httpversion( )
          iv_isipv6enabled        = lo_dist_cfg->get_isipv6enabled( ) ).

        DATA(lo_upd_rs) = ao_fnt->updatedistribution(
          io_distributionconfig = lo_disabled_cfg
          iv_id                 = av_distribution_id
          iv_ifmatch            = lv_etag ).
        lv_disabled_etag = lo_upd_rs->get_etag( ).
      CATCH /aws1/cx_fntclientexc
            /aws1/cx_fntserverexc
            /aws1/cx_rt_technical_generic
            /aws1/cx_rt_service_generic.
        " Disable failed (likely still InProgress) — tagged; leave for manual cleanup.
        RETURN.
    ENDTRY.

    " Step 3 – attempt to delete immediately.
    " This will succeed only if the distribution is already Deployed after
    " the disable above.  If it is still InProgress, DeleteDistribution
    " raises DistributionNotDisabled; we catch and leave it tagged.
    TRY.
        ao_fnt->deletedistribution(
          iv_id      = av_distribution_id
          iv_ifmatch = lv_disabled_etag ).
      CATCH /aws1/cx_fntclientexc
            /aws1/cx_fntserverexc
            /aws1/cx_rt_technical_generic
            /aws1/cx_rt_service_generic.
        " Delete failed — distribution is tagged convert_test=true;
        " clean up manually once it reaches Deployed+Disabled state.
    ENDTRY.
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " Test: list_distributions
  " Verifies that the action returns a bound result and that the
  " distribution created in class_setup appears in the list.
  " The distribution may still be InProgress — CloudFront includes it
  " in ListDistributions immediately after creation.
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

    " Verify the distribution created in class_setup appears in the list.
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
  " Calls UpdateDistribution and asserts directly on the synchronous API
  " response (bound result object + non-empty ETag).  No polling for
  " Deployed state is required — UpdateDistribution responds immediately
  " even when the distribution is InProgress.
  " -----------------------------------------------------------------------
  METHOD update_distribution.
    " UpdateDistribution requires the current ETag from GetDistributionConfig.
    DATA(lo_cfg_before) = ao_fnt->getdistributionconfig(
      iv_id = av_distribution_id ).

    DATA lv_orig_comment TYPE /aws1/fntcommenttype.
    lv_orig_comment =
      lo_cfg_before->get_distributionconfig( )->get_comment( ).

    DATA lv_new_comment TYPE /aws1/fntcommenttype.
    lv_new_comment = 'SAP ABAP SDK convert_test updated comment'.

    " Call the action method under test and capture its RETURNING value.
    DATA lo_upd_result TYPE REF TO /aws1/cl_fntupdistributionrs.
    ao_actions->update_distribution(
      EXPORTING
        iv_distribution_id = av_distribution_id
        iv_comment         = lv_new_comment
      RECEIVING
        oo_result          = lo_upd_result ).

    " Assert directly on the synchronous UpdateDistribution response.
    cl_abap_unit_assert=>assert_bound(
      act = lo_upd_result
      msg = 'update_distribution must return a bound result object' ).

    cl_abap_unit_assert=>assert_not_initial(
      act = lo_upd_result->get_etag( )
      msg = 'UpdateDistribution must return a non-empty ETag' ).

    " Verify the distribution object in the response carries the correct comment.
    " Multi-level chaining is broken into steps for NetWeaver 7.4 compatibility.
    DATA(lo_upd_dist) = lo_upd_result->get_distribution( ).
    DATA(lo_upd_dist_cfg) = lo_upd_dist->get_distributionconfig( ).
    cl_abap_unit_assert=>assert_equals(
      exp = lv_new_comment
      act = lo_upd_dist_cfg->get_comment( )
      msg = 'UpdateDistribution response must reflect the new comment' ).

    " Restore the original comment using the ETag from the update response,
    " so that class_teardown can attempt a clean disable+delete.
    ao_actions->update_distribution(
      iv_distribution_id = av_distribution_id
      iv_comment         = lv_orig_comment ).
  ENDMETHOD.


  " -----------------------------------------------------------------------
  " Helper: build_distribution_config
  " Constructs the minimal /AWS1/CL_FNTDISTRIBUTIONCONFIG required to
  " create a CloudFront distribution.  Uses www.example.com as an HTTPS
  " custom origin; no S3 bucket, ACM certificate, or VPC resource is
  " required.
  " -----------------------------------------------------------------------
  METHOD build_distribution_config.
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

    " Use the AWS-managed CachingOptimized cache policy.
    " CachingOptimized policy ID: '658327ea-f89d-4fab-a63d-7e88639e58f6'
    DATA(lo_default_cache) = NEW /aws1/cl_fntdefaultcachebehav(
      iv_targetoriginid       = lv_origin_id
      iv_viewerprotocolpolicy = 'redirect-to-https'
      iv_cachepolicyid        = '658327ea-f89d-4fab-a63d-7e88639e58f6' ).

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

ENDCLASS.
