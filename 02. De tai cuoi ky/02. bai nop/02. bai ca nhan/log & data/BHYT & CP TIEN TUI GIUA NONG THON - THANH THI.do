********************************************************************************
* FILE NAME :  bhyt_oop_vhlss2024_Final.do
* PROJECT   :  Impact of Health Insurance on OOP (Dual Effect Analysis)
* AUTHOR    :  Truong Nhat Duy
* DATA      :  VHLSS 2024 + TVSEP 2007 -2024 
********************************************************************************

*-------------------------------------------------------------------------------
* THIẾT LẬP MÔI TRƯỜNG LÀM VIỆC
*-------------------------------------------------------------------------------
clear all
set more off
set linesize 120
capture log close
log using "bhyt_oop_2024_Final.log", replace text

local dir `c(pwd)'
cd "`dir'"

********************************************************************************
*  VHLSS 2024
********************************************************************************
use "VHLSS24_Master_Analysis.dta", clear
svyset [pw=wt9], strata(tinh) psu(diaban)
global X "ln_INC AGE_HEAD SEX_HEAD HH_SIZE" // Chỉ còn biến nhân khẩu học

capture which estout
if _rc cap ssc install estout
capture which coefplot
if _rc cap ssc install coefplot

********************************************************************************
* THỐNG KÊ MÔ TẢ NÂNG CAO VÀ ĐỒ THỊ TRỰC QUAN CẤU TRÚC CHI PHÍ
********************************************************************************
tabstat OOP_HH OOP_INPATIENT OOP_OUTPATIENT ln_INC AGE_HEAD SEX_HEAD HH_SIZE hh_vuot_tuyen [aw=wt9], ///
    by(INS_DUMMY) statistics(mean sd n) format(%9.3f) columns(statistics)
display "--------------------------------------------------------"

* 1. Xuất bảng Thống kê mô tả chia theo nhóm BHYT (Insured vs Uninsured)
capture window drop _all
quietly estpost tabstat OOP_HH OOP_INPATIENT OOP_OUTPATIENT ln_INC AGE_HEAD SEX_HEAD HH_SIZE hh_vuot_tuyen [aw=wt9], ///
    by(INS_DUMMY) statistics(mean sd) columns(statistics) listwise

esttab, ///
    main(mean %6.3f) aux(sd %6.3f) nostar unstack nonote nomtitle nonumber label ///
    title("XEM TRUOC: Table 1b Baseline Characteristics") ///
    eqlabels("Uninsured" "Insured" "Total")

esttab using "$tablepath\Table1b_Summary_by_Ins.tex", replace ///
    main(mean %6.3f) aux(sd %6.3f) nostar unstack nonote nomtitle nonumber label ///
    title("Table 1b: Baseline Characteristics by Health Insurance Status") ///
    eqlabels("Uninsured" "Insured" "Total")

* 1. Biểu đồ Pie thể hiện tỷ lệ BHYT (Tổng quan mẫu)

graph pie, over(INS_DUMMY) ///
    plabel(_all percent, format(%2.1f) size(small) color(white)) ///
    title("Figure 1a: Health Insurance Coverage", size(medium) color(black)) ///
    subtitle("Proportion of Households in VHLSS 2024", size(small) color(gs8)) ///
    legend(order(1 "Uninsured" 2 "Insured") position(6) rows(1) region(lcolor(white))) ///
    pie(1, color(maroon*0.8)) pie(2, color(navy*0.8) explode) ///
    graphregion(color(white)) ///
    saving("$figpath/Figure1a_Pie_BHYT.gph", replace)

graph export "$figpath/Figure1a_Pie_BHYT.png", as(png) replace width(3000)
	
* Vẽ đồ thị Stacked Bar
preserve
collapse (mean) OOP_INPATIENT OOP_OUTPATIENT [aw=wt9], by(RURAL hh_vuot_tuyen)

* Tạo nhãn 
label define rural_lbl 0 "Urban" 1 "Rural"
label values RURAL rural_lbl
label define bypass_lbl 0 "Primary Care" 1 "Bypassed"
label values hh_vuot_tuyen bypass_lbl

