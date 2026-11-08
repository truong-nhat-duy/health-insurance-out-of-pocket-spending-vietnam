*******************************************************
* FILE NAME :  bhyt_oop_vhlss2024.do
* PROJECT   :  Impact of Health Insurance on OOP
* AUTHOR    :  Truong Nhat Duy
* DATA      :  VHLSS 2024
*******************************************************
*------------------------------------------------------*
* Thiết lập môi trường làm việc
*------------------------------------------------------*
clear all
set more off
set linesize 120
capture log close
log using "bhyt_oop_2024.log", replace text

* Directory
local dir `c(pwd)'
cd "`dir'"

********************************************************************************
* BƯỚC 1: LÀM SẠCH VÀ CHUẨN BỊ DỮ LIỆU TỪNG FILE
********************************************************************************

* --- 1. FILE HỘ GIA ĐÌNH ---
use "Ho_ThongTinHo.dta", clear
rename *, lower
rename idho IDHO

* Biến Nông thôn (1=Nông thôn, 0=Thành thị)
gen RURAL = (ttnt == 2) 

* Thu nhập bình quân (Đổi từ Nghìn đồng -> Triệu đồng -> Lấy Log)
gen INC_HH_MIL = tongthu / 1000 
gen INC_PC_MIL = INC_HH_MIL / tsnguoi
gen ln_INC = ln(INC_PC_MIL + 1)

* Tổng chi OOP hộ (đơn vị: triệu đồng) 
gen OOP_HH = m3ct / 1000

keep IDHO tinh huyen xa diaban RURAL INC_PC_MIL ln_INC tsnguoi OOP_HH
save "b1_household.dta", replace

* --- 2. FILE NHÂN KHẨU & BHYT ---
use "Ho_ThanhVien.dta", clear
rename *, lower
rename idho IDHO

* Xác định chủ hộ và đặc điểm chủ hộ
gen IS_HEAD = (m1a_c3 == 1) // m1a_c3 là quan hệ với chủ hộ
gen AGE_VAL = m1a_c5 if IS_HEAD == 1 // m1a_c5 là tuổi
gen SEX_VAL = m1a_c2 if IS_HEAD == 1 // m1a_c2 là giới tính

bys IDHO: egen AGE_HEAD = max(AGE_VAL)
bys IDHO: egen SEX_HEAD = max(SEX_VAL)
bys IDHO: gen HH_SIZE = _N

* Biến BHYT (Theo bạn xác nhận là m3a_c7)
gen HAS_BHYT = (m3a_c7 == 1)
bys IDHO: egen BHYT_RATE = mean(HAS_BHYT)

* Giữ 1 dòng đại diện cho mỗi hộ
bys IDHO: keep if _n == 1
keep IDHO AGE_HEAD SEX_HEAD HH_SIZE BHYT_RATE
save "b2_demog.dta", replace

* --- 3. FILE CHI PHÍ Y TẾ VÀ HÀNH VI KHÁM BỆNH ---
use "Ho_Muc3A.dta", clear
rename *, lower
rename idho IDHO

* Phân loại tuyến khám
gen tuyen = .
replace tuyen = 1 if inlist(m3a_c3ma,1,2,3)       // Xã/Huyện
replace tuyen = 2 if inlist(m3a_c3ma,4,5,6)       // Tỉnh/TW
replace tuyen = 3 if inlist(m3a_c3ma,7,8)         // Tư nhân
replace tuyen = 4 if inlist(m3a_c3ma,9,10,11,12,13) // Mua thuốc/Tự điều trị

* Biến sử dụng thẻ BHYT (nếu có m3a_c4)
gen su_dung_bhyt = (m3a_c4 == 1)

* Biến vượt tuyến cá nhân (chỉ dựa vào tuyến khám, chưa lọc BHYT hộ/RURAL)
gen vuot_tuyen_ind = inlist(tuyen,2,3)

