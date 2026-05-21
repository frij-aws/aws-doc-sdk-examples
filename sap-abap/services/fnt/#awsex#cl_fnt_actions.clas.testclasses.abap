" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0

CLASS ltc_awsex_cl_fnt_actions DEFINITION DEFERRED.
CLASS /awsex/cl_fnt_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_fnt_actions.

" ──────────────────────────────────────────────────────────────────────────────
" Test class for /awsex/cl_fnt_actions (Amazon CloudFront examples).
"
" SETUP NOTES
" ═══════════
" The SDK execution role (ZCODE_DEMO profile) must have the following IAM
" permissions granted before running these tests:
"
"   cloudfront:CreateDistribution
"   cloudfront:CreateDistributionWithTags
"   cloudfront:DeleteDistribution
"   cloudfront:GetDistribution
"   cloudfront:GetDistributionConfig
"   cloudfront:ListDistributions
"   cloudfront:ListTagsForResource
"   cloudfront:TagResource
"   cloudfront:UpdateDistribution
"
" Example inline policy (attach to the IAM role used by the ZCODE_DEMO profile):
"
"   {
"     "Version": "2012-10-17",
"     "Statement": [{
"       "Effect": "Allow",
"       "Action": [
"         "cloudfront:CreateDistribution",
"         "cloudfront:CreateDistributionWithTags",
"         "cloudfront:DeleteDistribution",
"         "cloudfront:GetDistribution",
"         "cloudfront:GetDistributionConfig",
"         "cloudfront:ListDistributions",
"         "cloudfront:ListTagsForResource",
"         "cloudfront:TagResource",
"         "cloudfront:UpdateDistribution"
"       ],
"       "Resource": "*"
"     }]
"   }
"
" CLEANUP NOTES
" ═════════════
" CloudFront distributions require two sequential deploys to delete:
"   1. Disable (UpdateDistribution with Enabled=false) → wait for Deployed
"   2. DeleteDistribution with the current ETag
"
" class_teardown performs both steps automatically.  The total wall-clock time
" for a full run (create → tests → disable → delete) is typically 20-40 minutes
" because each CloudFront propagation takes ~5-15 minutes.
"
" If teardown is interrupted the distribution will remain in the account.
" It is tagged  convert_test = true  so it can be found and deleted manually:
"   aws cloudfront list-distributions --query \
"     "DistributionList.Items[?Comment=='convert_test'].[Id,DomainName]"
" ──────────────────────────────────────────────────────────────────────────────
CLASS ltc_awsex_cl_fnt_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl           TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.
    " Max seconds to wait for a distribution status change (20 minutes).
    CONSTANTS cv_max_wait_sec  TYPE i                  VALUE 1200.
    " Poll interval in seconds.
    CONSTANTS cv_poll_interval TYPE i                  VALUE 30.

    CLASS-DATA ao_fnt          TYPE REF TO /aws1/if_fnt.
    CLASS-DATA ao_session      TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_fnt_actions  TYPE REF TO /awsex/cl_fnt_actions.

    " Distribution created in class_setup; used by all tests.
    CLASS-DATA av_dist_id      TYPE /aws1/fntstring.
    CLASS-DATA av_dist_arn     TYPE /aws1/fntstring.
    CLASS-DATA av_orig_comment TYPE /aws1/fntstring.

    METHODS: list_distributions  FOR TESTING RAISING /aws1/cx_rt_generic,
             update_distribution FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " Helper: poll GetDistribution until status = 'Deployed' or timeout.
    " Fails the test run if the distribution does not reach Deployed within
    " cv_max_wait_sec seconds.
    CLASS-METHODS wait_for_deployed
      IMPORTING
        iv_dist_id TYPE /aws1/fntstring
      RAISING
        /aws1/cx_rt_generic.

    " Helper: build the minimal DistributionConfig needed for create/update.
    " Uses a public HTTP endpoint as the origin so no real S3 bucket is needed.
    CLASS-METHODS build_minimal_dist_config
      IMPORTING
        iv_comment            TYPE /aws1/fntstring
        iv_enabled            TYPE /aws1/fntboolean DEFAULT abap_true
      RETURNING
        VALUE(oo_dist_config) TYPE REF TO /aws1/cl_fntdistributionconfig.

ENDCLASS.


