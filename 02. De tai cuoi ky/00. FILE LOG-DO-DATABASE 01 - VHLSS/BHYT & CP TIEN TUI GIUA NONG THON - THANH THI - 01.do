********************************************************************************
* FILE NAME :  bhyt_oop_vhlss2024_Final.do
* PROJECT   :  Impact of Health Insurance on OOP (Dual Effect Analysis)
* AUTHOR    :  Truong Nhat Duy
* DATA      :  VHLSS 2024
* UPDATES   :  - Decomposed OOP (Inpatient vs Outpatient)
* - Removed Supply-side controls (due to data limitations)
* - Optimized paths for Tables and Figures for LaTeX
********************************************************************************

*-------------------------------------------------------------------------------
* THIẾT LẬP MÔI TRƯỜNG LÀM VIỆC
*-------------------------------------------------------------------------------
clear all
set more off
set linesize 120
capture log close
log using "bhyt_oop_2024_Final.log", replace text

* Đặt thư mục làm việc (Hãy sửa lại đường dẫn này theo máy của bạn)
local dir `c(pwd)'
cd "`dir'"

********************************************************************************
* THIẾT LẬP ĐƯỜNG DẪN XUẤT KẾT QUẢ CHO LATEX
********************************************************************************

* 1. Đường dẫn xuất Bảng (Tables - file .tex)
global tablepath "D:\01. HOC HANH\13. THAC SI UEH\05. MON HOC\HOC KY 2\04. KINH TE SUC KHOE\04. De tai Bao hiem y te\02. De tai cuoi ky\01. Bai viet LAtex\tables"
cap mkdir "$tablepath"

* 2. Đường dẫn xuất Hình ảnh (Figures - file .png)
global figpath "D:\01. HOC HANH\13. THAC SI UEH\05. MON HOC\HOC KY 2\04. KINH TE SUC KHOE\04. De tai Bao hiem y te\02. De tai cuoi ky\01. Bai viet LAtex\figures"
cap mkdir "$figpath"

********************************************************************************
* BƯỚC 1: LÀM SẠCH VÀ CHUẨN BỊ DỮ LIỆU TỪNG FILE
********************************************************************************

display ">>> BƯỚC 1: XỬ LÝ DỮ LIỆU HỘ GIA ĐÌNH & PHÂN RÃ OOP <<<"
* --- 1. FILE HỘ GIA ĐÌNH ---
use "Ho_ThongTinHo.dta", clear
rename *, lower
rename idho IDHO

* Biến Nông thôn (1=Nông thôn, 0=Thành thị)
gen RURAL = (ttnt == 2) 

* Thu nhập bình quân (Triệu đồng) và Log(Thu nhập)
gen INC_HH_MIL = tongthu / 1000 
gen INC_PC_MIL = INC_HH_MIL / tsnguoi
gen ln_INC = ln(INC_PC_MIL + 1)

* Tổng chi OOP hộ (đơn vị: triệu đồng) 
gen OOP_HH = m3ct / 1000

* PHÂN RÃ CHI PHÍ OOP (VHLSS có biến nội trú (m3ct2) / ngoại trú (m3ct1) ở cấp hộ)
capture gen OOP_INPATIENT = m3ct2 / 1000
capture gen OOP_OUTPATIENT = m3ct1 / 1000

keep IDHO tinh huyen xa diaban RURAL INC_PC_MIL ln_INC tsnguoi OOP_HH OOP_INPATIENT OOP_OUTPATIENT
save "b1_household.dta", replace

* --- 2. FILE NHÂN KHẨU & BHYT ---
use "Ho_ThanhVien.dta", clear
rename *, lower
rename idho IDHO

gen IS_HEAD = (m1a_c3 == 1)
gen AGE_VAL = m1a_c5 if IS_HEAD == 1
gen SEX_VAL = m1a_c2 if IS_HEAD == 1