graph bar OOP_INPATIENT OOP_OUTPATIENT, ///
    over(hh_vuot_tuyen) over(RURAL) stack ///
    ytitle("Mean OOP Expenditure (Million VND)") ///
    legend(order(1 "Inpatient OOP" 2 "Outpatient OOP") position(6) rows(1)) ///
    title("Figure 1b: Composition of OOP Expenditures", color(black) size(medium)) ///
    subtitle("By Region and Bypassing Behavior", color(gs5) size(small)) ///
    scheme(s1mono) bar(1, color(maroon)) bar(2, color(navy))
graph export "$figpath\Figure1b_StackedBar_OOP.png", as(png) replace width(2000)
restore

* 3. Vẽ Boxplot: 
graph box ln_OOP, ///
    over(hh_vuot_tuyen, relabel(1 "Primary Care" 2 "Bypassed")) ///
    over(INS_DUMMY, relabel(1 "Uninsured" 2 "Insured")) ///
    ytitle("Log of Total OOP Expenditure") ///
    title("Figure 1c: Distribution of Medical Costs", color(black) size(medium)) ///
    subtitle("Highlighting Outlier Tail Risks", color(gs5) size(small)) ///
    scheme(s1mono) marker(1, msymbol(oh) msize(vsmall) mcolor(gs10)) ///
    box(1, color(black))
graph export "$figpath\Figure1c_Boxplot_Bypass.png", as(png) replace width(2000)

* 4. Vẽ Kernel Density: 
twoway (kdensity ln_OOP if INS_DUMMY == 1, lcolor(navy) lwidth(medium) lpattern(solid)) ///
       (kdensity ln_OOP if INS_DUMMY == 0, lcolor(maroon) lwidth(medium) lpattern(dash)), ///
    title("Figure 2: Distribution of Log(OOP) by Insurance Status", size(medium)) ///
    subtitle("Kernel Density Estimates", size(small) color(gs8)) ///
    xtitle("Logarithm of OOP Expenditure") ytitle("Density") ///
    legend(order(1 "Insured" 2 "Uninsured") position(6) rows(1) region(lcolor(white))) ///
    scheme(s1mono)
graph export "$figpath\Figure2_KernelDensity_INS.png", as(png) replace width(2000)

********************************************************************************
* BƯỚC: MÔ HÌNH IV-2SLS VỚI PHÂN RÃ CHI PHÍ (DUAL EFFECT ANALYSIS)
********************************************************************************

* 1. Mô hình Tổng chi phí OOP (Total)
quietly ivregress 2sls ln_OOP RURAL hh_vuot_tuyen rural_vuot_exo $X i.tinh ///
    (INS_DUMMY ins_rural ins_vuot ins_rural_vuot = IV_COMMUNE iv_rural iv_vuot iv_rural_vuot) ///
    [pw=wt9], vce(cluster tinh)
estimates store iv_total

* 2. Mô hình Chi phí Nội trú (Inpatient - Thảm họa)
quietly ivregress 2sls ln_OOP_in RURAL hh_vuot_tuyen rural_vuot_exo $X i.tinh ///
    (INS_DUMMY ins_rural ins_vuot ins_rural_vuot = IV_COMMUNE iv_rural iv_vuot iv_rural_vuot) ///
    [pw=wt9], vce(cluster tinh)
estimates store iv_inpatient

* 3. Mô hình Chi phí Ngoại trú (Outpatient - Khám thường)
quietly ivregress 2sls ln_OOP_out RURAL hh_vuot_tuyen rural_vuot_exo $X i.tinh ///
    (INS_DUMMY ins_rural ins_vuot ins_rural_vuot = IV_COMMUNE iv_rural iv_vuot iv_rural_vuot) ///
    [pw=wt9], vce(cluster tinh)
estimates store iv_outpatient

* Xuất bảng phân rã OOP 
esttab iv_total iv_inpatient iv_outpatient using "$tablepath\Dual_Effect_OOP.tex", replace ///
    title("Table: The Dual Effect of Health Insurance on Decomposed OOP Expenditures") ///
    mtitles("Total OOP" "Inpatient OOP" "Outpatient OOP") ///
    keep(INS_DUMMY RURAL hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot) ///
    coeflabels(INS_DUMMY "Health Insurance" ///
               ins_rural_vuot "Insured x Rural x Bypassed") ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    indicate("Demographic Controls = ln_INC" "Province FE = *tinh")