* Tổng hợp lên cấp hộ
bys IDHO: egen so_ca_kham = count(idtv)
bys IDHO: egen so_ca_vuot = total(vuot_tuyen_ind)
bys IDHO: egen hh_vuot_tuyen = max(vuot_tuyen_ind)
gen tyle_vuot = so_ca_vuot / so_ca_kham

* Giữ 1 dòng mỗi hộ
bys IDHO: keep if _n == 1
keep IDHO hh_vuot_tuyen so_ca_kham so_ca_vuot tyle_vuot
save "b3_oop.dta", replace

********************************************************************************
* BƯỚC 2: GHÉP NỐI VÀ TẠO CÁC BIẾN KINH TẾ LƯỢNG (MERGE & FEATURE ENGINEERING)
********************************************************************************
use "b1_household.dta", clear

* Ghép Nhân khẩu
merge 1:1 IDHO using "b2_demog.dta", keep(3) nogen

* Ghép Hành vi khám bệnh (File 3)
merge 1:1 IDHO using "b3_oop.dta"

* Hộ không có ai ốm đi khám (merge = 1) -> Khỏe mạnh, gán các biến = 0
replace hh_vuot_tuyen = 0 if _merge == 1
replace so_ca_kham = 0 if _merge == 1
replace so_ca_vuot = 0 if _merge == 1
replace tyle_vuot = 0 if _merge == 1
drop _merge

* Ghép trọng số
merge m:1 tinh huyen xa diaban using "weight2024_ver2.dta", keep(3) nogen

* --- 1. TẠO BIẾN CÔNG CỤ (LEAVE-ONE-OUT MEAN) ---
bys tinh huyen xa: egen sum_ins = total(BHYT_RATE)
bys tinh huyen xa: gen count_hh = _N
gen IV_COMMUNE = (sum_ins - BHYT_RATE) / (count_hh - 1)
* Sửa lỗi xã có 1 mẫu (giữ nguyên tỷ lệ của hộ đó để tránh missing data)
replace IV_COMMUNE = BHYT_RATE if count_hh == 1 

* --- 2. TẠO CÁC BIẾN DUMMY & LOG ---
* Dummy BHYT cấp hộ (Được xem là có BHYT nếu > 0 thành viên có thẻ)
gen INS_DUMMY = (BHYT_RATE > 0)

* Biến Log chi phí y tế
gen ln_OOP = ln(OOP_HH + 1)

* Hộ nông thôn có BHYT và CÓ vượt tuyến (Biến tương tác sâu)
gen rural_vuot = (RURAL == 1 & INS_DUMMY == 1 & hh_vuot_tuyen == 1)

* --- 3. GÁN NHÃN CHO DATA (LABELING) ---
label var OOP_HH "Chi OOP (Triệu VND)"
label var ln_OOP "Log(Chi OOP + 1)"
label var INS_DUMMY "Có BHYT (Hộ)"
label var RURAL "Nông thôn"
label var ln_INC "Log(Thu nhập)"
label var AGE_HEAD "Tuổi chủ hộ"
label var SEX_HEAD "Giới tính chủ hộ (1=Nam)"
label var HH_SIZE "Quy mô hộ"
label var IV_COMMUNE "Tỷ lệ BHYT xã (IV)"
label var hh_vuot_tuyen "Hộ có vượt tuyến (Dummy)"
label var rural_vuot "Nông thôn + BHYT + Vượt tuyến"

* LƯU BỘ DỮ LIỆU MASTER HOÀN CHỈNH
save "VHLSS24_Master_Analysis.dta", replace

********************************************************************************
* BƯỚC 3: THỐNG KÊ MÔ TẢ NHANH VÀ TRỰC QUAN HÓA (ENGLISH VERSION)
********************************************************************************
display ">>> DATA CLEANING COMPLETED. RUNNING DESCRIPTIVE STATISTICS <<<"

use "VHLSS24_Master_Analysis.dta", clear

