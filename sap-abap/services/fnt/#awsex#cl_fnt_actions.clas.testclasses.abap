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

    " Shared class-level state.
    CLASS-DATA ao_fnt     TYPE REF TO /aws1/if_fnt.
    CLASS-DATA ao_s3      TYPE REF TO /aws1/if_s3.
    CLASS-DATA ao_session TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_fnt_actions TYPE REF TO /awsex/cl_fnt_actions.

    " Resources created during class_setup. Both take very long to clean up
    " so they are tagged with 'convert_test' for manual teardown.
    CLASS-DATA av_s3_bucket       TYPE /aws1/s3_bucketname.
    CLASS-DATA av_distribution_id TYPE /aws1/fntstring.
    CLASS-DATA av_distribution_arn TYPE /aws1/fntresourcearn.

    " Test methods – one per service operation.
    METHODS list_distributions
        FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_distribution
        FOR TESTING RAISING /aws1/cx_rt_generic.

    " Lifecycle.
    CLASS-METHODS class_setup   RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " Helpers.
    CLASS-METHODS create_test_distribution
      RETURNING VALUE(rv_id) TYPE /aws1/fntstring
      RAISING   /aws1/cx_rt_generic.

    CLASS-METHODS wait_for_distribution_deployed
      IMPORTING iv_distribution_id TYPE /aws1/fntstring
      RAISING   /aws1/cx_rt_generic.

    CLASS-METHODS tag_distribution_resource
      IMPORTING iv_distribution_arn TYPE /aws1/fntresourcearn
      RAISING   /aws1/cx_rt_generic.

ENDCLASS.


CLASS ltc_awsex_cl_fnt_actions IMPLEMENTATION.

*--------------------------------------------------------------------*
* class_setup
*   Creates all resources needed across all test methods.
*   Resources that cannot be cleaned up quickly (CloudFront distributions
*   take 15-30 min to disable + delete, S3 buckets used as CF origins
*   should outlive the distribution) are tagged with 'convert_test'
*   so operators can identify and delete them manually.
*--------------------------------------------------------------------*
  METHOD class_setup.

    ao_session = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_fnt     = /aws1/cl_fnt_factory=>create( ao_session ).
    ao_s3      = /aws1/cl_s3_factory=>create( ao_session ).
    ao_fnt_actions = NEW /awsex/cl_fnt_actions( ).

    " ── 1. Create a unique S3 bucket to serve as CloudFront origin ──────
    DATA(lv_uuid) = /awsex/cl_utils=>get_random_string( ).
    DATA(lv_acct) = ao_session->get_account_id( ).
    " Bucket names must be lowercase and <= 63 chars.
    av_s3_bucket = to_lower( |sap-fnt-test-{ lv_acct }-{ lv_uuid }| ).
    " Truncate to 63 characters if needed.
    IF strlen( av_s3_bucket ) > 63.
      av_s3_bucket = av_s3_bucket(63).
    ENDIF.

    " Use the util helper which handles the us-east-1 location-constraint rule.
    /awsex/cl_utils=>create_bucket(
      iv_bucket  = av_s3_bucket
      io_s3      = ao_s3
      io_session = ao_session ).

    " Tag the S3 bucket so it can be identified for manual cleanup.
    DATA lt_s3_tags TYPE /aws1/cl_s3_tag=>tt_tagset.
    APPEND NEW /aws1/cl_s3_tag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_s3_tags.
    TRY.
        ao_s3->putbuckettagging(
          iv_bucket  = av_s3_bucket
          io_tagging = NEW /aws1/cl_s3_tagging( it_tagset = lt_s3_tags ) ).
      CATCH /aws1/cx_rt_generic.
        " Non-fatal – tagging failure should not abort setup.
    ENDTRY.

    " Wait briefly so the bucket endpoint is fully available.
    WAIT UP TO 5 SECONDS.

    " ── 2. Create the CloudFront distribution that tests will use ────────
    av_distribution_id = create_test_distribution( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = av_distribution_id
      msg = 'class_setup: CloudFront distribution was not created' ).

    " ── 3. Tag the distribution for manual cleanup ───────────────────────
    tag_distribution_resource( iv_distribution_arn = av_distribution_arn ).

    " ── 4. Wait until the distribution reaches 'Deployed' status ─────────
    " CloudFront distributions typically take 5-20 minutes to deploy.
    " Tests that call update_distribution also need a Deployed baseline.
    wait_for_distribution_deployed( iv_distribution_id = av_distribution_id ).

  ENDMETHOD.