********************************************************************************
* BƯỚC: TRỰC QUAN HÓA (VISUALIZATION)
********************************************************************************
* 1. Forest Plot từ mô hình Tổng 
estimates restore iv_total
coefplot, ///
    keep(INS_DUMMY ins_rural ins_vuot ins_rural_vuot RURAL hh_vuot_tuyen rural_vuot_exo) ///
    xline(0, lpattern(dash) lcolor(red)) ///
    title("Figure 1: Coefficient Estimates of Health Insurance and Interactions", color(black)) ///
    xtitle("Effect on Log Out-of-Pocket Expenditure (ln_OOP)") ///
    msymbol(D) mcolor(navy) scheme(s1mono) grid(none)
graph export "$figpath\Figure1_ForestPlot.png", as(png) replace width(2000)

* 2. Kernel Density Plot 
twoway (kdensity ln_OOP if INS_DUMMY == 1, color(navy) lwidth(medthick)) ///
       (kdensity ln_OOP if INS_DUMMY == 0, color(maroon) lpattern(dash) lwidth(medthick)), ///
       xtitle("Log Out-of-Pocket Expenditure (ln_OOP)") ///
       legend(order(1 "Insured" 2 "Uninsured") position(6) rows(1)) ///
       scheme(s1mono)
graph export "$figpath\Figure2_Kernel_Density.png", as(png) replace width(2000)

* ==============================================================================
* XUẤT TỔNG HỢP KẾT QUẢ 
* ==============================================================================

capture log close
log using "Ket_qua.txt", replace text

display "====================================================================="
display "1. THỐNG KÊ MÔ TẢ CÁC BIẾN (SUMMARY STATISTICS)"
display "====================================================================="

* Thống kê có trọng số mẫu 
sum OOP_HH OOP_INPATIENT OOP_OUTPATIENT INS_DUMMY RURAL hh_vuot_tuyen ///
    ln_INC AGE_HEAD SEX_HEAD HH_SIZE IV_COMMUNE [aw=wt9]

display " "
display "====================================================================="
display "2. KẾT QUẢ MÔ HÌNH IV-2SLS (TỔNG OOP, NỘI TRÚ, NGOẠI TRÚ)"
display "====================================================================="

* In bảng kết quả IV-2SLS 
esttab iv_total iv_inpatient iv_outpatient, ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(INS_DUMMY RURAL hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot) ///
    coeflabels(INS_DUMMY "BHYT (Base)" ///
               RURAL "Nong_thon" ///
               hh_vuot_tuyen "Vuot_tuyen" ///
               ins_rural "BHYT x Nong_thon" ///
               ins_vuot "BHYT x Vuot_tuyen" ///
               ins_rural_vuot "BHYT x Nong_thon x Vuot_tuyen") ///
    mtitles("Total_OOP" "Inpatient_OOP" "Outpatient_OOP") ///
    title("Bang 2: Hieu ung kep cua BHYT (IV-2SLS)")

display " "
display "====================================================================="
display "3. KẾT QUẢ GHÉP CẶP ĐIỂM XU HƯỚNG (PSM)"
display "====================================================================="

* Gọi lại mô hình PSM đã loại bỏ các quan sát vi phạm
teffects psmatch (ln_OOP) ///
    (INS_DUMMY RURAL hh_vuot_tuyen ln_INC AGE_HEAD SEX_HEAD HH_SIZE i.tinh, probit) ///
    if vi_pham_overlap == 0, nneighbor(1) vce(robust)

display " "
display "====================================================================="
display "4. KẾT QUẢ HỒI QUY PHÂN VỊ ĐỒNG THỜI (SQREG)"
display "====================================================================="
* Lệnh hồi quy phân vị (chạy lại nhanh gọn để in kết quả)
set seed 12345 
sqreg ln_OOP INS_DUMMY RURAL hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot ///
      ln_INC AGE_HEAD SEX_HEAD HH_SIZE, q(.25 .50 .75 .90) reps(100)

* ==============================================================================
* CHẠY LẠI MÔ HÌNH 
* ==============================================================================

* Mô hình Nội trú
quietly ivregress 2sls ln_OOP_in RURAL hh_vuot_tuyen rural_vuot_exo $X i.tinh ///
    (INS_DUMMY ins_rural ins_vuot ins_rural_vuot = IV_COMMUNE iv_rural iv_vuot iv_rural_vuot) ///
    [pw=wt9], vce(cluster tinh)
estimates store iv_inpatient