bys IDHO: egen AGE_HEAD = max(AGE_VAL)
bys IDHO: egen SEX_HEAD = max(SEX_VAL)
bys IDHO: gen HH_SIZE = _N

gen HAS_BHYT = (m3a_c7 == 1)
bys IDHO: egen BHYT_RATE = mean(HAS_BHYT)

bys IDHO: keep if _n == 1
keep IDHO AGE_HEAD SEX_HEAD HH_SIZE BHYT_RATE
save "b2_demog.dta", replace

* --- 3. FILE CHI PHÍ Y TẾ VÀ HÀNH VI KHÁM BỆNH ---
use "Ho_Muc3A.dta", clear
rename *, lower
rename idho IDHO

gen tuyen = .
replace tuyen = 1 if inlist(m3a_c3ma,1,2,3)       // Xã/Huyện
replace tuyen = 2 if inlist(m3a_c3ma,4,5,6)       // Tỉnh/TW
replace tuyen = 3 if inlist(m3a_c3ma,7,8)         // Tư nhân
replace tuyen = 4 if inlist(m3a_c3ma,9,10,11,12,13) // Tự điều trị

gen vuot_tuyen_ind = inlist(tuyen,2,3)

bys IDHO: egen so_ca_kham = count(idtv)
bys IDHO: egen so_ca_vuot = total(vuot_tuyen_ind)
bys IDHO: egen hh_vuot_tuyen = max(vuot_tuyen_ind)
gen tyle_vuot = so_ca_vuot / so_ca_kham

bys IDHO: keep if _n == 1
keep IDHO hh_vuot_tuyen so_ca_kham so_ca_vuot tyle_vuot
save "b3_oop.dta", replace

********************************************************************************
* BƯỚC 2: GHÉP NỐI VÀ TẠO CÁC BIẾN KINH TẾ LƯỢNG (MERGE & FEATURE ENGINEERING)
********************************************************************************
display ">>> BƯỚC 2: GHÉP NỐI DỮ LIỆU VÀ TẠO BIẾN <<<"
use "b1_household.dta", clear
merge 1:1 IDHO using "b2_demog.dta", keep(3) nogen

* --- CHUẨN HÓA BIẾN GIỚI TÍNH (DUMMY TRAP FIX) ---
* Gốc: 1=Nam, 2=Nữ. Cần recode thành: 1=Nam, 0=Nữ
recode SEX_HEAD (2 = 0)
label define sex_lbl 1 "Nam" 0 "Nữ"
label values SEX_HEAD sex_lbl

* Ghép nối file hành vi khám bệnh (OOP)
merge 1:1 IDHO using "b3_oop.dta"

* Những hộ không có trong file b3 ( _merge == 1) là những hộ KHÔNG ĐI KHÁM BỆNH
replace hh_vuot_tuyen = 0 if _merge == 1
replace so_ca_kham = 0 if _merge == 1
replace so_ca_vuot = 0 if _merge == 1
replace tyle_vuot = 0 if _merge == 1
drop _merge

* Ghép trọng số
merge m:1 tinh huyen xa diaban using "weight2024_ver2.dta", keep(3) nogen

* --- TẠO BIẾN CÔNG CỤ & LOG ---
bys tinh huyen xa: egen sum_ins = total(BHYT_RATE)
bys tinh huyen xa: gen count_hh = _N
gen IV_COMMUNE = (sum_ins - BHYT_RATE) / (count_hh - 1)
replace IV_COMMUNE = BHYT_RATE if count_hh == 1 

gen INS_DUMMY = (BHYT_RATE > 0)

* --- FIX LỖI MISSING DROP-OUT CHO CHI PHÍ Y TẾ ---
* Nếu hộ không phát sinh chi phí, biến gốc bị missing (.). Phải ép về 0 trước khi tính Log.
replace OOP_HH = 0 if missing(OOP_HH)
replace OOP_INPATIENT = 0 if missing(OOP_INPATIENT)
replace OOP_OUTPATIENT = 0 if missing(OOP_OUTPATIENT)