*--------------------------------------------------------------------*
* class_teardown
*   CloudFront distributions must first be DISABLED and allowed to
*   reach 'Deployed' (disabled) before they can be deleted.  That
*   second propagation cycle can take another 15-30 minutes.
*
*   Strategy: attempt a best-effort disable + delete here.  If the
*   process times out we leave the distribution in place; it is
*   tagged 'convert_test' and will be cleaned up manually.
*   The S3 origin bucket is also left tagged for manual cleanup because
*   it must outlive the distribution.
*--------------------------------------------------------------------*
  METHOD class_teardown.

    IF av_distribution_id IS INITIAL.
      RETURN.
    ENDIF.

    " ── Step 1: Read current config & ETag ──────────────────────────────
    DATA lo_cfg_rs  TYPE REF TO /aws1/cl_fntgetdistributionc01.
    DATA lo_old_cfg TYPE REF TO /aws1/cl_fntdistributionconfig.
    DATA lv_etag    TYPE /aws1/fntstring.

    TRY.
        lo_cfg_rs  = ao_fnt->getdistributionconfig( iv_id = av_distribution_id ).
        lo_old_cfg = lo_cfg_rs->get_distributionconfig( ).
        lv_etag    = lo_cfg_rs->get_etag( ).
      CATCH /aws1/cx_rt_generic.
        " Cannot read config – distribution may already be gone.
        RETURN.
    ENDTRY.

    " ── Step 2: Disable only if currently enabled ───────────────────────
    IF lo_old_cfg->get_enabled( ) = abap_true.
      TRY.
          DATA(lo_disabled_cfg) = NEW /aws1/cl_fntdistributionconfig(
            iv_callerreference    = lo_old_cfg->get_callerreference( )
            io_aliases            = lo_old_cfg->get_aliases( )
            iv_defaultrootobject  = lo_old_cfg->get_defaultrootobject( )
            io_origins            = lo_old_cfg->get_origins( )
            io_origingroups       = lo_old_cfg->get_origingroups( )
            io_defaultcachebehavior = lo_old_cfg->get_defaultcachebehavior( )
            io_cachebehaviors     = lo_old_cfg->get_cachebehaviors( )
            io_customerrorresponses = lo_old_cfg->get_customerrorresponses( )
            iv_comment            = lo_old_cfg->get_comment( )
            io_logging            = lo_old_cfg->get_logging( )
            iv_priceclass         = lo_old_cfg->get_priceclass( )
            iv_enabled            = abap_false
            io_viewercertificate  = lo_old_cfg->get_viewercertificate( )
            io_restrictions       = lo_old_cfg->get_restrictions( )
            iv_webaclid           = lo_old_cfg->get_webaclid( )
            iv_httpversion        = lo_old_cfg->get_httpversion( )
            iv_isipv6enabled      = lo_old_cfg->get_isipv6enabled( ) ).

          DATA(lo_upd_rs) = ao_fnt->updatedistribution(
            io_distributionconfig = lo_disabled_cfg
            iv_id                 = av_distribution_id
            iv_ifmatch            = lv_etag ).
          lv_etag = lo_upd_rs->get_etag( ).
        CATCH /aws1/cx_rt_generic.
          " Could not disable – leave tagged for manual cleanup.
          RETURN.
      ENDTRY.
    ENDIF.

    " ── Step 3: Poll until Deployed (disabled) – max 40 minutes ─────────
    DATA lv_ts_start  TYPE timestampl.
    DATA lv_ts_now    TYPE timestampl.
    DATA lv_elapsed   TYPE decfloat16.
    DATA lv_status    TYPE /aws1/fntstring.
    DATA lv_max_secs  TYPE i VALUE 2400.   " 40 minutes.

    GET TIME STAMP FIELD lv_ts_start.

    DO.
      TRY.
          DATA(lo_dist_rs) = ao_fnt->getdistribution( iv_id = av_distribution_id ).
          lv_status = lo_dist_rs->get_distribution( )->get_status( ).

          IF lv_status = 'Deployed'.
            lv_etag = lo_dist_rs->get_etag( ).
            EXIT.
          ENDIF.
        CATCH /aws1/cx_rt_generic.
          EXIT.   " Cannot read – abort polling.
      ENDTRY.

      GET TIME STAMP FIELD lv_ts_now.
      lv_elapsed = cl_abap_tstmp=>subtract(
        tstmp1 = lv_ts_now
        tstmp2 = lv_ts_start ).

      IF lv_elapsed > lv_max_secs.
        " Timeout: distribution is tagged – operators will clean it up.
        MESSAGE |CloudFront distribution { av_distribution_id } still deploying| &
                | - tagged convert_test for manual cleanup| TYPE 'W'.
        RETURN.
      ENDIF.

      WAIT UP TO 60 SECONDS.
    ENDDO.

    " ── Step 4: Delete ──────────────────────────────────────────────────
    IF lv_status = 'Deployed'.
      TRY.
          ao_fnt->deletedistribution(
            iv_id      = av_distribution_id
            iv_ifmatch = lv_etag ).
        CATCH /aws1/cx_rt_generic.
          " Tagged for manual cleanup.
      ENDTRY.
    ENDIF.

    " S3 origin bucket is intentionally left; it is tagged 'convert_test'.

  ENDMETHOD.


