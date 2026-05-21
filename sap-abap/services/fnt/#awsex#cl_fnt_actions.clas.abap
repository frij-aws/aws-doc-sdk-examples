" Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
" SPDX-License-Identifier: Apache-2.0

CLASS /awsex/cl_fnt_actions DEFINITION
  PUBLIC
  FINAL
  CREATE PUBLIC .

  PUBLIC SECTION.

    METHODS list_distributions
      RETURNING
        VALUE(oo_result) TYPE REF TO /aws1/cl_fntlstdistributionsrs
      RAISING
        /aws1/cx_rt_generic .

    METHODS update_distribution
      IMPORTING
        !iv_distribution_id TYPE /aws1/fntstring
        !iv_new_comment     TYPE /aws1/fntstring
      RAISING
        /aws1/cx_rt_generic .

  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS /awsex/cl_fnt_actions IMPLEMENTATION.

  METHOD list_distributions.

    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_fnt) = /aws1/cl_fnt_factory=>create( lo_session ).

    " snippet-start:[fnt.abapv1.listdistributions]
    TRY.
        oo_result = lo_fnt->listdistributions( ).
        DATA(lo_distribution_list) = oo_result->get_distributionlist( ).
        MESSAGE |Retrieved { lo_distribution_list->get_quantity( ) } CloudFront distributions| TYPE 'I'.
      CATCH /aws1/cx_fntinvalidargument INTO DATA(lo_ex).
        MESSAGE lo_ex->if_message~get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[fnt.abapv1.listdistributions]

  ENDMETHOD.

  METHOD update_distribution.

    CONSTANTS cv_pfl TYPE /aws1/rt_profile_id VALUE 'ZCODE_DEMO'.

    DATA(lo_session) = /aws1/cl_rt_session_aws=>create( cv_pfl ).
    DATA(lo_fnt) = /aws1/cl_fnt_factory=>create( lo_session ).

    " snippet-start:[fnt.abapv1.updatedistribution]
    TRY.
        " iv_distribution_id = 'E1PA6795UKMFR9'
        DATA(lo_config_result) = lo_fnt->getdistributionconfig(
          iv_id = iv_distribution_id
        ).
        DATA(lo_dist_config) = lo_config_result->get_distributionconfig( ).
        DATA(lv_etag) = lo_config_result->get_etag( ).

        " Update the comment field on the existing distribution config object.
        " The /aws1/cl_fntdistributionconfig object does not expose a setter,
        " so we reconstruct the config carrying the new comment value.
        DATA(lo_new_config) = NEW /aws1/cl_fntdistributionconfig(
          io_aliases               = lo_dist_config->get_aliases( )
          io_cachebehaviors        = lo_dist_config->get_cachebehaviors( )
          io_customerrorresponses  = lo_dist_config->get_customerrorresponses( )
          io_defaultcachebehavior  = lo_dist_config->get_defaultcachebehavior( )
          io_logging               = lo_dist_config->get_logging( )
          io_origingroups          = lo_dist_config->get_origingroups( )
          io_origins               = lo_dist_config->get_origins( )
          io_restrictions          = lo_dist_config->get_restrictions( )
          io_viewercertificate     = lo_dist_config->get_viewercertificate( )
          iv_callerreference       = lo_dist_config->get_callerreference( )
          iv_comment               = iv_new_comment
          iv_defaultrootobject     = lo_dist_config->get_defaultrootobject( )
          iv_enabled               = lo_dist_config->get_enabled( )
          iv_httpversion           = lo_dist_config->get_httpversion( )
          iv_isipv6enabled         = lo_dist_config->get_isipv6enabled( )
          iv_priceclass            = lo_dist_config->get_priceclass( )
          iv_webaclid              = lo_dist_config->get_webaclid( )
        ).

        DATA(lo_update_result) = lo_fnt->updatedistribution(
          io_distributionconfig = lo_new_config
          iv_id                 = iv_distribution_id
          iv_ifmatch            = lv_etag
        ).
        MESSAGE |Distribution { iv_distribution_id } updated: comment is now '{ iv_new_comment }'| TYPE 'I'.
      CATCH /aws1/cx_fntnosuchdistribution INTO DATA(lo_ex).
        MESSAGE lo_ex->if_message~get_text( ) TYPE 'I'.
      CATCH /aws1/cx_fntinvalidargument INTO DATA(lo_ex2).
        MESSAGE lo_ex2->if_message~get_text( ) TYPE 'I'.
      CATCH /aws1/cx_fntpreconditionfailed INTO DATA(lo_ex3).
        MESSAGE lo_ex3->if_message~get_text( ) TYPE 'I'.
      CATCH /aws1/cx_fntillegalupdate INTO DATA(lo_ex4).
        MESSAGE lo_ex4->if_message~get_text( ) TYPE 'I'.
    ENDTRY.
    " snippet-end:[fnt.abapv1.updatedistribution]

  ENDMETHOD.

ENDCLASS.
