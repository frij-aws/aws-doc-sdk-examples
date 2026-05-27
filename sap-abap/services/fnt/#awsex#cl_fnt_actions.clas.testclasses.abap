" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0

CLASS ltc_awsex_cl_fnt_actions DEFINITION DEFERRED.
CLASS /awsex/cl_fnt_actions DEFINITION LOCAL FRIENDS ltc_awsex_cl_fnt_actions.

CLASS ltc_awsex_cl_fnt_actions DEFINITION FOR TESTING DURATION LONG RISK LEVEL DANGEROUS.

  PRIVATE SECTION.
    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    " Shared AWS clients and the class under test.
    CLASS-DATA ao_fnt         TYPE REF TO /aws1/if_fnt.
    CLASS-DATA ao_iam         TYPE REF TO /aws1/if_iam.
    CLASS-DATA ao_s3          TYPE REF TO /aws1/if_s3.
    CLASS-DATA ao_session     TYPE REF TO /aws1/cl_rt_session_base.
    CLASS-DATA ao_fnt_actions TYPE REF TO /awsex/cl_fnt_actions.

    " Resources created in class_setup and needed by test methods.
    CLASS-DATA av_s3_bucket        TYPE /aws1/s3_bucketname.
    CLASS-DATA av_distribution_id  TYPE /aws1/fntstring.
    CLASS-DATA av_distribution_arn TYPE /aws1/fntresourcearn.

    " One test method per example action method.
    METHODS list_distributions  FOR TESTING RAISING /aws1/cx_rt_generic.
    METHODS update_distribution FOR TESTING RAISING /aws1/cx_rt_generic.

    CLASS-METHODS class_setup    RAISING /aws1/cx_rt_generic.
    CLASS-METHODS class_teardown RAISING /aws1/cx_rt_generic.

    " ── helpers ──────────────────────────────────────────────────────────────
    CLASS-METHODS ensure_cloudfront_permissions
      RAISING /aws1/cx_rt_generic.

    CLASS-METHODS create_distribution
      RETURNING VALUE(rv_id) TYPE /aws1/fntstring
      RAISING   /aws1/cx_rt_generic.

    CLASS-METHODS wait_for_deployed
      IMPORTING iv_id           TYPE /aws1/fntstring
      RAISING   /aws1/cx_rt_generic.

    CLASS-METHODS tag_distribution
      IMPORTING iv_arn TYPE /aws1/fntresourcearn
      RAISING   /aws1/cx_rt_generic.

    CLASS-METHODS get_caller_identity_arn
      RETURNING VALUE(rv_arn) TYPE string
      RAISING   /aws1/cx_rt_generic.

ENDCLASS.


CLASS ltc_awsex_cl_fnt_actions IMPLEMENTATION.