* Mô hình Ngoại trú
quietly ivregress 2sls ln_OOP_out RURAL hh_vuot_tuyen rural_vuot_exo $X i.tinh ///
    (INS_DUMMY ins_rural ins_vuot ins_rural_vuot = IV_COMMUNE iv_rural iv_vuot iv_rural_vuot) ///
    [pw=wt9], vce(cluster tinh)
estimates store iv_outpatient

* In lại bảng kết quả ra màn hình để kiểm tra
esttab iv_total iv_inpatient iv_outpatient, ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(INS_DUMMY RURAL hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot) ///
    coeflabels(INS_DUMMY "BHYT (Base)" ///
               ins_rural "BHYT x Nong_thon" ///
               ins_vuot "BHYT x Vuot_tuyen" ///
               ins_rural_vuot "BHYT x Nong x Vuot_tuyen") ///
    mtitles("Total_OOP" "Inpatient_OOP" "Outpatient_OOP") ///
    title("BANG KET QUA DA FIX LOI MAT QUAN SAT (N=46995)")


* Xuất bảng so sánh 3 mô hình vào thư mục Tables
esttab iv_total iv_inpatient iv_outpatient using "$tablepath\Table2_Decomposed_OOP.tex", replace ///
    title("Table 2: The Dual Effect of Health Insurance on Decomposed OOP Expenditures") ///
    mtitles("Total OOP" "Inpatient OOP" "Outpatient OOP") ///
    keep(INS_DUMMY RURAL hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot) ///
    coeflabels(INS_DUMMY "Health Insurance (HI)" ///
               RURAL "Rural Area" ///
               hh_vuot_tuyen "Bypassed Primary Care" ///
               ins_rural "HI $\times$ Rural" ///
               ins_vuot "HI $\times$ Bypassed" ///
               ins_rural_vuot "HI $\times$ Rural $\times$ Bypassed") ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    indicate("Demographic Controls = ln_INC" "Province FE = *tinh") ///
    addnotes("Robust standard errors clustered at the province level in parentheses.")

* Vẽ đồ thị so sánh hệ số của 3 mô hình trên cùng 1 trục
coefplot (iv_total, label("Total OOP") msymbol(S) mcolor(black)) ///
         (iv_inpatient, label("Inpatient OOP (Severe)") msymbol(D) mcolor(maroon)) ///
         (iv_outpatient, label("Outpatient OOP (Mild)") msymbol(T) mcolor(navy)), ///
    keep(INS_DUMMY ins_rural ins_vuot ins_rural_vuot) ///
    coeflabels(INS_DUMMY = "Health Insurance (HI)" ///
               ins_rural = "HI x Rural" ///
               ins_vuot = "HI x Bypassed" ///
               ins_rural_vuot = "HI x Rural x Bypassed") ///
    xline(0, lpattern(dash) lcolor(gs10)) ///
    title("Figure 3: Heterogeneous Effects on Decomposed OOP Expenditures", size(medsmall) color(black)) ///
    xtitle("Effect Size on Log(OOP)", size(small)) ///
    legend(position(6) rows(1)) ///
    ciopts(lwidth(thin)) ///
    scheme(s1mono) grid(none) offset(0.15)
graph export "$figpath\Figure3_Combined_ForestPlot.png", as(png) replace width(2000)

********************************************************************************
* KIỂM TRA ĐỘ VỮNG (ROBUSTNESS CHECKS)
********************************************************************************
* 1. PSM (Đã loại bỏ quan sát vi phạm Overlap)
capture drop vi_pham_overlap 
capture teffects psmatch (ln_OOP) ///
    (INS_DUMMY RURAL hh_vuot_tuyen $X i.tinh, probit), ///
    nneighbor(1) vce(robust) osample(vi_pham_overlap)

teffects psmatch (ln_OOP) ///
    (INS_DUMMY RURAL hh_vuot_tuyen $X i.tinh, probit) ///
    if vi_pham_overlap == 0, nneighbor(1) vce(robust)

tebalance density ln_INC
* Xuất Balance Plot vào thư mục FIGURES
graph export "$figpath\Figure3_Balance_Plot.png", as(png) replace width(2000)

* 2. SQREG (Không Fixed Effects tỉnh để tránh lỗi hội tụ)
set seed 12345 
sqreg ln_OOP INS_DUMMY RURAL hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot ///
      $X, q(.25 .50 .75 .90) reps(100)

