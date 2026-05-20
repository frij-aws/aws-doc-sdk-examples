" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0
CLASS /awsex/cl_fnt_actions DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    METHODS list_distributions
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_fntlstdistributionsrs .

    METHODS update_distribution
      IMPORTING
        !iv_distribution_id TYPE /aws1/fntstring
        !iv_comment         TYPE /aws1/fntcommenttype .

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS /AWSEX/CL_FNT_ACTIONS IMPLEMENTATION.


  METHOD list_distributions.

    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_fnt) = /aws1/cl_fnt_factory=>create( lo_session ).

    " snippet-start:[fnt.abapv1.list_distributions]
    TRY.
        oo_result = lo_fnt->listdistributions( ).
        DATA(lt_items) =
          oo_result->get_distributionlist( )->get_items( ).
        MESSAGE |Retrieved { lines( lt_items ) } CloudFront distributions|
          TYPE 'I'.
      CATCH /aws1/cx_fntinvalidargument INTO DATA(lo_ex).
        MESSAGE lo_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_fntclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_fntserverexc INTO DATA(lo_server_ex).
        MESSAGE lo_server_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[fnt.abapv1.list_distributions]

  ENDMETHOD.


  METHOD update_distribution.

    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_fnt) = /aws1/cl_fnt_factory=>create( lo_session ).

    " snippet-start:[fnt.abapv1.update_distribution]
    TRY.
        " Retrieve the current distribution config and its ETag.
        " The ETag is used for optimistic locking on the update call.
        " Example distribution ID: 'E1EXAMPLE11111'
        DATA(lo_cfg_response) = lo_fnt->getdistributionconfig(
          iv_id = iv_distribution_id ).

        DATA(lo_dist_config) = lo_cfg_response->get_distributionconfig( ).
        DATA(lv_etag)        = lo_cfg_response->get_etag( ).

        " Reconstruct the distribution config, setting only the new comment.
        " All other fields are copied verbatim from the retrieved config.
        DATA(lo_updated_cfg) = NEW /aws1/cl_fntdistributionconfig(
          iv_callerreference    = lo_dist_config->get_callerreference( )
          io_aliases            = lo_dist_config->get_aliases( )
          iv_defaultrootobject  = lo_dist_config->get_defaultrootobject( )
          io_origins            = lo_dist_config->get_origins( )
          io_origingroups       = lo_dist_config->get_origingroups( )
          io_defaultcachebehavior =
            lo_dist_config->get_defaultcachebehavior( )
          io_cachebehaviors     = lo_dist_config->get_cachebehaviors( )
          io_customerrorresponses =
            lo_dist_config->get_customerrorresponses( )
          iv_comment            = iv_comment
          io_logging            = lo_dist_config->get_logging( )
          iv_priceclass         = lo_dist_config->get_priceclass( )
          iv_enabled            = lo_dist_config->get_enabled( )
          io_viewercertificate  = lo_dist_config->get_viewercertificate( )
          io_restrictions       = lo_dist_config->get_restrictions( )
          iv_webaclid           = lo_dist_config->get_webaclid( )
          iv_httpversion        = lo_dist_config->get_httpversion( )
          iv_isipv6enabled      = lo_dist_config->get_isipv6enabled( ) ).

        lo_fnt->updatedistribution(
          io_distributionconfig = lo_updated_cfg
          iv_id                 = iv_distribution_id
          iv_ifmatch            = lv_etag ).

        MESSAGE |Distribution { iv_distribution_id } updated| TYPE 'I'.
      CATCH /aws1/cx_fntnosuchdistribution INTO DATA(lo_no_dist_ex).
        MESSAGE lo_no_dist_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_fntaccessdenied INTO DATA(lo_access_ex).
        MESSAGE lo_access_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_fntinvalidifmatchvrs INTO DATA(lo_etag_ex).
        MESSAGE lo_etag_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_fntpreconditionfailed INTO DATA(lo_precond_ex).
        MESSAGE lo_precond_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_fntclientexc INTO DATA(lo_client_ex).
        MESSAGE lo_client_ex->get_text( ) TYPE 'E'.
      CATCH /aws1/cx_fntserverexc INTO DATA(lo_server_ex).
        MESSAGE lo_server_ex->get_text( ) TYPE 'E'.
    ENDTRY.
    " snippet-end:[fnt.abapv1.update_distribution]

  ENDMETHOD.
ENDCLASS.