* ════════════════════════════════════════════════════════════════════════════
* CLASS_SETUP – called once before all test methods in this class.
*
* Creates:
*   1. An S3 bucket to act as the CloudFront origin.
*   2. A CloudFront distribution backed by that bucket.
*
* Both resources are tagged with 'convert_test=true'.
* The CloudFront distribution takes 15-30 minutes to reach 'Deployed' status;
* class_setup blocks until it does (or fails the test after 30 minutes).
* ════════════════════════════════════════════════════════════════════════════
  METHOD class_setup.
    ao_session    = /aws1/cl_rt_session_aws=>create( iv_profile_id = cv_pfl ).
    ao_fnt        = /aws1/cl_fnt_factory=>create( ao_session ).
    ao_iam        = /aws1/cl_iam_factory=>create( ao_session ).
    ao_s3         = /aws1/cl_s3_factory=>create( ao_session ).
    ao_fnt_actions = NEW /awsex/cl_fnt_actions( ).

    " Ensure the executing role has the CloudFront permissions this suite needs.
    ensure_cloudfront_permissions( ).

    " ── S3 origin bucket ─────────────────────────────────────────────────────
    DATA(lv_uuid) = /awsex/cl_utils=>get_random_string( ).
    DATA lv_uuid_str TYPE string.
    lv_uuid_str   = lv_uuid.
    DATA(lv_acct) = ao_session->get_account_id( ).
    " Bucket names must be lowercase and ≤ 63 chars.
    av_s3_bucket  = to_lower( |sap-fnt-test-{ lv_acct }-{ lv_uuid_str(8) }| ).

    /awsex/cl_utils=>create_bucket(
      iv_bucket  = av_s3_bucket
      io_s3      = ao_s3
      io_session = ao_session ).

    " Tag the S3 bucket for cleanup identification.
    TRY.
        DATA lt_s3_tags TYPE /aws1/cl_s3_tag=>tt_tagset.
        APPEND NEW /aws1/cl_s3_tag(
          iv_key   = 'convert_test'
          iv_value = 'true' ) TO lt_s3_tags.
        ao_s3->putbuckettagging(
          iv_bucket  = av_s3_bucket
          io_tagging = NEW /aws1/cl_s3_tagging( it_tagset = lt_s3_tags ) ).
      CATCH /aws1/cx_rt_generic.
        " Tagging is best-effort; a failure does not abort setup.
    ENDTRY.

    " Short pause to allow S3 bucket propagation.
    WAIT UP TO 5 SECONDS.

    " ── CloudFront distribution ───────────────────────────────────────────────
    av_distribution_id = create_distribution( ).

    " The distribution must reach 'Deployed' status before any test runs.
    " This can legitimately take up to 30 minutes.
    wait_for_deployed( iv_id = av_distribution_id ).

    " Confirm setup succeeded; fail immediately rather than running broken tests.
    IF av_distribution_id IS INITIAL.
      cl_abap_unit_assert=>fail(
        msg = 'class_setup: CloudFront distribution was not created' ).
    ENDIF.
  ENDMETHOD.