* ==============================================================================
* KIỂM ĐỊNH 
* ==============================================================================
ssc install ivreg2, replace
ssc install ranktest, replace

* ------------------------------------------------------------------------------
* 1. KIỂM ĐỊNH ĐA CỘNG TUYẾN (MULTICOLLINEARITY)
* ------------------------------------------------------------------------------
display ">>> 1. KIEM DINH VIF CHO MO HINH CO SO <<<"
quietly reg ln_OOP INS_DUMMY RURAL hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot ln_INC $X i.tinh [pw=wt9]

vif

* ------------------------------------------------------------------------------
* 2. MA TRAN TUONG QUAN (CORRELATION MATRIX)
* ------------------------------------------------------------------------------
display ">>> MA TRAN TUONG QUAN CHO CAC BIEN CHINH TONG MO HINH <<<"


pwcorr ln_OOP INS_DUMMY RURAL hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot ln_INC AGE_HEAD SEX_HEAD HH_SIZE, sig star(0.05)


corr ln_OOP INS_DUMMY RURAL hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot ln_INC AGE_HEAD SEX_HEAD HH_SIZE [aw=wt9]

* ------------------------------------------------------------------------------
* 2. KIỂM ĐỊNH MÔ HÌNH BIẾN CÔNG CỤ (IV-2SLS)
* ------------------------------------------------------------------------------

ivreg2 ln_OOP RURAL hh_vuot_tuyen rural_vuot_exo $X i.tinh ///
    (INS_DUMMY ins_rural ins_vuot ins_rural_vuot = IV_COMMUNE iv_rural iv_vuot iv_rural_vuot), ///
    cluster(tinh) endog(INS_DUMMY ins_rural ins_vuot ins_rural_vuot) first

ivregress 2sls ln_OOP ln_INC AGE_HEAD SEX_HEAD HH_SIZE (INS_DUMMY ins_rural ins_vuot ins_rural_vuot = IV_COMMUNE iv_rural iv_vuot iv_rural_vuot)

ssc install ivhettest, replace

* kiểm định Pagan-Hall cho mô hình IV
ivhettest, ph
* hệ số tương quan nội cụm (ICC) theo biến tỉnh
loneway ln_OOP tinh

* ------------------------------------------------------------------------------
* 2. KIỂM ĐỊNH MÔ HÌNH BIẾN CÔNG CỤ (IV-2SLS) & ANDERSON-RUBIN TEST
* ------------------------------------------------------------------------------
* Cài đặt các gói cần thiết (avar và weakiv) nếu chưa có
capture which avar
if _rc cap ssc install avar, replace

capture which weakiv
if _rc cap ssc install weakiv, replace

* Chạy mô hình ivreg2 với tùy chọn partial(i.tinh) để sửa lỗi Full Rank
ivreg2 ln_OOP RURAL hh_vuot_tuyen rural_vuot_exo $X i.tinh ///
    (INS_DUMMY ins_rural ins_vuot ins_rural_vuot = IV_COMMUNE iv_rural iv_vuot iv_rural_vuot), ///
    cluster(tinh) partial(i.tinh) endog(INS_DUMMY ins_rural ins_vuot ins_rural_vuot) first

* KIỂM ĐỊNH ANDERSON-RUBIN (AR TEST) CHO BIẾN CÔNG CỤ YẾU
display ">>> KIEM DINH ANDERSON-RUBIN (WEAK-INSTRUMENT ROBUST INFERENCE) <<<"
weakiv test (INS_DUMMY ins_rural ins_vuot ins_rural_vuot)

* Nếu bạn chỉ muốn focus test sự vững chắc của riêng hệ số tương tác 3 chiều:
weakiv test (ins_rural_vuot)

* ------------------------------------------------------------------------------
* BƯỚC 1: ƯỚC LƯỢNG MÔ HÌNH BẰNG IVREGRESS (Thay cho ivreg2 để tăng tính tương thích)
* ------------------------------------------------------------------------------
* Lưu ý: Ta đưa i.tinh vào để kiểm soát đặc điểm địa phương.
* VCE(cluster tinh) tương đương với cluster(tinh) trong ivreg2.