gen ln_OOP = ln(OOP_HH + 1)
gen ln_OOP_in = ln(OOP_INPATIENT + 1)   // Phân rã Nội trú
gen ln_OOP_out = ln(OOP_OUTPATIENT + 1) // Phân rã Ngoại trú

* --- TẠO CÁC BIẾN TƯƠNG TÁC (INTERACTIONS) ---
gen rural_vuot_exo = RURAL * hh_vuot_tuyen
gen ins_rural = INS_DUMMY * RURAL
gen ins_vuot = INS_DUMMY * hh_vuot_tuyen
gen ins_rural_vuot = INS_DUMMY * RURAL * hh_vuot_tuyen 

gen iv_rural = IV_COMMUNE * RURAL
gen iv_vuot = IV_COMMUNE * hh_vuot_tuyen
gen iv_rural_vuot = IV_COMMUNE * RURAL * hh_vuot_tuyen

* --- LABELING ENGLISH FOR Q1 JOURNALS ---
label var ln_OOP "Log(Total OOP + 1)"
label var ln_OOP_in "Log(Inpatient OOP + 1)"
label var ln_OOP_out "Log(Outpatient OOP + 1)"
label var INS_DUMMY "Health Insurance"
label var RURAL "Rural Area"
label var hh_vuot_tuyen "Bypassed Primary Care"
label var ins_rural_vuot "Insurance x Rural x Bypassed"

save "VHLSS24_Master_Analysis.dta", replace

********************************************************************************
* BƯỚC 3: THIẾT LẬP TOÀN CỤC VÀ TRỌNG SỐ
********************************************************************************
svyset [pw=wt9], strata(tinh) psu(diaban)
global X "ln_INC AGE_HEAD SEX_HEAD HH_SIZE" // Chỉ còn biến nhân khẩu học

capture which estout
if _rc cap ssc install estout
capture which coefplot
if _rc cap ssc install coefplot

********************************************************************************
* THỐNG KÊ MÔ TẢ NÂNG CAO VÀ ĐỒ THỊ TRỰC QUAN CẤU TRÚC CHI PHÍ
********************************************************************************
display ">>> RUNNING ADVANCED DESCRIPTIVE STATISTICS <<<"

* --- BƯỚC CHECK 1: IN NHANH RA MÀN HÌNH ĐỂ KIỂM TRA N, MEAN, SD ---
* (Lệnh này in ra màn hình Stata mặc định để bạn xem trước số quan sát N xem có bị rớt mẫu không)
display "--- KIEM TRA NHANH SO LIEU TRONG STATA ---"
tabstat OOP_HH OOP_INPATIENT OOP_OUTPATIENT ln_INC AGE_HEAD SEX_HEAD HH_SIZE hh_vuot_tuyen [aw=wt9], ///
    by(INS_DUMMY) statistics(mean sd n) format(%9.3f) columns(statistics)
display "--------------------------------------------------------"

* 1. Xuất bảng Thống kê mô tả chia theo nhóm BHYT (Insured vs Uninsured)
* Sử dụng estpost để lưu trữ giá trị Mean và SD vào bộ nhớ tạm
capture window drop _all
quietly estpost tabstat OOP_HH OOP_INPATIENT OOP_OUTPATIENT ln_INC AGE_HEAD SEX_HEAD HH_SIZE hh_vuot_tuyen [aw=wt9], ///
    by(INS_DUMMY) statistics(mean sd) columns(statistics) listwise

* --- BƯỚC CHECK 2: IN BẢNG ĐỊNH DẠNG LATEX RA MÀN HÌNH ---
* (Lệnh esttab không có "using..." sẽ in y hệt cấu trúc bảng sẽ xuất ra file)
esttab, ///
    main(mean %6.3f) aux(sd %6.3f) nostar unstack nonote nomtitle nonumber label ///
    title("XEM TRUOC: Table 1b Baseline Characteristics") ///
    eqlabels("Uninsured" "Insured" "Total")