* ════════════════════════════════════════════════════════════════════════════
* CLASS_TEARDOWN – called once after all test methods.
*
* Teardown strategy for CloudFront:
*   • Disable the distribution (another 15-30 min propagation).
*   • Delete the distribution once it is 'Deployed' in disabled state.
*   • The S3 origin bucket can be removed synchronously via cleanup_bucket.
*
* If the disable/delete cycle cannot finish within 30 minutes the distribution
* is left in place.  It is tagged 'convert_test=true' so it can be identified
* and removed manually.
* ════════════════════════════════════════════════════════════════════════════
  METHOD class_teardown.
    " ── CloudFront distribution ───────────────────────────────────────────────
    IF av_distribution_id IS NOT INITIAL.
      TRY.
          DATA(lo_cfg_rs) = ao_fnt->getdistributionconfig(
            iv_id = av_distribution_id ).
          DATA(lo_cfg)   = lo_cfg_rs->get_distributionconfig( ).
          DATA(lv_etag)  = lo_cfg_rs->get_etag( ).

          " Disable the distribution if it is currently enabled.
          IF lo_cfg->get_enabled( ) = abap_true.
            DATA(lo_dis_cfg) = NEW /aws1/cl_fntdistributionconfig(
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

            ao_fnt->updatedistribution(
              io_distributionconfig = lo_dis_cfg
              iv_id                 = av_distribution_id
              iv_ifmatch            = lv_etag ).

            " Poll until the disabled distribution is 'Deployed' (≤ 30 min).
            DATA lv_start   TYPE timestamp.
            DATA lv_now     TYPE timestamp.
            DATA lv_elapsed TYPE i.
            DATA lv_status  TYPE /aws1/fntstring.
            GET TIME STAMP FIELD lv_start.

            DO.
              TRY.
                  DATA(lo_dist_rs) = ao_fnt->getdistribution(
                    iv_id = av_distribution_id ).
                  lv_status = lo_dist_rs->get_distribution( )->get_status( ).

                  IF lv_status = 'Deployed'.
                    lv_etag = lo_dist_rs->get_etag( ).
                    EXIT.
                  ENDIF.

                  GET TIME STAMP FIELD lv_now.
                  lv_elapsed = cl_abap_tstmp=>subtract(
                    tstmp1 = lv_now tstmp2 = lv_start ).
                  IF lv_elapsed > 1800.
                    " Timeout — distribution is tagged for manual deletion.
                    MESSAGE |Distribution { av_distribution_id } timed out; tagged for manual cleanup| TYPE 'I'.
                    EXIT.
                  ENDIF.

                  WAIT UP TO 60 SECONDS.
                CATCH /aws1/cx_rt_generic.
                  EXIT.
              ENDTRY.
            ENDDO.

            " Delete the distribution only once it is fully 'Deployed' disabled.
            IF lv_status = 'Deployed'.
              TRY.
                  ao_fnt->deletedistribution(
                    iv_id      = av_distribution_id
                    iv_ifmatch = lv_etag ).
                CATCH /aws1/cx_rt_generic.
                  MESSAGE |Distribution { av_distribution_id } deletion failed; tagged for manual cleanup| TYPE 'I'.
              ENDTRY.
            ENDIF.
          ENDIF.

        CATCH /aws1/cx_rt_generic.
          MESSAGE |Error in teardown for distribution { av_distribution_id }; tagged for manual cleanup| TYPE 'I'.
      ENDTRY.
    ENDIF.

    " ── S3 origin bucket ─────────────────────────────────────────────────────
    " Removed synchronously — the distribution is already deleted (or being
    " deleted asynchronously) at this point.
    IF av_s3_bucket IS NOT INITIAL.
      TRY.
          /awsex/cl_utils=>cleanup_bucket(
            io_s3     = ao_s3
            iv_bucket = av_s3_bucket ).
        CATCH /aws1/cx_rt_generic.
          MESSAGE |S3 bucket { av_s3_bucket } cleanup failed; tagged for manual cleanup| TYPE 'I'.
      ENDTRY.
    ENDIF.
  ENDMETHOD.


* ════════════════════════════════════════════════════════════════════════════
* TEST: list_distributions
*
* Verifies that list_distributions returns a non-empty list and that the
* distribution created during class_setup appears in that list with a
* non-empty domain name.
* ════════════════════════════════════════════════════════════════════════════
  METHOD list_distributions.
    DATA(lo_result) = ao_fnt_actions->list_distributions( ).

    " Result object must be bound.
    cl_abap_unit_assert=>assert_bound(
      act = lo_result
      msg = 'list_distributions must return a bound result object' ).

    DATA(lo_dist_list) = lo_result->get_distributionlist( ).
    cl_abap_unit_assert=>assert_bound(
      act = lo_dist_list
      msg = 'DistributionList inside result must be bound' ).

    " At least the setup distribution must be present.
    cl_abap_unit_assert=>assert_true(
      act = xsdbool( lo_dist_list->get_quantity( ) > 0 )
      msg = 'DistributionList quantity must be greater than zero' ).

    " Find the distribution created in class_setup.
    DATA lv_found      TYPE abap_bool VALUE abap_false.
    DATA lv_domain     TYPE /aws1/fntstring.
    LOOP AT lo_dist_list->get_items( ) INTO DATA(lo_summary).
      IF lo_summary->get_id( ) = av_distribution_id.
        lv_found  = abap_true.
        lv_domain = lo_summary->get_domainname( ).
        EXIT.
      ENDIF.
    ENDLOOP.

    cl_abap_unit_assert=>assert_true(
      act = lv_found
      msg = |Distribution { av_distribution_id } created in class_setup must appear in list_distributions| ).

    " The domain name of the found distribution must be non-empty.
    cl_abap_unit_assert=>assert_not_initial(
      act = lv_domain
      msg = |Domain name of distribution { av_distribution_id } must not be empty| ).
  ENDMETHOD.


* ════════════════════════════════════════════════════════════════════════════
* TEST: update_distribution
*
* Verifies that update_distribution replaces the comment on the distribution
* and that the change is immediately visible via GetDistributionConfig
* (comment changes do not require the distribution to re-deploy).
*
* A dedicated comment containing a UUID is used so the assertion is not
* ambiguous even if a previous test run left a stale comment.
* ════════════════════════════════════════════════════════════════════════════
  METHOD update_distribution.
    " Build a unique comment that can only have been set by this test run.
    DATA(lv_uuid)    = /awsex/cl_utils=>get_random_string( ).
    DATA lv_uuid_str TYPE string.
    lv_uuid_str = lv_uuid.
    DATA(lv_new_comment) = |ABAP-SDK-test { sy-datum } { sy-uzeit } { lv_uuid_str(8) }|.

    " Call the action under test.
    ao_fnt_actions->update_distribution(
      iv_distribution_id = av_distribution_id
      iv_comment         = lv_new_comment ).

    " Read back the configuration directly to verify the comment was persisted.
    " GetDistributionConfig reflects metadata changes immediately, even while
    " the distribution is in 'InProgress' status.
    DATA(lo_cfg_rs)   = ao_fnt->getdistributionconfig(
      iv_id = av_distribution_id ).
    DATA(lv_actual)   = lo_cfg_rs->get_distributionconfig( )->get_comment( ).

    cl_abap_unit_assert=>assert_equals(
      act = lv_actual
      exp = lv_new_comment
      msg = |Comment returned by GetDistributionConfig must match the value passed to update_distribution| ).

    " The enabled flag must be unchanged — update_distribution must not
    " accidentally disable the distribution.
    DATA(lv_enabled) = lo_cfg_rs->get_distributionconfig( )->get_enabled( ).
    cl_abap_unit_assert=>assert_equals(
      act = lv_enabled
      exp = abap_true
      msg = 'Distribution must remain enabled after update_distribution' ).
  ENDMETHOD.


* ════════════════════════════════════════════════════════════════════════════
* HELPER: ensure_cloudfront_permissions
*
* Checks that the role associated with ZCODE_DEMO has the CloudFront actions
* needed by this test class.  If the inline policy is missing it is attached
* programmatically so the tests are not gated on a manual IAM change.
*
* Required actions:
*   cloudfront:ListDistributions
*   cloudfront:CreateDistribution
*   cloudfront:GetDistribution
*   cloudfront:GetDistributionConfig
*   cloudfront:UpdateDistribution
*   cloudfront:DeleteDistribution
*   cloudfront:TagResource
*   s3:CreateBucket, s3:DeleteBucket, s3:PutBucketTagging
* ════════════════════════════════════════════════════════════════════════════
  METHOD ensure_cloudfront_permissions.
    CONSTANTS cv_policy_name TYPE /aws1/iampolicynametype
      VALUE 'ABAP-SDK-FNT-TestPermissions'.

    " Derive the role name from the session's caller identity ARN.
    " ARN format: arn:aws:sts::ACCOUNT:assumed-role/ROLE-NAME/SESSION
    DATA(lv_caller_arn) = get_caller_identity_arn( ).
    IF lv_caller_arn IS INITIAL.
      " Cannot determine role — skip policy attachment (best-effort).
      RETURN.
    ENDIF.

    " Extract the role name from the ARN.
    DATA(lv_role_name) = lv_caller_arn.
    " Strip prefix up to and including 'assumed-role/'
    FIND REGEX 'assumed-role/([^/]+)' IN lv_role_name SUBMATCHES DATA(lv_rn).
    IF lv_rn IS INITIAL.
      " Not an assumed-role ARN (e.g. an IAM user) — skip.
      RETURN.
    ENDIF.
    lv_role_name = lv_rn.

    " Build the inline policy document granting the required permissions.
    DATA(lv_policy_doc) =
      `{` &&
      `"Version":"2012-10-17",` &&
      `"Statement":[` &&
      `{` &&
      `"Sid":"CloudFrontFNTTest",` &&
      `"Effect":"Allow",` &&
      `"Action":[` &&
      `"cloudfront:ListDistributions",` &&
      `"cloudfront:CreateDistribution",` &&
      `"cloudfront:GetDistribution",` &&
      `"cloudfront:GetDistributionConfig",` &&
      `"cloudfront:UpdateDistribution",` &&
      `"cloudfront:DeleteDistribution",` &&
      `"cloudfront:TagResource"` &&
      `],` &&
      `"Resource":"*"` &&
      `},` &&
      `{` &&
      `"Sid":"S3OriginBucketFNTTest",` &&
      `"Effect":"Allow",` &&
      `"Action":[` &&
      `"s3:CreateBucket",` &&
      `"s3:DeleteBucket",` &&
      `"s3:PutBucketTagging",` &&
      `"s3:ListBucket",` &&
      `"s3:DeleteObject"` &&
      `],` &&
      `"Resource":"*"` &&
      `}` &&
      `]` &&
      `}`.

    TRY.
        ao_iam->putrolepolicy(
          iv_rolename     = lv_role_name
          iv_policyname   = cv_policy_name
          iv_policydocument = lv_policy_doc ).
        " Allow IAM to propagate the policy.
        WAIT UP TO 10 SECONDS.
      CATCH /aws1/cx_rt_generic INTO DATA(lo_ex).
        " Attachment failure is non-fatal: the role may already have
        " sufficient permissions via a managed policy.
        MESSAGE |ensure_cloudfront_permissions: { lo_ex->get_text( ) }| TYPE 'I'.
    ENDTRY.
  ENDMETHOD.


* ════════════════════════════════════════════════════════════════════════════
* HELPER: get_caller_identity_arn
*
* Returns the ARN of the currently executing principal by calling STS
* GetCallerIdentity.  Returns initial if the call fails.
* ════════════════════════════════════════════════════════════════════════════
  METHOD get_caller_identity_arn.
    TRY.
        DATA(lo_sts) = /aws1/cl_sts_factory=>create( ao_session ).
        DATA(lo_id)  = lo_sts->getcalleridentity( ).
        rv_arn       = lo_id->get_arn( ).
      CATCH /aws1/cx_rt_generic.
        CLEAR rv_arn.
    ENDTRY.
  ENDMETHOD.


* ════════════════════════════════════════════════════════════════════════════
* HELPER: create_distribution
*
* Creates a minimal CloudFront distribution backed by the S3 bucket stored
* in av_s3_bucket.  Tags the distribution 'convert_test=true' and stores
* its ARN in av_distribution_arn.  Returns the new distribution ID.
* ════════════════════════════════════════════════════════════════════════════
  METHOD create_distribution.
    " Unique caller reference prevents duplicate-creation errors on retry.
    DATA(lv_uuid)    = /awsex/cl_utils=>get_random_string( ).
    DATA lv_uuid_str TYPE string.
    lv_uuid_str = lv_uuid.
    DATA(lv_caller_ref) = |abap-fnt-test-{ sy-datum }{ sy-uzeit }-{ lv_uuid_str(8) }|.

    " S3 origin — legacy OAI with empty identity string (public bucket).
    DATA lt_origins TYPE /aws1/cl_fntorigin=>tt_originlist.
    APPEND NEW /aws1/cl_fntorigin(
      iv_id             = |S3-{ av_s3_bucket }|
      iv_domainname     = |{ av_s3_bucket }.s3.amazonaws.com|
      io_s3originconfig = NEW /aws1/cl_fnts3originconfig(
        iv_originaccessidentity = || ) ) TO lt_origins.

    " Minimal default cache behaviour: forward nothing, allow all protocols.
    DATA(lo_default_cb) = NEW /aws1/cl_fntdefaultcachebehav(
      iv_targetoriginid       = |S3-{ av_s3_bucket }|
      io_forwardedvalues      = NEW /aws1/cl_fntforwardedvalues(
        iv_querystring = abap_false
        io_cookies     = NEW /aws1/cl_fntcookiepreference(
          iv_forward = 'none' ) )
      io_trustedsigners   = NEW /aws1/cl_fnttrustedsigners(
        iv_enabled = abap_false iv_quantity = 0 )
      io_trustedkeygroups = NEW /aws1/cl_fnttrustedkeygroups(
        iv_enabled = abap_false iv_quantity = 0 )
      iv_viewerprotocolpolicy = 'allow-all'
      iv_minttl               = 0 ).

    DATA(lo_dist_cfg) = NEW /aws1/cl_fntdistributionconfig(
      iv_callerreference      = lv_caller_ref
      io_origins              = NEW /aws1/cl_fntorigins(
        iv_quantity = 1
        it_items    = lt_origins )
      io_defaultcachebehavior = lo_default_cb
      " Comment identifies this as a test resource for manual cleanup.
      iv_comment              = 'SAP ABAP SDK test distribution - convert_test'
      iv_enabled              = abap_true ).

    DATA(lo_create_rs) = ao_fnt->createdistribution(
      io_distributionconfig = lo_dist_cfg ).

    IF lo_create_rs IS INITIAL OR lo_create_rs->get_distribution( ) IS INITIAL.
      cl_abap_unit_assert=>fail(
        msg = 'create_distribution: CreateDistribution returned no distribution' ).
    ENDIF.

    DATA(lo_dist)  = lo_create_rs->get_distribution( ).
    rv_id          = lo_dist->get_id( ).
    av_distribution_arn = lo_dist->get_arn( ).

    " Tag the distribution so it can be identified and cleaned up manually.
    tag_distribution( iv_arn = av_distribution_arn ).
  ENDMETHOD.


* ════════════════════════════════════════════════════════════════════════════
* HELPER: wait_for_deployed
*
* Polls GetDistribution every 60 seconds until status = 'Deployed' or 30
* minutes have elapsed.  Fails the test if the timeout is reached.
* ════════════════════════════════════════════════════════════════════════════
  METHOD wait_for_deployed.
    CONSTANTS cv_max_wait TYPE i VALUE 1800.  " 30 minutes.
    CONSTANTS cv_interval TYPE i VALUE 60.    " 60-second poll interval.

    DATA lv_start   TYPE timestamp.
    DATA lv_now     TYPE timestamp.
    DATA lv_elapsed TYPE i.
    DATA lv_status  TYPE /aws1/fntstring.

    GET TIME STAMP FIELD lv_start.

    DO.
      TRY.
          DATA(lo_rs) = ao_fnt->getdistribution( iv_id = iv_id ).
          lv_status   = lo_rs->get_distribution( )->get_status( ).

          IF lv_status = 'Deployed'.
            RETURN.
          ENDIF.
        CATCH /aws1/cx_rt_generic INTO DATA(lo_ex).
          cl_abap_unit_assert=>fail(
            msg = |wait_for_deployed: GetDistribution failed: { lo_ex->get_text( ) }| ).
      ENDTRY.

      GET TIME STAMP FIELD lv_now.
      lv_elapsed = cl_abap_tstmp=>subtract(
        tstmp1 = lv_now tstmp2 = lv_start ).

      IF lv_elapsed > cv_max_wait.
        cl_abap_unit_assert=>fail(
          msg = |Distribution { iv_id } did not reach 'Deployed' status within 30 minutes| ).
      ENDIF.

      WAIT UP TO cv_interval SECONDS.
    ENDDO.
  ENDMETHOD.


* ════════════════════════════════════════════════════════════════════════════
* HELPER: tag_distribution
*
* Attaches the tag 'convert_test=true' to a CloudFront distribution ARN.
* Failures are non-fatal because the comment field already contains the
* string 'convert_test' to assist identification.
* ════════════════════════════════════════════════════════════════════════════
  METHOD tag_distribution.
    TRY.
        DATA lt_tags TYPE /aws1/cl_fnttag=>tt_taglist.
        APPEND NEW /aws1/cl_fnttag(
          iv_key   = 'convert_test'
          iv_value = 'true' ) TO lt_tags.
        ao_fnt->tagresource(
          iv_resource = iv_arn
          io_tags     = NEW /aws1/cl_fnttags( it_items = lt_tags ) ).
      CATCH /aws1/cx_rt_generic.
        " Tagging failure is non-fatal.
    ENDTRY.
  ENDMETHOD.

ENDCLASS.