* --- GẮN LẠI NHÃN TIẾNG ANH CHO CÁC BIẾN CHÍNH (Để xuất ra LaTeX chuẩn) ---
label var OOP_HH "OOP Expenditure (Million VND)"
label var ln_OOP "Log(OOP Expenditure + 1)"
label var INS_DUMMY "Health Insurance Coverage"
label var RURAL "Rural Area"
label var ln_INC "Log(Income per capita)"
label var AGE_HEAD "Age of Household Head"
label var SEX_HEAD "Male Household Head"
label var HH_SIZE "Household Size"
label var IV_COMMUNE "Commune-level HI Rate (IV)"
label var hh_vuot_tuyen "Bypassed Primary Care"
label var rural_vuot "Rural + Insured + Bypassed"

* ------------------------------------------------------------------------------
* 0. THIẾT LẬP BIẾN TOÀN CỤC & ĐƯỜNG DẪN
* ------------------------------------------------------------------------------
global Y "OOP_HH"
global X "ln_INC AGE_HEAD SEX_HEAD HH_SIZE"
global TREAT "INS_DUMMY"
global IV "IV_COMMUNE"

* Thiết lập đường dẫn xuất bảng và hình (Hãy giữ nguyên đường dẫn của bạn)
global outpath "D:\01. HOC HANH\13. THAC SI UEH\05. MON HOC\HOC KY 2\04. KINH TE SUC KHOE\04. De tai Bao hiem y te\02. De tai cuoi ky\01. Bai viet LAtex\figures"
cap mkdir "$outpath"

* Thiết lập trọng số mẫu
svyset [pw=wt9], strata(tinh) psu(diaban)

* Cài đặt package (Có thêm capture để bỏ qua nếu rớt mạng nhưng đã cài rồi)
capture which estout
if _rc cap ssc install estout
capture which collin
if _rc cap ssc install collin

********************************************************************************
* 1. THỐNG KÊ MÔ TẢ & TRỰC QUAN HÓA (DESCRIPTIVE STATISTICS)
********************************************************************************
display ">>> 1. RUNNING DESCRIPTIVE STATISTICS <<<"

* Bảng 1: Thống kê chung và So sánh theo nhóm BHYT
estpost tabstat $Y $TREAT $X RURAL hh_vuot_tuyen rural_vuot, ///
    by($TREAT) statistics(mean sd min max) columns(statistics)

* Xuất bảng ra LaTeX (Có label tiếng Anh, bỏ Title cứng để dùng caption trong Latex)
esttab using "$outpath\Summary_Stats.tex", replace main(mean) aux(sd) nostar unstack ///
    label nomtitle nonumber ///
    note("Note: Standard deviations are reported in parentheses.")

* Biểu đồ 1: Phân phối chi phí y tế (Bỏ title cứng, chuẩn hóa label)
histogram OOP_HH if OOP_HH < 50, percent normal ///
    xtitle("Million VND/year") ytitle("Percentage (%)") ///
    graphregion(color(white)) // Background trắng chuẩn bài viết
graph export "$outpath\hist_oop.png", replace as(png) width(1200)

* Biểu đồ 2: Kernel density của Log OOP theo nhóm BHYT
twoway (kdensity ln_OOP if INS_DUMMY==1, lcolor(navy) lwidth(medthick)) ///
       (kdensity ln_OOP if INS_DUMMY==0, lcolor(maroon) lpattern(dash) lwidth(medthick)), ///
       legend(label(1 "Insured") label(2 "Uninsured") position(6) rows(1)) ///
       xtitle("Log(OOP Expenditure + 1)") ytitle("Density") ///
       graphregion(color(white))
graph export "$outpath\kdensity_lnoop.png", replace as(png) width(1200)

* Biểu đồ 3: Boxplot so sánh OOP theo tình trạng vượt tuyến (nếu cần)
graph box OOP_HH if OOP_HH < 100, over(rural_vuot) ///
    ytitle("Million VND/year") ///
    graphregion(color(white))