* --- BƯỚC 3: XUẤT KẾT QUẢ CHÍNH THỨC RA FILE LATEX ---
esttab using "$tablepath\Table1b_Summary_by_Ins.tex", replace ///
    main(mean %6.3f) aux(sd %6.3f) nostar unstack nonote nomtitle nonumber label ///
    title("Table 1b: Baseline Characteristics by Health Insurance Status") ///
    eqlabels("Uninsured" "Insured" "Total")

* 1. Biểu đồ Pie thể hiện tỷ lệ BHYT (Tổng quan mẫu)
* Sử dụng bảng màu chuyên nghiệp (pcolor) và tách mảng (explode) để tạo điểm nhấn
graph pie, over(INS_DUMMY) ///
    plabel(_all percent, format(%2.1f) size(small) color(white)) ///
    title("Figure 1a: Health Insurance Coverage", size(medium) color(black)) ///
    subtitle("Proportion of Households in VHLSS 2024", size(small) color(gs8)) ///
    legend(order(1 "Uninsured" 2 "Insured") position(6) rows(1) region(lcolor(white))) ///
    pie(1, color(maroon*0.8)) pie(2, color(navy*0.8) explode) ///
    graphregion(color(white)) ///
    saving("$figpath/Figure1a_Pie_BHYT.gph", replace)

* Xuất đồ thị ra định dạng PNG chất lượng cao (đúng tên file để tránh ghi đè)
graph export "$figpath/Figure1a_Pie_BHYT.png", as(png) replace width(3000)
	
* 2. Vẽ đồ thị Stacked Bar: Cấu trúc OOP (Nội trú vs Ngoại trú) theo Khu vực & Vượt tuyến
preserve
collapse (mean) OOP_INPATIENT OOP_OUTPATIENT [aw=wt9], by(RURAL hh_vuot_tuyen)

* Tạo nhãn tiếng Anh chuẩn học thuật cho đồ thị
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

* 3. Vẽ Boxplot: Phân phối Log(OOP) để thấy rõ các ca thảm họa (Outliers) ở phần đuôi
graph box ln_OOP, ///
    over(hh_vuot_tuyen, relabel(1 "Primary Care" 2 "Bypassed")) ///
    over(INS_DUMMY, relabel(1 "Uninsured" 2 "Insured")) ///
    ytitle("Log of Total OOP Expenditure") ///
    title("Figure 1c: Distribution of Medical Costs", color(black) size(medium)) ///
    subtitle("Highlighting Outlier Tail Risks", color(gs5) size(small)) ///
    scheme(s1mono) marker(1, msymbol(oh) msize(vsmall) mcolor(gs10)) ///
    box(1, color(black))
graph export "$figpath\Figure1c_Boxplot_Bypass.png", as(png) replace width(2000)

* 4. Vẽ Kernel Density: So sánh phân phối chi phí giữa nhóm có và không có BHYT
* Biểu đồ này giúp minh chứng cho việc tại sao cần dùng hồi quy phân vị (SQREG)
twoway (kdensity ln_OOP if INS_DUMMY == 1, lcolor(navy) lwidth(medium) lpattern(solid)) ///
       (kdensity ln_OOP if INS_DUMMY == 0, lcolor(maroon) lwidth(medium) lpattern(dash)), ///
    title("Figure 2: Distribution of Log(OOP) by Insurance Status", size(medium)) ///
    subtitle("Kernel Density Estimates", size(small) color(gs8)) ///
    xtitle("Logarithm of OOP Expenditure") ytitle("Density") ///
    legend(order(1 "Insured" 2 "Uninsured") position(6) rows(1) region(lcolor(white))) ///
    scheme(s1mono)
graph export "$figpath\Figure2_KernelDensity_INS.png", as(png) replace width(2000)