*--------------------------------------------------------------------*
* create_test_distribution  (helper)
*   Builds a minimal CloudFront distribution backed by the S3 bucket
*   that was created in class_setup.  Uses OAI-less access (public
*   bucket) to keep setup simple.
*--------------------------------------------------------------------*
  METHOD create_test_distribution.

    DATA lv_uuid      TYPE string.
    DATA lv_caller_ref TYPE /aws1/fntstring.

    lv_uuid       = /awsex/cl_utils=>get_random_string( ).
    lv_caller_ref = |abap-test-{ sy-datum }{ sy-uzeit }-{ lv_uuid }|.

    " S3 website-style domain; no OAI required (open origin).
    DATA(lv_s3_domain) = |{ av_s3_bucket }.s3.amazonaws.com|.
    DATA(lv_origin_id) = |S3-{ av_s3_bucket }|.

    " ── Origin ─────────────────────────────────────────────────────────
    DATA lt_origins TYPE /aws1/cl_fntorigin=>tt_originlist.
    APPEND NEW /aws1/cl_fntorigin(
      iv_id         = lv_origin_id
      iv_domainname = lv_s3_domain
      io_s3originconfig = NEW /aws1/cl_fnts3originconfig(
        iv_originaccessidentity = || ) ) TO lt_origins.

    DATA(lo_origins) = NEW /aws1/cl_fntorigins(
      iv_quantity = 1
      it_items    = lt_origins ).

    " ── Default cache behaviour ─────────────────────────────────────────
    DATA(lo_fwd_values) = NEW /aws1/cl_fntforwardedvalues(
      iv_querystring = abap_false
      io_cookies     = NEW /aws1/cl_fntcookiepreference( iv_forward = 'none' ) ).

    DATA(lo_def_cache) = NEW /aws1/cl_fntdefaultcachebehav(
      iv_targetoriginid      = lv_origin_id
      io_forwardedvalues     = lo_fwd_values
      io_trustedsigners      = NEW /aws1/cl_fnttrustedsigners(
        iv_enabled  = abap_false
        iv_quantity = 0 )
      io_trustedkeygroups    = NEW /aws1/cl_fnttrustedkeygroups(
        iv_enabled  = abap_false
        iv_quantity = 0 )
      iv_viewerprotocolpolicy = 'allow-all'
      iv_minttl               = 0 ).

    " ── Distribution config ─────────────────────────────────────────────
    DATA(lo_dist_cfg) = NEW /aws1/cl_fntdistributionconfig(
      iv_callerreference      = lv_caller_ref
      io_origins              = lo_origins
      io_defaultcachebehavior = lo_def_cache
      iv_comment              = 'SAP ABAP convert_test distribution'
      iv_enabled              = abap_true ).

    " ── Create ──────────────────────────────────────────────────────────
    DATA(lo_create_rs) = ao_fnt->createdistribution(
      io_distributionconfig = lo_dist_cfg ).

    DATA(lo_dist)    = lo_create_rs->get_distribution( ).
    rv_id            = lo_dist->get_id( ).
    av_distribution_arn = lo_dist->get_arn( ).

    cl_abap_unit_assert=>assert_not_initial(
      act = rv_id
      msg = 'create_test_distribution: ID is empty after creation' ).

  ENDMETHOD.


*--------------------------------------------------------------------*
* wait_for_distribution_deployed  (helper)
*   Polls GetDistribution until status = 'Deployed' or 40 min timeout.
*   Fails the test if it times out so tests never run against a
*   distribution that is still propagating.
*--------------------------------------------------------------------*
  METHOD wait_for_distribution_deployed.

    DATA lv_ts_start TYPE timestampl.
    DATA lv_ts_now   TYPE timestampl.
    DATA lv_elapsed  TYPE decfloat16.
    DATA lv_status   TYPE /aws1/fntstring.
    DATA lv_max_secs TYPE i VALUE 2400.   " 40 minutes.

    GET TIME STAMP FIELD lv_ts_start.

    DO.
      TRY.
          DATA(lo_dist_rs) = ao_fnt->getdistribution(
            iv_id = iv_distribution_id ).
          lv_status = lo_dist_rs->get_distribution( )->get_status( ).

          IF lv_status = 'Deployed'.
            RETURN.
          ENDIF.
        CATCH /aws1/cx_rt_generic INTO DATA(lo_ex).
          cl_abap_unit_assert=>fail(
            msg = |wait_for_distribution_deployed: { lo_ex->get_text( ) }| ).
      ENDTRY.

      GET TIME STAMP FIELD lv_ts_now.
      lv_elapsed = cl_abap_tstmp=>subtract(
        tstmp1 = lv_ts_now
        tstmp2 = lv_ts_start ).

      IF lv_elapsed > lv_max_secs.
        cl_abap_unit_assert=>fail(
          msg = |Distribution { iv_distribution_id } still not Deployed| &
                | after { lv_max_secs } seconds| ).
      ENDIF.

      WAIT UP TO 60 SECONDS.
    ENDDO.

  ENDMETHOD.


