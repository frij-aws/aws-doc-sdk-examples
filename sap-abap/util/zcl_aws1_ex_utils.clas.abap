class ZCL_AWS1_EX_UTILS definition
  public
  final
  create public .

public section.

  constants CV_ASSET_PREFIX type STRING value 'aws-example' ##NO_TEXT.

  class-methods GET_RANDOM_STRING
    returning
      value(OV_STR) type STRING .
  class-methods CLEANUP_BUCKET
    importing
      !IV_BUCKET type /AWS1/S3_BUCKETNAME
      !IO_S3 type ref to /AWS1/IF_S3
    raising
      /AWS1/CX_RT_GENERIC .
  class-methods CREATE_BUCKET
    importing
      !IV_BUCKET type /AWS1/S3_BUCKETNAME
      !IO_S3 type ref to /AWS1/IF_S3
      !IO_SESSION type ref to /AWS1/CL_RT_SESSION_BASE
    raising
      /AWS1/CX_RT_GENERIC .
  PROTECTED SECTION.
  PRIVATE SECTION.
ENDCLASS.



CLASS ZCL_AWS1_EX_UTILS IMPLEMENTATION.


  method CLEANUP_BUCKET.
        TRY.
        DATA lt_obj TYPE /aws1/cl_s3_objectidentifier=>tt_objectidentifierlist.
        LOOP AT io_s3->listobjectsv2( iv_bucket = iv_bucket )->get_contents( ) ASSIGNING FIELD-SYMBOL(<obj>).
          APPEND NEW /aws1/cl_s3_objectidentifier( iv_key = <obj>->get_key( ) ) TO lt_obj.
        ENDLOOP.
        IF lines( lt_obj ) > 0.
          io_s3->deleteobjects(
               iv_bucket                     = iv_bucket
               io_delete                     = NEW /aws1/cl_s3_delete( it_objects = lt_obj )
          ).
        ENDIF.
        io_s3->deletebucket( iv_bucket = iv_bucket ).
      CATCH /aws1/cx_s3_nosuchbucket INTO DATA(lo_ex).
      CATCH /aws1/cx_s3_clientexc INTO DATA(lo_ex2).
        IF lo_ex2->av_err_code = 'InvalidBucketName'.
          " do nothing
        ELSE.
          RAISE EXCEPTION lo_ex2.
        ENDIF.
    ENDTRY.
  endmethod.


  method CREATE_BUCKET.
    " determine our region from our session
    DATA(lv_region) = CONV /aws1/s3_bucketlocationcnstrnt( io_session->get_region( ) ).
    DATA lo_constraint TYPE REF TO /aws1/cl_s3_createbucketconf.
    " When in the us-east-1 region, you must not specify a constraint
    " In all other regions, specify the region as the constraint
    IF lv_region = 'us-east-1'.
      CLEAR lo_constraint.
    ELSE.
      lo_constraint = NEW /aws1/cl_s3_createbucketconf( lv_region ).
    ENDIF.

    io_s3->createbucket(
        iv_bucket = iv_bucket
        io_createbucketconfiguration  = lo_constraint ).
  endmethod.


  METHOD get_random_string.
    CALL FUNCTION 'GENERAL_GET_RANDOM_STRING'
      EXPORTING
        number_chars  = 10
      IMPORTING
        random_string = ov_str.
  ENDMETHOD.
ENDCLASS.