CLASS ltc_awsex_cl_fnt_actions IMPLEMENTATION.

  " ─────────────────────────────────────────────────────────────────────────
  " class_setup
  " Creates a fresh CloudFront distribution tagged convert_test=true and
  " waits until it reaches the Deployed state before any test method runs.
  " ─────────────────────────────────────────────────────────────────────────
  METHOD class_setup.
    ao_session    = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_fnt        = /aws1/cl_fnt_factory=>create( ao_session ).
    ao_fnt_actions = NEW /awsex/cl_fnt_actions( ).

    " Use a unique caller-reference so repeated runs do not collide.
    DATA lv_uuid_str TYPE string.
    DATA lv_uuid     TYPE sysuuid_c32.
    lv_uuid     = cl_system_uuid=>create_uuid_c32_static( ).
    lv_uuid_str = lv_uuid.

    " Comment is used as our human-readable test marker and as the
    " value verified by the update_distribution test.
    av_orig_comment = |convert_test { lv_uuid_str }|.

    " Build a minimal distribution config pointing at the well-known
    " S3 website hostname.  This requires no bucket – CloudFront simply
    " forwards requests to the custom HTTP origin.
    DATA(lo_dist_config) = build_minimal_dist_config(
                             iv_comment = av_orig_comment
                             iv_enabled = abap_true ).

    " Wrap config with Tags so we can use CreateDistributionWithTags and
    " have the convert_test tag applied atomically at creation time.
    DATA lt_tag_items TYPE /aws1/cl_fnttag=>tt_taglist.
    APPEND NEW /aws1/cl_fnttag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_tag_items.

    DATA(lo_tags) = NEW /aws1/cl_fnttags( it_items = lt_tag_items ).

    DATA(lo_cfg_with_tags) = NEW /aws1/cl_fntdistributioncfgw00(
      io_distributionconfig = lo_dist_config
      io_tags               = lo_tags ).

    DATA(lo_create_result) = ao_fnt->createdistributionwithtags(
      io_distributioncfgwithtags = lo_cfg_with_tags ).

    av_dist_id  = lo_create_result->get_distribution( )->get_id( ).
    av_dist_arn = lo_create_result->get_distribution( )->get_arn( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = av_dist_id
      msg = 'class_setup: distribution ID must not be empty after create' ).

    " Wait for the distribution to become Deployed before running tests.
    " Tests that call UpdateDistribution require Deployed state.
    wait_for_deployed( av_dist_id ).

  ENDMETHOD.


  " ─────────────────────────────────────────────────────────────────────────
  " class_teardown
  " Disables the distribution (required before delete), waits for Deployed,
  " then deletes it.  Each sub-step has its own TRY/CATCH so a partial
  " failure in one step does not prevent the others from running.
  " ─────────────────────────────────────────────────────────────────────────
  METHOD class_teardown.
    IF av_dist_id IS INITIAL.
      RETURN.
    ENDIF.

    " ── Step 1: disable the distribution ──────────────────────────────────
    TRY.
        DATA(lo_cfg_result) = ao_fnt->getdistributionconfig(
          iv_id = av_dist_id ).
        DATA(lv_etag) = lo_cfg_result->get_etag( ).
        DATA(lo_cfg)  = lo_cfg_result->get_distributionconfig( ).

        DATA(lo_disabled_cfg) = build_minimal_dist_config(
          iv_comment = av_orig_comment
          iv_enabled = abap_false ).

        " Carry over the original origins/defaultcachebehavior so the
        " update does not violate any constraints.
        DATA(lo_full_disabled) = NEW /aws1/cl_fntdistributionconfig(
          io_aliases              = lo_cfg->get_aliases( )
          io_cachebehaviors       = lo_cfg->get_cachebehaviors( )
          io_customerrorresponses = lo_cfg->get_customerrorresponses( )
          io_defaultcachebehavior = lo_cfg->get_defaultcachebehavior( )
          io_logging              = lo_cfg->get_logging( )
          io_origingroups         = lo_cfg->get_origingroups( )
          io_origins              = lo_cfg->get_origins( )
          io_restrictions         = lo_cfg->get_restrictions( )
          io_viewercertificate    = lo_cfg->get_viewercertificate( )
          iv_callerreference      = lo_cfg->get_callerreference( )
          iv_comment              = av_orig_comment
          iv_defaultrootobject    = lo_cfg->get_defaultrootobject( )
          iv_enabled              = abap_false
          iv_httpversion          = lo_cfg->get_httpversion( )
          iv_isipv6enabled        = lo_cfg->get_isipv6enabled( )
          iv_priceclass           = lo_cfg->get_priceclass( )
          iv_webaclid             = lo_cfg->get_webaclid( )
        ).

        ao_fnt->updatedistribution(
          io_distributionconfig = lo_full_disabled
          iv_id                 = av_dist_id
          iv_ifmatch            = lv_etag ).

      CATCH /aws1/cx_rt_generic INTO DATA(lo_dis_ex).
        " Log but continue — attempt the delete anyway.
    ENDTRY.

    " ── Step 2: wait for Deployed after disable ────────────────────────────
    TRY.
        wait_for_deployed( av_dist_id ).
      CATCH /aws1/cx_rt_generic.
        " Best-effort; continue to delete attempt.
    ENDTRY.

    " ── Step 3: delete the distribution ───────────────────────────────────
    TRY.
        DATA(lo_del_cfg) = ao_fnt->getdistributionconfig(
          iv_id = av_dist_id ).
        ao_fnt->deletedistribution(
          iv_id       = av_dist_id
          iv_ifmatch  = lo_del_cfg->get_etag( ) ).
      CATCH /aws1/cx_rt_generic INTO DATA(lo_del_ex).
        " Distribution may still be deploying; leave it tagged for manual
        " cleanup.  The convert_test tag is already set from class_setup.
    ENDTRY.

  ENDMETHOD.


  " ─────────────────────────────────────────────────────────────────────────
  " wait_for_deployed
  " Polls GetDistribution every cv_poll_interval seconds until the status
  " becomes 'Deployed', or fails with cl_abap_unit_assert=>fail after
  " cv_max_wait_sec seconds total.
  " ─────────────────────────────────────────────────────────────────────────
  METHOD wait_for_deployed.
    DATA lv_start   TYPE timestampl.
    DATA lv_now     TYPE timestampl.
    DATA lv_elapsed TYPE i.
    DATA lv_status  TYPE /aws1/fntstring.

    GET TIME STAMP FIELD lv_start.

    DO.
      DATA(lo_dist_result) = ao_fnt->getdistribution( iv_id = iv_dist_id ).
      lv_status = lo_dist_result->get_distribution( )->get_status( ).

      IF lv_status = 'Deployed'.
        RETURN.
      ENDIF.

      WAIT UP TO cv_poll_interval SECONDS.

      GET TIME STAMP FIELD lv_now.
      lv_elapsed = cl_abap_tstmp=>subtract(
        tstmp1 = lv_now
        tstmp2 = lv_start ).

      IF lv_elapsed >= cv_max_wait_sec.
        cl_abap_unit_assert=>fail(
          msg = |Distribution { iv_dist_id } did not reach Deployed status | &&
                |within { cv_max_wait_sec } seconds. Last status: { lv_status }| ).
      ENDIF.
    ENDDO.

  ENDMETHOD.


  " ─────────────────────────────────────────────────────────────────────────
  " build_minimal_dist_config
  " Returns a DistributionConfig with a single custom HTTP origin pointing
  " at example.com.  This requires no real AWS resource as the origin and
  " satisfies all CloudFront required-field constraints.
  " ─────────────────────────────────────────────────────────────────────────
  METHOD build_minimal_dist_config.
    " Origin: example.com over HTTP port 80.
    " Using a well-known public domain avoids any S3 bucket dependency.
    DATA lt_ssl_protocols TYPE /aws1/cl_fntsslprotocolslist_w=>tt_sslprotocolslist.
    APPEND NEW /aws1/cl_fntsslprotocolslist_w( 'TLSv1.2' ) TO lt_ssl_protocols.

    DATA(lo_custom_origin) = NEW /aws1/cl_fntcustomoriginconfig(
      io_originsslprotocols    = NEW /aws1/cl_fntoriginsslprotocols(
        it_items   = lt_ssl_protocols
        iv_quantity = 1 )
      iv_httpport             = 80
      iv_httpsport            = 443
      iv_originprotocolpolicy = 'http-only' ).

    DATA lt_origins TYPE /aws1/cl_fntorigin=>tt_originlist.
    APPEND NEW /aws1/cl_fntorigin(
      " iv_domainname = 'example.com'
      io_customoriginconfig = lo_custom_origin
      iv_domainname         = 'example.com'
      iv_id                 = 'example-origin' ) TO lt_origins.

    DATA(lo_origins_obj) = NEW /aws1/cl_fntorigins(
      it_items    = lt_origins
      iv_quantity = 1 ).

    " DefaultCacheBehavior: viewer redirects to HTTPS, no query string
    " forwarding, managed CachingDisabled policy.
    DATA(lo_default_cb) = NEW /aws1/cl_fntdefaultcachebehav(
      " iv_cachepolicyid = '4135ea2d-6df8-44a3-9df3-4b5a84be39ad'  (CachingDisabled)
      iv_cachepolicyid        = '4135ea2d-6df8-44a3-9df3-4b5a84be39ad'
      iv_targetoriginid       = 'example-origin'
      iv_viewerprotocolpolicy = 'redirect-to-https' ).

    " GeoRestriction: none.
    DATA(lo_restrictions) = NEW /aws1/cl_fntrestrictions(
      io_georestriction = NEW /aws1/cl_fntgeorestriction(
        iv_restrictiontype = 'none'
        iv_quantity        = 0 ) ).

    " ViewerCertificate: use the CloudFront default certificate.
    DATA(lo_viewer_cert) = NEW /aws1/cl_fntviewercertificate(
      iv_cloudfrontdefaultcert = abap_true
      iv_minimumprotocolversion = 'TLSv1.2_2021'
      iv_sslsupportmethod       = 'sni-only' ).

    oo_dist_config = NEW /aws1/cl_fntdistributionconfig(
      io_defaultcachebehavior  = lo_default_cb
      io_origins               = lo_origins_obj
      io_restrictions          = lo_restrictions
      io_viewercertificate     = lo_viewer_cert
      iv_callerreference       = iv_comment  " re-use comment as unique ref
      iv_comment               = iv_comment
      iv_enabled               = iv_enabled
      iv_httpversion           = 'http2'
      iv_isipv6enabled         = abap_true
      iv_priceclass            = 'PriceClass_100' ).

  ENDMETHOD.


  " ═══════════════════════════════════════════════════════════════════════════
  " TEST: list_distributions
  " Verifies that list_distributions returns a bound result that includes the
  " distribution created during class_setup.
  " ═══════════════════════════════════════════════════════════════════════════
  METHOD list_distributions.
    DATA(lo_result) = ao_fnt_actions->list_distributions( ).

    " Result object must be bound.
    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_distributions: result object must be bound' ).

    " The distribution list wrapper must be present.
    DATA(lo_dl) = lo_result->get_distributionlist( ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_dl
      msg = 'list_distributions: DistributionList must be present' ).

    " The account must have at least the distribution created in class_setup.
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lo_dl->get_quantity( ) > 0 )
      msg = 'list_distributions: at least one distribution must be returned' ).

    " The distribution created in class_setup must appear in the list.
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_dl->get_items( ) INTO DATA(lo_item).
      IF lo_item->get_id( ) = av_dist_id.
        lv_found = abap_true.

        " Each summary must carry a non-empty domain name.
        cl_abap_unit_assert=>assert_not_initial(
          act = lo_item->get_domainname( )
          msg = 'list_distributions: test distribution must have a DomainName' ).

        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_distributions: distribution { av_dist_id } not found in list| ).

  ENDMETHOD.


  " ═══════════════════════════════════════════════════════════════════════════
  " TEST: update_distribution
  " Changes the Comment field on the test distribution and reads it back to
  " confirm the API call succeeded.  The original comment is restored in
  " class_teardown, not here, so that teardown always has a known-good state.
  " ═══════════════════════════════════════════════════════════════════════════
  METHOD update_distribution.
    DATA(lv_new_comment) = |convert_test updated { sy-datum } { sy-uzeit }|.

    " Call the action under test.
    ao_fnt_actions->update_distribution(
      iv_distribution_id = av_dist_id
      iv_new_comment     = lv_new_comment ).

    " Read the config back directly via the SDK to verify the change.
    DATA(lo_cfg_check) = ao_fnt->getdistributionconfig( iv_id = av_dist_id ).

    DATA(lv_actual) = lo_cfg_check
                        ->get_distributionconfig( )
                        ->get_comment( ).

    cl_abap_unit_assert=>assert_equals(
      exp = lv_new_comment
      act = lv_actual
      msg = |update_distribution: comment should be '{ lv_new_comment }' | &&
            |but was '{ lv_actual }'| ).

  ENDMETHOD.

ENDCLASS.