*--------------------------------------------------------------------*
* tag_distribution_resource  (helper)
*   Tags the CloudFront distribution with 'convert_test = true' using
*   the correct CloudFront TagResource API (not S3 tags).
*--------------------------------------------------------------------*
  METHOD tag_distribution_resource.

    DATA lt_fnt_tags TYPE /aws1/cl_fnttag=>tt_taglist.
    APPEND NEW /aws1/cl_fnttag(
      iv_key   = 'convert_test'
      iv_value = 'true' ) TO lt_fnt_tags.

    TRY.
        ao_fnt->tagresource(
          iv_resource = iv_distribution_arn
          io_tags     = NEW /aws1/cl_fnttags( it_items = lt_fnt_tags ) ).
      CATCH /aws1/cx_rt_generic.
        " Tagging is best-effort; the comment field already contains
        " 'convert_test' so the distribution can still be found manually.
    ENDTRY.

  ENDMETHOD.


*--------------------------------------------------------------------*
* TEST: list_distributions
*   Calls the action and asserts:
*     • The result object is bound.
*     • The distribution list is present.
*     • Our test distribution appears in the list (by ID).
*     • The returned Quantity >= 1.
*--------------------------------------------------------------------*
  METHOD list_distributions.

    DATA lo_result TYPE REF TO /aws1/cl_fntlstdistributionsrs.

    ao_fnt_actions->list_distributions(
      IMPORTING oo_result = lo_result ).

    " The result must be bound.
    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_distributions: result object is unbound' ).

    " The distribution list wrapper must be present.
    DATA(lo_dist_list) = lo_result->get_distributionlist( ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_dist_list
      msg = 'list_distributions: DistributionList is unbound' ).

    " At least one distribution must be returned (we just created one).
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lo_dist_list->get_quantity( ) > 0 )
      msg = 'list_distributions: Quantity must be > 0' ).

    " Our test distribution must appear in the list.
    DATA lv_found TYPE abap_bool VALUE abap_false.
    LOOP AT lo_dist_list->get_items( ) INTO DATA(lo_summ).
      IF lo_summ->get_id( ) = av_distribution_id.
        lv_found = abap_true.

        " Verify key fields are populated.
        cl_abap_unit_assert=>assert_not_initial(
          act = lo_summ->get_domainname( )
          msg = 'list_distributions: DomainName must not be empty' ).

        cl_abap_unit_assert=>assert_not_initial(
          act = lo_summ->get_status( )
          msg = 'list_distributions: Status must not be empty' ).

        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |list_distributions: distribution { av_distribution_id }| &
            | not found in list| ).

  ENDMETHOD.


*--------------------------------------------------------------------*
* TEST: update_distribution
*   Updates the comment on the shared test distribution and verifies
*   that the new value is readable via GetDistributionConfig.
*   A fresh random string is used as the comment each run.
*--------------------------------------------------------------------*
  METHOD update_distribution.

    " Build a unique new comment so we can detect stale values.
    DATA lv_uuid       TYPE string.
    DATA lv_new_comment TYPE /aws1/fntcommenttype.
    lv_uuid        = /awsex/cl_utils=>get_random_string( ).
    lv_new_comment = |Updated { sy-datum }{ sy-uzeit } { lv_uuid }|.

    " Call the action under test.
    ao_fnt_actions->update_distribution(
      iv_distribution_id = av_distribution_id
      iv_comment         = lv_new_comment ).

    " Read back the configuration and assert the comment was persisted.
    DATA(lo_cfg_rs)  = ao_fnt->getdistributionconfig(
      iv_id = av_distribution_id ).
    DATA(lo_cfg)     = lo_cfg_rs->get_distributionconfig( ).

    cl_abap_unit_assert=>assert_equals(
      act = lo_cfg->get_comment( )
      exp = lv_new_comment
      msg = |update_distribution: comment should be '{ lv_new_comment }'| &
            | but was '{ lo_cfg->get_comment( ) }'| ).

    " The distribution must still be enabled after the update.
    cl_abap_unit_assert=>assert_equals(
      act = lo_cfg->get_enabled( )
      exp = abap_true
      msg = 'update_distribution: distribution must remain enabled' ).

  ENDMETHOD.

ENDCLASS.