********************************************************************************
* BƯỚC 4: MÔ HÌNH IV-2SLS VỚI PHÂN RÃ CHI PHÍ (DUAL EFFECT ANALYSIS)
********************************************************************************
display ">>> RUNNING IV-2SLS DECOMPOSED MODELS <<<"

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

* Xuất bảng phân rã OOP vào thư mục TABLES
esttab iv_total iv_inpatient iv_outpatient using "$tablepath\Dual_Effect_OOP.tex", replace ///
    title("Table: The Dual Effect of Health Insurance on Decomposed OOP Expenditures") ///
    mtitles("Total OOP" "Inpatient OOP" "Outpatient OOP") ///
    keep(INS_DUMMY RURAL hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot) ///
    coeflabels(INS_DUMMY "Health Insurance" ///
               ins_rural_vuot "Insured x Rural x Bypassed") ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    indicate("Demographic Controls = ln_INC" "Province FE = *tinh")

********************************************************************************
* BƯỚC 5: TRỰC QUAN HÓA (VISUALIZATION FOR Q1)
********************************************************************************
* 1. Forest Plot từ mô hình Tổng (Xuất vào thư mục FIGURES)
estimates restore iv_total
coefplot, ///
    keep(INS_DUMMY ins_rural ins_vuot ins_rural_vuot RURAL hh_vuot_tuyen rural_vuot_exo) ///
    xline(0, lpattern(dash) lcolor(red)) ///
    title("Figure 1: Coefficient Estimates of Health Insurance and Interactions", color(black)) ///
    xtitle("Effect on Log Out-of-Pocket Expenditure (ln_OOP)") ///
    msymbol(D) mcolor(navy) scheme(s1mono) grid(none)
graph export "$figpath\Figure1_ForestPlot.png", as(png) replace width(2000)

* 2. Kernel Density Plot (Xuất vào thư mục FIGURES)
twoway (kdensity ln_OOP if INS_DUMMY == 1, color(navy) lwidth(medthick)) ///
       (kdensity ln_OOP if INS_DUMMY == 0, color(maroon) lpattern(dash) lwidth(medthick)), ///
       xtitle("Log Out-of-Pocket Expenditure (ln_OOP)") ///
       legend(order(1 "Insured" 2 "Uninsured") position(6) rows(1)) ///
       scheme(s1mono)
graph export "$figpath\Figure2_Kernel_Density.png", as(png) replace width(2000)

* ==============================================================================
* XUẤT TỔNG HỢP KẾT QUẢ 
* ==============================================================================

* Mở một file log text để lưu toàn bộ kết quả in ra màn hình
capture log close
log using "Ket_qua.txt", replace text

display "====================================================================="
display "1. THỐNG KÊ MÔ TẢ CÁC BIẾN (SUMMARY STATISTICS)"
display "====================================================================="
* Thống kê có trọng số mẫu để phản ánh đúng tổng thể
sum OOP_HH OOP_INPATIENT OOP_OUTPATIENT INS_DUMMY RURAL hh_vuot_tuyen ///
    ln_INC AGE_HEAD SEX_HEAD HH_SIZE IV_COMMUNE [aw=wt9]

display " "
display "====================================================================="
display "2. KẾT QUẢ MÔ HÌNH IV-2SLS (TỔNG OOP, NỘI TRÚ, NGOẠI TRÚ)"
display "====================================================================="
* In bảng kết quả IV-2SLS ra thẳng màn hình text
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
* CHẠY LẠI MÔ HÌNH VỚI DỮ LIỆU CHUẨN (N = 46,995)
* ==============================================================================

display ">>> CHẠY LẠI IV-2SLS CHO NỘI TRÚ VÀ NGOẠI TRÚ <<<"

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

display ">>> BƯỚC 3: XUẤT BẢNG KẾT QUẢ CHO LATEX <<<"

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


display ">>> BƯỚC 4: VẼ ĐỒ THỊ FOREST PLOT GỘP (COMBINED COEFPLOT) <<<"

