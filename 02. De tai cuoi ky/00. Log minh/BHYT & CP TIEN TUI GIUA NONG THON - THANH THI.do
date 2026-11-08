* ==============================================================================
* FILE: TVSEP_Panel_Analysis_Final.do
* DATA: VHLSS 2020
* MỤC TIÊU: Đánh giá hiệu ứng bảo vệ của BHYT đối với người cao tuổi trên 45
* ==============================================================================

*-------------------------------------------------------------------------------
* THIẾT LẬP MÔI TRƯỜNG LÀM VIỆC
*-------------------------------------------------------------------------------
clear all
set more off
set linesize 120
capture log close
log using "bhyt_oop_2020.log", replace text

* Đặt thư mục làm việc (Hãy sửa lại đường dẫn này theo máy của bạn)
local dir `c(pwd)'
cd "`dir'"
use "ktskdata.dta", clear

* ==============================================================================
sum lnoop hi gender age marital employed edu region nopeople noinpatient lnincome tdvmnpb btb tn dnb dbscl facilityused

tab hi
tab gender
tab marital
tab employed
tab facilityused

tab hi, missing

* ==============================================================================

tobit lnoop hi gender age marital employed edu region nopeople noinpatient lnincome tdvmnpb btb tn dnb dbscl facilityused ,ll(0) vce(cluster idho)

reg lnoop gender age marital hi employed edu region nopeople noinpatient lnincome tdvmnpb btb tn dnb dbscl facilityused , vce(cluster idho)

probit hi gender age marital employed edu region nopeople noinpatient lnincome tdvmnpb btb tn dnb dbscl facilityused sick pct_hi_commune , vce(cluster idho)

predict xb, xb

gen gen_res = cond(hi == 1, normalden(xb)/normal(xb), -normalden(xb)/(1-normal(xb)))

tobit lnoop hi gender age marital employed edu region nopeople noinpatient lnincome tdvmnpb btb tn dnb dbscl facilityused gen_res, ll(0) vce(cluster idho)
	
* ==============================================================================
* KẾT THÚC
********************************************************************************
log close