ivregress 2sls ln_OOP RURAL hh_vuot_tuyen rural_vuot_exo $X i.tinh ///
    (INS_DUMMY ins_rural ins_vuot ins_rural_vuot = IV_COMMUNE iv_rural iv_vuot iv_rural_vuot), ///
    vce(cluster tinh)

* ------------------------------------------------------------------------------
* BƯỚC 2: KIỂM ĐỊNH SAU ƯỚC LƯỢNG (POST-ESTIMATION)
* ------------------------------------------------------------------------------

* 1. Kiểm tra bộ nhớ (Nếu hiện ra bảng danh sách là lệnh trên đã thành công)
ereturn list

* 2. Chạy kiểm định Weak-instrument-robust (Anderson-Rubin)
* Lệnh weakiv hỗ trợ ivregress cực tốt, sẽ không còn báo lỗi "unsupported"
weakiv test (INS_DUMMY ins_rural ins_vuot ins_rural_vuot)

* 3. Nếu bạn chỉ muốn kiểm định riêng cho biến tương tác quan trọng nhất:
weakiv test (ins_rural_vuot)

* ------------------------------------------------------------------------------
* BƯỚC 3: XEM KẾT QUẢ FIRST-STAGE (Nếu cần)
* ------------------------------------------------------------------------------
* Vì ivregress không hiện first-stage mặc định như ivreg2, bạn dùng lệnh:
estat firststage
* ------------------------------------------------------------------------------
* 3. KIỂM ĐỊNH MÔ HÌNH PHÂN VỊ (SQREG)
* ------------------------------------------------------------------------------

* mô hình SQREG
quietly sqreg ln_OOP INS_DUMMY hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot ln_INC $X i.tinh, ///
    quantiles(.25 .50 .75 .90) reps(100)

* Kiểm định Wald: 
test [q25]INS_DUMMY = [q50]INS_DUMMY = [q75]INS_DUMMY = [q90]INS_DUMMY

* ------------------------------------------------------------------------------
* 4. KIỂM ĐỊNH GHÉP CẶP ĐIỂM XU HƯỚNG (PSM)
* ------------------------------------------------------------------------------
quietly teffects psmatch (ln_OOP) (INS_DUMMY $X, probit), nn(1) vce(iid)

* Bảng kiểm tra sự cân bằng của các hiệp biến sau khi ghép cặp
tebalance summarize

* Vẽ và xuất đồ thị Vùng hỗ trợ chung (Common Support)
tebalance density
graph export "Common_Support_PSM.png", replace

* ------------------------------------------------------------------------------
* Phân tích TVSEP
* ------------------------------------------------------------------------------
use "TVSEP_Panel_Clean_CPI_Labelled_Final", clear

* ------------------------------------------------------------------------------
* THỐNG KÊ MÔ TẢ VÀ ĐỒ THỊ XU HƯỚNG TỔNG QUAN
* ------------------------------------------------------------------------------

preserve
collapse (mean) mean_ln_OOP=ln_OOP_real, by(wave country_code INS_dummy)
twoway (line mean_ln_OOP wave if country_code=="VNM" & INS_dummy==0, lcolor(maroon) lpattern(dash) lwidth(medthick)) ///
       (line mean_ln_OOP wave if country_code=="VNM" & INS_dummy==1, lcolor(maroon) lpattern(solid) lwidth(medthick) msymbol(S)) ///
       (line mean_ln_OOP wave if country_code=="THA" & INS_dummy==0, lcolor(navy) lpattern(dash) lwidth(medthick)) ///
       (line mean_ln_OOP wave if country_code=="THA" & INS_dummy==1, lcolor(navy) lpattern(solid) lwidth(medthick) msymbol(D)), ///
       legend(order(1 "VN - Không BHYT" 2 "VN - Có BHYT" 3 "Thái - Không BHYT" 4 "Thái - Có BHYT") position(6) rows(2)) ///
       title("Xu hướng chi phí y tế tiền túi trung bình (2007-2024)") ///
       ytitle("Mean Log(OOP PPP USD Real)") xtitle("Năm khảo sát (Wave)") ///
       name(gtrend_overall, replace)
graph export "${figdir}\oop_trend_overall.png", replace as(png) width(2000)
restore

* ------------------------------------------------------------------------------
* PHẦN 3: MÔ HÌNH HỒI QUY CHÍNH (BASELINE, MECHANISM & Q90)
* ------------------------------------------------------------------------------