* Cần cài đặt coefplot nếu chưa có: ssc install coefplot
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

* Xuất hình ảnh vào thư mục Figures
graph export "$figpath\Figure3_Combined_ForestPlot.png", as(png) replace width(2000)

********************************************************************************
* BƯỚC 6: KIỂM TRA ĐỘ VỮNG (ROBUSTNESS CHECKS)
********************************************************************************
display ">>> RUNNING ROBUSTNESS CHECKS <<<"

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
* TỔNG HỢP KIỂM ĐỊNH CÁC MÔ HÌNH (ROBUSTNESS & POST-ESTIMATION TESTS)
* ==============================================================================

* Cài đặt các gói lệnh cần thiết (Bỏ qua nếu máy bạn đã cài)
ssc install ivreg2, replace
ssc install ranktest, replace

* ------------------------------------------------------------------------------
* 1. KIỂM ĐỊNH ĐA CỘNG TUYẾN (MULTICOLLINEARITY)
* ------------------------------------------------------------------------------
display ">>> 1. KIEM DINH VIF CHO MO HINH CO SO <<<"
quietly reg ln_OOP INS_DUMMY RURAL hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot ln_INC $X i.tinh [pw=wt9]
vif
* Tiêu chuẩn: VIF của các biến kiểm soát (X) < 10 là an toàn. VIF của các biến tương tác cao là bình thường.

* ------------------------------------------------------------------------------
* 2. MA TRAN TUONG QUAN (CORRELATION MATRIX)
* ------------------------------------------------------------------------------
display ">>> MA TRAN TUONG QUAN CHO CAC BIEN CHINH TONG MO HINH <<<"

* Sử dụng pwcorr để xem hệ số tương quan từng cặp, hiển thị p-value (sig) và đánh dấu sao (*) nếu p < 0.05
pwcorr ln_OOP INS_DUMMY RURAL hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot ln_INC AGE_HEAD SEX_HEAD HH_SIZE, sig star(0.05)

* Ma trận tương quan có xét trọng số (sử dụng aweight thay cho pweight)
corr ln_OOP INS_DUMMY RURAL hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot ln_INC AGE_HEAD SEX_HEAD HH_SIZE [aw=wt9]

* ------------------------------------------------------------------------------
* 2. KIỂM ĐỊNH MÔ HÌNH BIẾN CÔNG CỤ (IV-2SLS)
* ------------------------------------------------------------------------------
display ">>> 2. KIEM DINH NO SINH VA BIEN CONG CU YEU (IV-2SLS) <<<"
* Lệnh ivreg2 sẽ tự động xuất ra các kiểm định Kleibergen-Paap và Durbin-Wu-Hausman
ivreg2 ln_OOP RURAL hh_vuot_tuyen rural_vuot_exo $X i.tinh ///
    (INS_DUMMY ins_rural ins_vuot ins_rural_vuot = IV_COMMUNE iv_rural iv_vuot iv_rural_vuot), ///
    cluster(tinh) endog(INS_DUMMY ins_rural ins_vuot ins_rural_vuot) first

* Tiêu chuẩn cần check trong bảng kết quả:
* - Kleibergen-Paap rk Wald F statistic > 10 (Bác bỏ H0: Biến công cụ yếu).
* - Endogeneity test (Durbin-Wu-Hausman) p-value < 0.05 hoặc 0.10 (Bác bỏ H0: Các biến ngoại sinh, xác nhận mô hình IV là cần thiết).
* Chạy lại mô hình IV (lưu ý: tạm thời bỏ [pw] và cluster để chạy được lệnh kiểm định gốc)
ivregress 2sls ln_OOP ln_INC AGE_HEAD SEX_HEAD HH_SIZE (INS_DUMMY ins_rural ins_vuot ins_rural_vuot = IV_COMMUNE iv_rural iv_vuot iv_rural_vuot)
* Cài đặt gói ivhettest nếu chưa có
ssc install ivhettest, replace
* Thực hiện kiểm định Pagan-Hall cho mô hình IV
ivhettest, ph
* Tính toán hệ số tương quan nội cụm (ICC) theo biến tỉnh
loneway ln_OOP tinh