graph export "$outpath\box_OOP_rural_vuot.png", replace as(png) width(1200)


********************************************************************************
* 2. MÔ HÌNH BASELINE VÀ KIỂM ĐỊNH (OLS DIAGNOSTICS)
********************************************************************************
display ">>> 2. RUNNING OLS & MODEL DIAGNOSTICS <<<"

* A. Chạy OLS ẨN để lấy các kiểm định kỹ thuật
quietly reg $Y $TREAT RURAL $X
vif                    // Multicollinearity
estat hettest          // Breusch-Pagan test for heteroskedasticity
quietly estat imtest, white // White test
estat ovtest           // Ramsey RESET test

* B. Chạy OLS CHÍNH THỨC (Có trọng số và sai số chuẩn cụm)
reg $Y $TREAT RURAL c.$TREAT#c.RURAL $X i.tinh [pw=wt9], vce(cluster tinh)
estimates store OLS_BASE

* C. Chạy OLS với Log(Y)
reg ln_OOP $TREAT RURAL c.$TREAT#c.RURAL $X i.tinh [pw=wt9], vce(cluster tinh)
estimates store OLS_LOG

* Xuất kết quả OLS ra file LaTeX
esttab OLS_BASE OLS_LOG using "$outpath\OLS_Results.tex", replace ///
    label b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep($TREAT RURAL c.$TREAT#c.RURAL $X) ///
    indicate("Province FE = *tinh") ///
    note("Robust standard errors clustered at the province level in parentheses.")
	
********************************************************************************
* 3. MÔ HÌNH BIẾN CÔNG CỤ (IV - 2SLS) VÀ KIỂM ĐỊNH
********************************************************************************
display ">>> 3. RUNNING 2SLS (IV) ESTIMATION <<<"

* A. Chạy mô hình 2SLS cho Log(OOP)
* Biến nội sinh: INS_DUMMY và c.INS_DUMMY#c.RURAL
* Biến công cụ: IV_COMMUNE và c.IV_COMMUNE#c.RURAL
ivregress 2sls ln_OOP RURAL $X i.tinh ///
    (INS_DUMMY c.INS_DUMMY#c.RURAL = IV_COMMUNE c.IV_COMMUNE#c.RURAL) ///
    [pw=wt9], vce(cluster tinh)

estimates store IV_LOG

* B. Các kiểm định sau mô hình (Post-estimation Diagnostics)
* Lưu ý: Các lệnh estat này yêu cầu chạy ngay sau ivregress

* B1. Kiểm định tính nội sinh (Endogeneity Test - Durbin-Wu-Hausman)
* H0: Các biến được xem là nội sinh thực chất là ngoại sinh (Nếu bác bỏ H0 -> OLS bị chệch, dùng IV là đúng đắn)
estat endogenous

* B2. Kiểm định Biến công cụ yếu (Weak Instrument Test - First Stage F-stat)
* H0: Biến công cụ yếu (F-stat ở bước 1 phải > 10, lý tưởng là > 104.7 theo Stock-Yogo để bác bỏ H0)
estat firststage

* A. Chạy lại mô hình 2SLS (để đưa vào bộ nhớ)
quietly ivregress 2sls ln_OOP RURAL $X i.tinh ///
    (INS_DUMMY c.INS_DUMMY#c.RURAL = IV_COMMUNE c.IV_COMMUNE#c.RURAL) ///
    [pw=wt9], vce(cluster tinh)

* B1. Kiểm định tính nội sinh (Endogeneity Test)
estat endogenous, forceweights

* B2. Kiểm định Biến công cụ yếu (Weak Instrument Test)
estat firststage, forceweights

********************************************************************************
* 4. KIỂM TRA ĐỘ VỮNG (ROBUSTNESS CHECKS)
********************************************************************************
display ">>> 4. RUNNING ROBUSTNESS CHECKS <<<"

* Robustness 1: Chạy mô hình IV với OOP gốc (Biến mức độ - Level)
ivregress 2sls OOP_HH RURAL $X i.tinh ///
    (INS_DUMMY c.INS_DUMMY#c.RURAL = IV_COMMUNE c.IV_COMMUNE#c.RURAL) ///
    [pw=wt9], vce(cluster tinh)
estimates store IV_LEVEL

* Robustness 2: Loại bỏ 1% giá trị dị biệt (Trim outliers)
* Tìm bách phân vị thứ 99 của chi phí y tế
quietly sum OOP_HH [aw=wt9], detail
local p99 = r(p99)

ivregress 2sls ln_OOP RURAL $X i.tinh ///
    (INS_DUMMY c.INS_DUMMY#c.RURAL = IV_COMMUNE c.IV_COMMUNE#c.RURAL) ///
    if OOP_HH < `p99' [pw=wt9], vce(cluster tinh)
estimates store IV_NO_OUTLIER

* Robustness 3: Chỉ xét tập mẫu có phát sinh nhu cầu khám chữa bệnh (so_ca_kham > 0)
ivregress 2sls ln_OOP RURAL $X i.tinh ///
    (INS_DUMMY c.INS_DUMMY#c.RURAL = IV_COMMUNE c.IV_COMMUNE#c.RURAL) ///
    if so_ca_kham > 0 [pw=wt9], vce(cluster tinh)
estimates store IV_SICK_ONLY

* Xuất toàn bộ kết quả so sánh ra LaTeX
esttab OLS_LOG IV_LOG IV_LEVEL IV_NO_OUTLIER IV_SICK_ONLY using "$outpath\Robustness_Results.tex", replace ///
    label b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(INS_DUMMY RURAL c.INS_DUMMY#c.RURAL $X) ///
    mtitles("OLS (Base)" "IV (Log OOP)" "IV (Level OOP)" "IV (No Outliers)" "IV (Sick Only)") ///
    indicate("Province FE = *tinh") ///
    note("Robust standard errors clustered at the province level in parentheses.")
	
* ==============================================================================
* 1. TẠO CÁC BIẾN TƯƠNG TÁC (Tạo thủ công để tránh lỗi kỹ thuật trong IV)
* ==============================================================================

* --- A. Tạo các biến tương tác Ngoại sinh (Exogenous interactions) ---
* Biến này nằm trong phương trình chính
capture drop rural_vuot_exo
gen rural_vuot_exo = RURAL * hh_vuot_tuyen

* --- B. Tạo các biến tương tác Nội sinh (Endogenous interactions) ---
capture drop ins_rural
capture drop ins_vuot
capture drop ins_rural_vuot

gen ins_rural = INS_DUMMY * RURAL
gen ins_vuot = INS_DUMMY * hh_vuot_tuyen
gen ins_rural_vuot = INS_DUMMY * RURAL * hh_vuot_tuyen 
label var ins_rural_vuot "Insured + Rural + Bypassed"

* --- C. Tạo các biến Công cụ tương ứng (Instrumental interactions) ---
capture drop iv_rural
capture drop iv_vuot
capture drop iv_rural_vuot

gen iv_rural = IV_COMMUNE * RURAL
gen iv_vuot = IV_COMMUNE * hh_vuot_tuyen
gen iv_rural_vuot = IV_COMMUNE * RURAL * hh_vuot_tuyen


* ==============================================================================
* 2. CHẠY MÔ HÌNH 2SLS (IV) VỚI CỤM TƯƠNG TÁC 3 CHIỀU
* ==============================================================================

display ">>> RUNNING 2SLS WITH 3-WAY INTERACTION (BYPASSING) <<<"

quietly ivregress 2sls ln_OOP RURAL hh_vuot_tuyen rural_vuot_exo $X i.tinh ///
    (INS_DUMMY ins_rural ins_vuot ins_rural_vuot = ///
     IV_COMMUNE iv_rural iv_vuot iv_rural_vuot) ///
    [pw=wt9], vce(cluster tinh)

* Hiển thị kết quả với các biến quan trọng lên đầu cho dễ nhìn
estat endogenous, forceweights
estimates store model_bypassed

* Hiển thị lại kết quả mô hình vừa lưu
estimates replay model_bypassed
	
* ==============================================================================
* FIGURE 1: TÁC ĐỘNG CỦA BHYT LÊN CHI PHÍ Y TẾ OOP (MARGINAL EFFECTS)
* Yêu cầu: Đã chạy và lưu kết quả "estimates store model_bypassed"
* Yêu cầu: ssc install coefplot
* ==============================================================================

* Phục hồi lại kết quả mô hình 2SLS
estimates restore model_bypassed

* Tính toán tác động của BHYT (INS_DUMMY) cho 4 nhóm đối tượng:

* 1. Thành thị + Khám ĐÚNG tuyến
quietly lincom INS_DUMMY
estimates store me_Urb_N

* 2. Thành thị + Khám VƯỢT tuyến
quietly lincom INS_DUMMY + ins_vuot
estimates store me_Urb_Y

* 3. Nông thôn + Khám ĐÚNG tuyến
quietly lincom INS_DUMMY + ins_rural
estimates store me_Rur_N

* 4. Nông thôn + Khám VƯỢT tuyến
quietly lincom INS_DUMMY + ins_rural + ins_vuot + ins_rural_vuot
estimates store me_Rur_Y

* ==============================================================================
* VẼ ĐỒ THỊ BẰNG COEFPLOT (Chuẩn format báo Q1)
* ==============================================================================

coefplot (me_Urb_N, label("Thành thị - Đúng tuyến")) ///
         (me_Urb_Y, label("Thành thị - Vượt tuyến")) ///
         (me_Rur_N, label("Nông thôn - Đúng tuyến")) ///
         (me_Rur_Y, label("Nông thôn - Vượt tuyến")), ///
         drop(_cons) xline(0, lpattern(dash) lcolor(red)) ///
         title("Figure 1: Marginal Effect of Health Insurance on ln(OOP)", size(medium) color(black)) ///
         subtitle("By Region and Bypassing Status (IV-2SLS Estimates)", size(small) color(gs5)) ///
         xtitle("Marginal Effect on Log Out-of-Pocket Expenditure (ln_OOP)") ///
         ciopts(lcolor(navy) lwidth(thin)) ///
         msymbol(D) mcolor(navy) msize(medium) ///
         legend(off) ///
         groups(me_Urb_N me_Urb_Y = "{bf:Khu vực Thành thị}" ///
                me_Rur_N me_Rur_Y = "{bf:Khu vực Nông thôn}") ///
         scheme(s1mono) // Sử dụng theme đen trắng học thuật
* ==============================================================================

* ==============================================================================
* FIGURE 2: KERNEL DENSITY PLOT CỦA CHI PHÍ Y TẾ OOP THEO TRẠNG THÁI BHYT
* ==============================================================================
display ">>> VẼ ĐỒ THỊ KERNEL DENSITY <<<"

twoway (kdensity ln_OOP if INS_DUMMY == 1, color(navy) lwidth(medthick)) ///
       (kdensity ln_OOP if INS_DUMMY == 0, color(maroon) lpattern(dash) lwidth(medthick)), ///
       title("Figure 2: Distribution of Log OOP Health Expenditure", size(medium) color(black)) ///
       subtitle("By Health Insurance Status", size(small) color(gs5)) ///
       xtitle("Log Out-of-Pocket Expenditure (ln_OOP)") ///
       ytitle("Density") ///
       legend(order(1 "Insured" 2 "Uninsured") position(6) rows(1)) ///
       scheme(s1mono) // Dùng theme đen trắng chuẩn báo cáo khoa học

* Xuất hình ra thư mục hiện tại
* graph export "Figure2_Kernel_Density.png", as(png) replace width(2000)

* ==============================================================================
* FOREST PLOT (ENGLISH VERSION FOR Q1 JOURNALS)
* ==============================================================================

* 1. Restore the saved 2SLS model estimates
estimates restore model_bypassed

* 2. Plot the coefficients with academic English labels
coefplot, ///
    keep(INS_DUMMY ins_rural ins_vuot ins_rural_vuot RURAL hh_vuot_tuyen rural_vuot_exo) ///
    coeflabels( ///
        INS_DUMMY      = "Health Insurance (Base)" ///
        ins_rural      = "Health Insurance x Rural" ///
        ins_vuot       = "Health Insurance x Bypassed" ///
        ins_rural_vuot = "Health Insurance x Rural x Bypassed" ///
        RURAL          = "Rural Area" ///
        hh_vuot_tuyen  = "Bypassed Primary Care" ///
        rural_vuot_exo = "Rural x Bypassed" ///
    ) ///
    xline(0, lpattern(dash) lcolor(red) lwidth(thin)) ///
    title("Figure 1: Coefficient Estimates of Health Insurance and Interactions", size(medium) color(black)) ///
    subtitle("IV-2SLS Model (Controlling for covariates and province fixed effects)", size(small) color(gs5)) ///
    xtitle("Effect on Log Out-of-Pocket Expenditure (ln_OOP)") ///
    ciopts(lcolor(navy) lwidth(medthick)) ///
    msymbol(D) mcolor(navy) msize(large) ///
    scheme(s1mono) /// Standard black-and-white theme for journals
    grid(none)

* 3. Export high-quality image (2000px width) directly to your LaTeX folder
graph export "D:\01. HOC HANH\13. THAC SI UEH\05. MON HOC\HOC KY 2\04. KINH TE SUC KHOE\04. De tai Bao hiem y te\02. De tai cuoi ky\01. Bai viet LAtex\figures\Figure1_ForestPlot_ENG.png", as(png) replace width(2000)

* ==============================================================================
* FIGURE 2: KERNEL DENSITY PLOT CỦA CHI PHÍ Y TẾ OOP THEO TRẠNG THÁI BHYT
* ==============================================================================
display ">>> VẼ ĐỒ THỊ KERNEL DENSITY <<<"

twoway (kdensity ln_OOP if INS_DUMMY == 1, color(navy) lwidth(medthick)) ///
       (kdensity ln_OOP if INS_DUMMY == 0, color(maroon) lpattern(dash) lwidth(medthick)), ///
       title("Figure 2: Distribution of Log OOP Health Expenditure", size(medium) color(black)) ///
       subtitle("By Health Insurance Status", size(small) color(gs5)) ///
       xtitle("Log Out-of-Pocket Expenditure (ln_OOP)") ///
       ytitle("Density") ///
       legend(order(1 "Insured" 2 "Uninsured") position(6) rows(1)) ///
       scheme(s1mono) // Dùng theme đen trắng chuẩn báo cáo khoa học

* Xuất hình ra thư mục hiện tại
graph export "D:\01. HOC HANH\13. THAC SI UEH\05. MON HOC\HOC KY 2\04. KINH TE SUC KHOE\04. De tai Bao hiem y te\02. De tai cuoi ky\01. Bai viet LAtex\figures\Figure2_Kernel_Density.png", as(png) replace width(2000)

* ==============================================================================
* ROBUSTNESS CHECK 1: PROPENSITY SCORE MATCHING (PSM)
* Mô hình Ghép cặp Điểm xu hướng (Propensity Score Matching - PSM)
* ==============================================================================
display ">>> RUNNING PROPENSITY SCORE MATCHING (NEAREST NEIGHBOR) <<<"

* Chạy PSM: Ghép 1-1 (Nearest Neighbor) dựa trên các biến kiểm soát
* Lưu ý: Lệnh này có thể chạy mất vài phút do mẫu của bạn khá lớn (hơn 46.000 obs)
teffects psmatch (ln_OOP) ///
                 (INS_DUMMY RURAL hh_vuot_tuyen ln_INC AGE_HEAD SEX_HEAD HH_SIZE i.tinh, probit), ///
                 nneighbor(1) vce(robust)

* Đánh giá chất lượng ghép cặp (Balance plot)
* Nếu các dấu chấm tụ về đường số 0, nghĩa là việc ghép cặp rất thành công.
tebalance density ln_INC

* ==============================================================================
* ROBUSTNESS CHECK 1: PROPENSITY SCORE MATCHING (ĐÃ XỬ LÝ LỖI OVERLAP)
* ==============================================================================
display ">>> BƯỚC 1: NHẬN DIỆN CÁC QUAN SÁT VI PHẠM COMMON SUPPORT <<<"

* Xóa biến vi_pham_overlap nếu đã từng tạo trước đó để tránh lỗi
capture drop vi_pham_overlap 

* Chạy lệnh lần 1 kèm option osample() để "bắt" các quan sát vi phạm. 
* Lệnh này SẼ báo lỗi màu đỏ (r459), nhưng không sao, Stata đã lưu biến vi_pham_overlap.
capture teffects psmatch (ln_OOP) ///
    (INS_DUMMY RURAL hh_vuot_tuyen ln_INC AGE_HEAD SEX_HEAD HH_SIZE i.tinh, probit), ///
    nneighbor(1) vce(robust) osample(vi_pham_overlap)

* Báo cáo xem có bao nhiêu người bị rớt khỏi Common Support
tab vi_pham_overlap, missing

* ------------------------------------------------------------------------------
display ">>> BƯỚC 2: CHẠY LẠI PSM TRÊN VÙNG HỖ TRỢ CHUNG (COMMON SUPPORT) <<<"

* Chạy lệnh chính thức với điều kiện if vi_pham_overlap == 0 (Chỉ lấy những người thỏa mãn)
teffects psmatch (ln_OOP) ///
    (INS_DUMMY RURAL hh_vuot_tuyen ln_INC AGE_HEAD SEX_HEAD HH_SIZE i.tinh, probit) ///
    if vi_pham_overlap == 0, ///
    nneighbor(1) vce(robust)
    
* Sau khi chạy xong, đánh giá chất lượng ghép cặp (Balance plot)
tebalance density ln_INC
graph export "D:\01. HOC HANH\13. THAC SI UEH\05. MON HOC\HOC KY 2\04. KINH TE SUC KHOE\04. De tai Bao hiem y te\02. De tai cuoi ky\01. Bai viet LAtex\figures\FBalance plot.png", as(png) replace width(2000)
* ==============================================================================
* ROBUSTNESS CHECK 2: SIMULTANEOUS QUANTILE REGRESSION (FIXED CONVERGENCE)
* Hồi quy Phân vị Đồng thời (Simultaneous Quantile Regression)
* ==============================================================================
display ">>> RUNNING SIMULTANEOUS QUANTILE REGRESSION (WITHOUT PROVINCE FE) <<<"

set seed 12345 
* Bỏ i.tinh ra khỏi mô hình để thuật toán có thể hội tụ
sqreg ln_OOP INS_DUMMY RURAL hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot ///
      ln_INC AGE_HEAD SEX_HEAD HH_SIZE, ///
      q(.25 .50 .75 .90) reps(100)

* So sánh hệ số của biến BHYT gốc giữa nhóm chi tiêu thấp và nhóm thảm họa
test [q25]INS_DUMMY = [q90]INS_DUMMY

* Chạy riêng lẻ không dùng bootstrap
qreg ln_OOP INS_DUMMY RURAL hh_vuot_tuyen ins_rural ins_vuot ins_rural_vuot ln_INC AGE_HEAD SEX_HEAD HH_SIZE i.tinh, q(.90) iterate(1000)

* ==============================================================================	 
*  KẾT THÚC
*******************************************************
log close