* Mô hình 1: Tác động tổng thể
reghdfe ln_OOP_real INS_dummy INS_x_THAI $X, ///
    absorb(id_panel wave) vce(cluster village)
estimates store m1_base

* Mô hình 2: Cơ chế vượt tuyến
reghdfe ln_OOP_real INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI $X, ///
    absorb(id_panel wave) vce(cluster village)
estimates store m2_bypass

* Mô hình 3: Thảm họa y tế (Phân vị 90th)
sqreg ln_OOP_real INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI ///
      $X i.wave, q(.90)

estimates store m3_q90

* Xuất bảng
esttab m1_base m2_bypass m3_q90 using "Table_Main_Results.rtf", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI Health_shock) ///
    coeflabels(INS_dummy "BHYT (Chung/VN)" INS_x_THAI "BHYT x Thái Lan" ///
               BYPASSED "Vượt tuyến (Chung)" BYPASS_x_THAI "Vượt tuyến x Thái Lan") ///
    mtitles("TWFE (Mean)" "Mechanism (Mean)" "SQREG (Q90 - Thảm họa)")
	
* 3 quantile:
qreg ln_OOP_real INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI $X, q(.50)
qreg ln_OOP_real INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI $X, q(.75)
qreg ln_OOP_real INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI $X, q(.90)

* tạo bảng:
Table: Quantile Regression Results for OOP Expenditure

* ------------------------------------------------------------------------------
* PHẦN 4: PHÂN TÍCH ĐỘNG (DYNAMIC ANALYSIS) - SỰ THAY ĐỔI THEO THỜI GIAN
* ------------------------------------------------------------------------------

* Chạy mô hình Fixed Effects với tương tác 3 chiều (Wave x INS x Country)
reghdfe ln_OOP_real i.INS_dummy##i.THAI_dummy##i.wave $X, ///
    absorb(id_panel) vce(cluster village)

* Tính toán Tác động Biên (Marginal Effects) của BHYT cho từng nước qua các năm
* -------------------------------
* Việt Nam (THAI_dummy==0)
* -------------------------------
preserve
keep if THAI_dummy==0
margins, dydx(INS_dummy) at(wave=(2008 2010 2011 2013 2016 2017))
marginsplot, x(wave) ///
    plotopts(lcolor(maroon) mcolor(maroon) msymbol(S)) ///
    ciopts(fcolor(maroon%20) lcolor(none)) ///
    name(vn_plot, replace) ///
    title("Tác động BHYT - Việt Nam")
restore

* -------------------------------
* Thái Lan (THAI_dummy==1)
* -------------------------------
preserve
keep if THAI_dummy==1
margins, dydx(INS_dummy) at(wave=(2008 2010 2011 2013 2016 2017))
marginsplot, x(wave) ///
    plotopts(lcolor(navy) mcolor(navy) msymbol(D)) ///
    ciopts(fcolor(navy%20) lcolor(none)) ///
    name(th_plot, replace) ///
    title("Tác động BHYT - Thái Lan")
restore

* -------------------------------
* Ghép hai đồ thị thành Event-Study chung
* -------------------------------
* Vietnam
preserve
keep if THAI_dummy==0
margins, dydx(INS_dummy) at(wave=(2008 2010 2011 2013 2016 2017))
marginsplot, x(wave) ///
    plotopts(lcolor(maroon) mcolor(maroon) msymbol(S)) ///
    ciopts(fcolor(maroon%20) lcolor(none)) ///
    name(vn_plot, replace) ///
    title("VN") ///
    ytitle("Marginal Effect") ///
    xtitle("Wave")
restore

* Thailand
preserve
keep if THAI_dummy==1
margins, dydx(INS_dummy) at(wave=(2008 2010 2011 2013 2016 2017))
marginsplot, x(wave) ///
    plotopts(lcolor(navy) mcolor(navy) msymbol(D)) ///
    ciopts(fcolor(navy%20) lcolor(none)) ///
    name(th_plot, replace) ///
    title("THA") ///
    ytitle("Marginal Effect") ///
    xtitle("Wave")
restore

* Combine plots
graph combine vn_plot th_plot, ///
    title("HI Impact on OOP (Dynamic)") ///
    name(g_dynamic_effect, replace)

graph export "${figdir}\g_dynamic_effect.png", replace as(png) width(2000)

 
* KẾT THÚC
********************************************************************************
log close