* ------------------------------------------------------------------------------
* KIỂM ĐỊNH MÔ HÌNH BIẾN CÔNG CỤ (IV-2SLS) & ANDERSON-RUBIN TEST
* ------------------------------------------------------------------------------
* Cài đặt gói weakiv nếu chưa có
capture which weakiv
if _rc cap ssc install weakiv, replace

* Chạy mô hình ivreg2 để lấy các thông số kiểm định first-stage
ivreg2 ln_OOP RURAL hh_vuot_tuyen rural_vuot_exo $X i.tinh ///
    (INS_DUMMY ins_rural ins_vuot ins_rural_vuot = IV_COMMUNE iv_rural iv_vuot iv_rural_vuot), ///
    cluster(tinh) endog(INS_DUMMY ins_rural ins_vuot ins_rural_vuot) first

* KIỂM ĐỊNH ANDERSON-RUBIN (AR TEST) CHO BIẾN CÔNG CỤ YẾU
* Lệnh weakiv sẽ tính toán p-value của AR test và khoảng tin cậy (Confidence Interval) 
* mạnh (robust) ngay cả khi F-stat ở First-stage nhỏ.
display ">>> KIEM DINH ANDERSON-RUBIN (WEAK-INSTRUMENT ROBUST INFERENCE) <<<"
weakiv test (INS_DUMMY ins_rural ins_vuot ins_rural_vuot)

* Nếu bạn chỉ muốn focus test sự vững chắc của riêng hệ số tương tác 3 chiều:
weakiv test (ins_rural_vuot)

* ------------------------------------------------------------------------------
* 3. KIỂM ĐỊNH MÔ HÌNH PHÂN VỊ (SQREG)
* ------------------------------------------------------------------------------
display ">>> 3. KIEM DINH TINH PHI TUYEN CUA BHYT TREN CAC PHAN VI (SQREG) <<<"
* Chạy lại mô hình SQREG (có thể mất vài phút vì bootstrap 100 lần)
quietly sqreg ln_OOP INS_DUMMY hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot ln_INC $X i.tinh, ///
    quantiles(.25 .50 .75 .90) reps(100)

* Kiểm định Wald: Xem hệ số BHYT có bằng nhau giữa các phân vị không
test [q25]INS_DUMMY = [q50]INS_DUMMY = [q75]INS_DUMMY = [q90]INS_DUMMY

* Tiêu chuẩn: p-value < 0.05 (Bác bỏ H0: Tác động của BHYT là như nhau ở mọi phân vị).

* ------------------------------------------------------------------------------
* 4. KIỂM ĐỊNH GHÉP CẶP ĐIỂM XU HƯỚNG (PSM)
* ------------------------------------------------------------------------------
display ">>> 4. KIEM DINH SU CAN BANG VA VUNG HO TRO CHUNG (PSM) <<<"
quietly teffects psmatch (ln_OOP) (INS_DUMMY $X, probit), nn(1) vce(iid)

* Bảng kiểm tra sự cân bằng của các hiệp biến sau khi ghép cặp
tebalance summarize
* Tiêu chuẩn: Cột "Standardized Differences" ở phần Matched lý tưởng nhất là < 0.1.

* Vẽ và xuất đồ thị Vùng hỗ trợ chung (Common Support)
tebalance density
graph export "Common_Support_PSM.png", replace
* Tiêu chuẩn: Đồ thị cho thấy hai đường phân phối của nhóm Treatment và Control chồng lấp tốt lên nhau.

display ">>> HOAN THANH TOAN BO KIEM DINH <<<"

* ==============================================================================    
* KẾT THÚC
********************************************************************************
log close