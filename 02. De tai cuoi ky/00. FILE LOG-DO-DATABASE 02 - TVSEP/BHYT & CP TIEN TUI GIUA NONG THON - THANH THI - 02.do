* ==============================================================================
* FILE: TVSEP_Panel_Analysis_Final.do
* DATA: TVSEP_Panel_Clean_CPI_Labelled.dta
* MỤC TIÊU: Đánh giá hiệu ứng bảo vệ của BHYT và Cơ chế Vượt tuyến (VN vs THA)
* ==============================================================================

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
use "TVSEP_Panel_Clean_CPI_Labelled_Final.dta", clear

* ==============================================================================
* Thiết lập đường dẫn xuất file hình ảnh và bảng
* ==============================================================================
global figdir "D:\01. HOC HANH\13. THAC SI UEH\05. MON HOC\HOC KY 2\04. KINH TE SUC KHOE\04. De tai Bao hiem y te\02. De tai cuoi ky\01. Bai viet LATEX 02\figures"
set scheme s2color

* ------------------------------------------------------------------------------
* BƯỚC 1: THIẾT LẬP PANEL VÀ TẠO BIẾN CƠ CHẾ (MECHANISM VARIABLES)
* ------------------------------------------------------------------------------
* Tạo định danh Panel duy nhất
egen id_panel = group(hhid country_code)
xtset id_panel wave

* Đảm bảo biến Thái Lan dummy được định nghĩa chuẩn xác
gen THAI_dummy = (country_code == "THA")
replace INS_x_THAI = INS_dummy * THAI_dummy // Chạy lại cho chắc chắn

* TẠO BIẾN TƯƠNG TÁC CƠ CHẾ VƯỢT TUYẾN:
gen BYPASS_x_THAI = BYPASSED * THAI_dummy

* Gom nhóm biến kiểm soát (Lưu ý: Dùng age_head thay vì AGE_HEAD là năm sinh)
global X "age_head SEX_HEAD HH_SIZE Health_shock"

* ------------------------------------------------------------------------------
* BƯỚC 2: MÔ HÌNH 1 - ĐÁNH GIÁ TÁC ĐỘNG TỔNG THỂ (BASELINE TWFE)
* ------------------------------------------------------------------------------
display ">>> RUNNING MODEL 1: BHYT VÀ HIỆU ỨNG BẢO VỆ TỔNG THỂ <<<"
ssc install reghdfe, replace
ssc install ftools, replace
ssc install boottest, replace
ssc install require, replace

reghdfe ln_OOP_real INS_dummy INS_x_THAI $X, ///
    absorb(id_panel wave) vce(cluster village)
estimates store m1_baseline

* ------------------------------------------------------------------------------
* BƯỚC 3: MÔ HÌNH 2 - KIỂM CHỨNG CƠ CHẾ VƯỢT TUYẾN (GATEKEEPER MECHANISM)
* ------------------------------------------------------------------------------
display ">>> RUNNING MODEL 2: CƠ CHẾ VƯỢT TUYẾN (BYPASSING) <<<"

reghdfe ln_OOP_real INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI $X, ///
    absorb(id_panel wave) vce(cluster village)
estimates store m2_bypass

* ------------------------------------------------------------------------------
* BƯỚC 4: MÔ HÌNH 3 - CHỐNG THẢM HỌA Y TẾ (RIF-TWFE Q90)
* ------------------------------------------------------------------------------

display ">>> RUNNING MODEL 3: UNCONDITIONAL QUANTILE REGRESSION (Q90) <<<"

qreg ln_OOP_real INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI $X, quantile(0.9)
estimates store m3_qreg90


* ------------------------------------------------------------------------------
* BƯỚC 5: XUẤT BẢNG KẾT QUẢ CHUẨN Q1 (LATEX / WORD)
* ------------------------------------------------------------------------------
esttab m1_baseline m2_bypass m3_qreg90 using "Table_Results_TVSEP.rtf", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI Health_shock) ///
    coeflabels(INS_dummy "BHYT (Chung)" ///
               INS_x_THAI "BHYT x Thái Lan (Hiệu ứng chênh lệch BHYT)" ///
               BYPASSED "Vượt tuyến (Chung)" ///
               BYPASS_x_THAI "Vượt tuyến x Thái Lan (Hiệu ứng gác cổng)" ///
               Health_shock "Cú sốc sức khỏe") ///
    mtitles("Baseline (Mean)" "Mechanism (Mean)" "Catastrophic (Q90)") ///
    title("Tác động của BHYT và Hành vi Vượt tuyến đến Chi tiêu y tế (Việt Nam vs Thái Lan)") ///
    addnotes("Chi phí phụ thuộc: Log(OOP PPP USD Real). Kiểm soát Hiệu ứng cố định Hộ và Năm.")

* Robustness check: cluster theo hộ
reghdfe ln_OOP_real INS_dummy INS_x_THAI $X, absorb(id_panel wave) vce(cluster id_panel)

* Robustness check: cluster theo wave
reghdfe ln_OOP_real INS_dummy INS_x_THAI $X, absorb(id_panel wave) vce(cluster wave)

* Việt Nam
reghdfe ln_OOP_real INS_dummy BYPASSED $X if country_code=="VNM", absorb(id_panel wave) vce(cluster village)

* Thái Lan
reghdfe ln_OOP_real INS_dummy BYPASSED $X if country_code=="THA", absorb(id_panel wave) vce(cluster village)

qreg ln_OOP_real INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI $X, quantile(0.5)
estimates store m_q50

qreg ln_OOP_real INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI $X, quantile(0.9)
estimates store m_q90

graph box ln_OOP_real, over(INS_dummy) over(country_code) ///
    title("Chi phí ngoài túi theo BHYT và quốc gia")
	

* ==============================================================================
* ADD-ON: Thống kê mô tả, so sánh theo wave, và phân tích động BHYT theo quốc gia
* Thêm vào cuối do-file chính
* ==============================================================================

* -------------------------
* A. Thống kê mô tả tổng quan
* -------------------------
display ">>> A. Descriptive statistics by country and INS status <<<"

* 1) Tổng quan: số obs, mean ln_OOP_real, sd, median, min, max
gen group_country_ins = country_code + "_" + string(INS_dummy)

tabstat ln_OOP_real HH_SIZE age_head Health_shock, ///
    by(group_country_ins) statistics(n mean sd median min max) ///
    columns(statistics) format(%9.3f)

* 2) Bảng tóm tắt (tabulate) cho biến nhị phân
tabulate country_code INS_dummy, missing

* 3) Bảng cân bằng: mean của các biến kiểm soát theo INS và country
gen group_country_ins = country_code + "_" + string(INS_dummy)

tabstat age_head SEX_HEAD HH_SIZE Health_shock, ///
    by(group_country_ins) statistics(mean sd) ///
    columns(statistics) format(%9.3f)

* 4) Lưu kết quả mô tả ra file CSV để dùng trong báo cáo (tuỳ chọn)
capture postutil clear
tempfile desc_stats
preserve
collapse (count) N=ln_OOP_real (mean) mean_ln_OOP=ln_OOP_real (sd) sd_ln_OOP=ln_OOP_real ///
         (median) med_ln_OOP=ln_OOP_real, by(country_code INS_dummy)
save `desc_stats', replace
restore

* Bạn có thể export `desc_stats' nếu cần:
* export delimited using "desc_stats_by_country_ins.csv", replace

* Tính trung bình ln_OOP_real theo wave, country, INS
collapse (mean) mean_ln_OOP=ln_OOP_real, by(wave country_code INS_dummy)

* Vẽ xu hướng cho Việt Nam
twoway (line mean_ln_OOP wave if country_code=="VNM" & INS_dummy==0, ///
          lcolor(red) lpattern(dash)) ///
       (line mean_ln_OOP wave if country_code=="VNM" & INS_dummy==1, ///
          lcolor(red) lpattern(solid)), ///
       title("Việt Nam: Chi phí ngoài túi theo wave") ///
       legend(order(1 "No INS" 2 "INS")) ///
       ytitle("Mean Log(OOP)") xtitle("Wave")

* Vẽ xu hướng cho Thái Lan
twoway (line mean_ln_OOP wave if country_code=="THA" & INS_dummy==0, ///
          lcolor(blue) lpattern(dash)) ///
       (line mean_ln_OOP wave if country_code=="THA" & INS_dummy==1, ///
          lcolor(blue) lpattern(solid)), ///
       title("Thái Lan: Chi phí ngoài túi theo wave") ///
       legend(order(1 "No INS" 2 "INS")) ///
       ytitle("Mean Log(OOP)") xtitle("Wave")
	   
* ------------------------- không được
* B. So sánh trung bình theo wave (means + t-tests)
* -------------------------
display ">>> B. Mean comparisons by wave (INS vs No INS) for each country <<<"

* 1) Tạo bảng mean ln_OOP_real by wave, country, INS
preserve
collapse (mean) mean_ln_OOP=ln_OOP_real (sd) sd_ln_OOP=ln_OOP_real (count) N=ln_OOP_real, ///
    by(wave country_code INS_dummy)
sort country_code wave INS_dummy
list wave country_code INS_dummy N mean_ln_OOP sd_ln_OOP, sepby(country_code) noobs
restore

* 2) T-test INS vs No-INS within each wave and country
display ">>> t-tests: INS vs No INS by wave and country <<<"
levelsof wave, local(waves)
foreach w of local waves {
    display "---- Wave `w' ----"
    foreach c in VNM THA {
        capture noisily ttest ln_OOP_real, by(INS_dummy) if country_code=="`c'" & wave==`w'
    }
}

* -------------------------
* C. Đồ thị: xu hướng trung bình theo wave (phân theo BHYT và quốc gia)
* -------------------------
display ">>> C. Plotting time trends by INS and country <<<"

* 1) Tính mean theo wave × country × INS
preserve
collapse (mean) mean_ln_OOP=ln_OOP_real, by(wave country_code INS_dummy)

* 2) Reshape để dễ vẽ: tạo series cho 4 đường: VNM_INS1, VNM_INS0, THA_INS1, THA_INS0
preserve
collapse (mean) mean_ln_OOP=ln_OOP_real, by(wave country_code INS_dummy)

twoway ///
    (line mean_ln_OOP wave if country_code=="VNM" & INS_dummy==0, lcolor(red) lpattern(dash)) ///
    (line mean_ln_OOP wave if country_code=="VNM" & INS_dummy==1, lcolor(red) lpattern(solid)) ///
    (line mean_ln_OOP wave if country_code=="THA" & INS_dummy==0, lcolor(blue) lpattern(dash)) ///
    (line mean_ln_OOP wave if country_code=="THA" & INS_dummy==1, lcolor(blue) lpattern(solid)), ///
    legend(order(1 "VN No INS" 2 "VN INS" 3 "THA No INS" 4 "THA INS")) ///
    title("Chi phí ngoài túi trung bình theo wave, quốc gia và BHYT") ///
    ytitle("Mean Log(OOP Real)") xtitle("Wave")
graph export "Chi phí ngoài túi trung bình theo wave, quốc gia và BHYT.png", replace
set scheme s2color
graph export "D:\01. HOC HANH\13. THAC SI UEH\05. MON HOC\HOC KY 2\04. KINH TE SUC KHOE\04. De tai Bao hiem y te\02. De tai cuoi ky\01. Bai viet LATEX 02\figures\oop_trend_by_country_ins.png", replace as(png)
restore	

* ------------------------------------------------------------------------------
* Xuất thêm các biểu đồ khác (ví dụ boxplot, CDF, coefficient plot)
* ------------------------------------------------------------------------------
graph box ln_OOP_real, over(INS_dummy) over(country_code) ///
    title("Chi phí ngoài túi theo BHYT và quốc gia") ///
    ytitle("Log(OOP Real)") ///
    name(gbox_ins_country, replace)
graph export "${figdir}\gbox_ins_country.png", replace as(png)

cumul ln_OOP_real, gen(cdf)
twoway (line cdf ln_OOP_real if country_code=="VNM", lcolor(red)) ///
       (line cdf ln_OOP_real if country_code=="THA", lcolor(blue)), ///
       legend(order(1 "Việt Nam" 2 "Thái Lan")) ///
       title("CDF của Log(OOP) theo quốc gia") ///
       ytitle("Cumulative probability") ///
       name(gcdf_country, replace)
graph export "${figdir}\gcdf_country.png", replace as(png)

* ------------------------------------------------------------------------------
* Xuất boxplot theo BHYT và quốc gia
* ------------------------------------------------------------------------------
graph box ln_OOP_real, over(INS_dummy) over(country_code) ///
    title("Chi phí ngoài túi theo BHYT và quốc gia") ///
    ytitle("Log(OOP Real)") ///
    name(gbox_ins_country, replace)
graph export "${figdir}\gbox_ins_country.png", replace as(png)

* ------------------------------------------------------------------------------
* Xuất CDF theo quốc gia
* ------------------------------------------------------------------------------
cumul ln_OOP_real, gen(cdf)
twoway (line cdf ln_OOP_real if country_code=="VNM", lcolor(red)) ///
       (line cdf ln_OOP_real if country_code=="THA", lcolor(blue)), ///
       legend(order(1 "Việt Nam" 2 "Thái Lan")) ///
       title("CDF của Log(OOP) theo quốc gia") ///
       ytitle("Cumulative probability") ///
       name(gcdf_country, replace)
graph export "${figdir}\gcdf_country.png", replace as(png)


* Vẽ: Việt Nam (INS vs No INS)
twoway (line mean_ln_OOP if country_code=="VNM" & INS_dummy==0, ///
          sort lcolor(red) lpattern(dash) lwidth(medthick)) ///
       (line mean_ln_OOP if country_code=="VNM" & INS_dummy==1, ///
          sort lcolor(red) lpattern(solid) lwidth(medthick)), ///
       title("Việt Nam: Mean Log(OOP) theo wave (No INS vs INS)") ///
       ytitle("Mean Log(OOP)") xtitle("Wave") ///
       legend(order(1 "No INS" 2 "INS")) name(g_vnm_trend, replace)
graph export "trend_vnm_ins.png", replace

* Thái Lan
twoway (line mean_ln_OOP if country_code=="THA" & INS_dummy==0, ///
          sort lcolor(blue) lpattern(dash) lwidth(medthick)) ///
       (line mean_ln_OOP if country_code=="THA" & INS_dummy==1, ///
          sort lcolor(blue) lpattern(solid) lwidth(medthick)), ///
       title("Thái Lan: Mean Log(OOP) theo wave (No INS vs INS)") ///
       ytitle("Mean Log(OOP)") xtitle("Wave") ///
       legend(order(1 "No INS" 2 "INS")) name(g_tha_trend, replace)
graph export "trend_tha_ins.png", replace

restore

* 3) Plot difference (INS - No INS) by wave for each country (visualize gap)
preserve
collapse (mean) mean_ln_OOP=ln_OOP_real, by(wave country_code INS_dummy)
sort country_code wave INS_dummy
* compute difference
bysort country_code wave: egen mean_ins = mean(mean_ln_OOP) if INS_dummy==1
bysort country_code wave: egen mean_noins = mean(mean_ln_OOP) if INS_dummy==0
gen diff_ins_noins = mean_ins - mean_noins
twoway (line diff_ins_noins wave if country_code=="VNM", lcolor(red)) ///
       (line diff_ins_noins wave if country_code=="THA", lcolor(blue)), ///
       legend(order(1 "VNM: INS - NoINS" 2 "THA: INS - NoINS")) ///
       title("Khoảng cách Mean Log(OOP) giữa INS và NoINS theo wave") ///
       ytitle("Mean(INS) - Mean(NoINS)") name(g_diff_ins, replace)
graph export "diff_ins_by_wave.png", replace
restore

* ==============================================================================
* Thiết lập đường dẫn xuất file hình ảnh và bảng
* ==============================================================================

* Xuất bảng kết quả chính (RTF) vào thư mục figures
esttab m1_baseline m2_bypass m3_qreg90 using "${figdir}\Table_Results_TVSEP.rtf", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI Health_shock) ///
    coeflabels(INS_dummy "BHYT (Chung)" ///
               INS_x_THAI "BHYT x Thái Lan (Hiệu ứng chênh lệch BHYT)" ///
               BYPASSED "Vượt tuyến (Chung)" ///
               BYPASS_x_THAI "Vượt tuyến x Thái Lan (Hiệu ứng gác cổng)" ///
               Health_shock "Cú sốc sức khỏe") ///
    mtitles("Baseline (Mean)" "Mechanism (Mean)" "Catastrophic (Q90)") ///
    title("Tác động của BHYT và Vượt tuyến đến Chi tiêu y tế (VN vs THA)") ///
    addnotes("Chi phí phụ thuộc: Log(OOP PPP USD Real). FE: Hộ và Wave. Cluster: village.")

* ==============================================================================
* Xuất đồ thị với nền trắng học thuật
* ==============================================================================

* Boxplot theo BHYT và quốc gia
graph box ln_OOP_real, over(INS_dummy) over(country_code) ///
    title("Chi phí ngoài túi theo BHYT và quốc gia") ///
    ytitle("Log(OOP Real)") ///
    name(gbox_ins_country, replace)
graph export "${figdir}\gbox_ins_country.png", replace as(png)

* Xu hướng trung bình theo wave (Việt Nam vs Thái Lan)
collapse (mean) mean_ln_OOP=ln_OOP_real, by(wave country_code)
twoway (line mean_ln_OOP wave if country_code=="VNM", lcolor(red)) ///
       (line mean_ln_OOP wave if country_code=="THA", lcolor(blue)), ///
       legend(order(1 "Việt Nam" 2 "Thái Lan")) ///
       title("Xu hướng trung bình Log(OOP) theo thời gian") ///
       ytitle("Mean Log(OOP Real)") xtitle("Wave") ///
       name(gtrend_wave, replace)
graph export "${figdir}\gtrend_wave.png", replace as(png)

* Phân phối CDF theo quốc gia
cumul ln_OOP_real, gen(cdf)
twoway (line cdf ln_OOP_real if country_code=="VNM", lcolor(red)) ///
       (line cdf ln_OOP_real if country_code=="THA", lcolor(blue)), ///
       legend(order(1 "Việt Nam" 2 "Thái Lan")) ///
       title("CDF của Log(OOP) theo quốc gia") ///
       ytitle("Cumulative probability") ///
       name(gcdf_country, replace)
graph export "${figdir}\gcdf_country.png", replace as(png)

* Coefficient plot (nếu đã lưu các estimates)
coefplot m1_baseline m2_bypass m3_qreg90, ///
    keep(INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI Health_shock) ///
    xline(0) vertical ///
    title("So sánh hệ số BHYT và Vượt tuyến") ///
    name(gcoef_models, replace)
graph export "${figdir}\gcoef_models.png", replace as(png)

* -------------------------
* D. Phân tích động: ước lượng hệ số INS theo wave × country (event-study style)
* Ghi chú: không absorb wave ở đây; absorb id_panel để giữ FE hộ
* -------------------------
display ">>> D. Dynamic analysis: INS effect by wave and country (interaction) <<<"

* 1) Tạo mô hình tương tác: i.wave##i.INS_dummy##i.THAI_dummy
*    absorb id_panel (hộ FE), cluster theo village
reghdfe ln_OOP_real i.wave##i.INS_dummy##i.THAI_dummy $X, ///
    absorb(id_panel) vce(cluster village)
estimates store m_dyn_wave_country

* 2) Trích các hệ số liên quan đến INS by wave and country
*    Cách chọn tên hệ số: inspect _b names via ereturn list or use coefplot keep pattern
*    Dùng coefplot để vẽ hệ số INS theo wave cho mỗi country
capture which coefplot
if _rc {
    display "coefplot not installed; installing..."
    ssc install coefplot, replace
}

* Vẽ hệ số tương tác: giữ các hệ số chứa "INS_dummy#"
coefplot m_dyn_wave_country, ///
    keep(*.INS_dummy* .INS_dummy#* .INS_dummy##*) ///
    drop(_cons) xline(0) vertical ///
    title("Hệ số tương tác: INS by wave and country") ///
    xlabel(, angle(45)) name(gcoef_dyn, replace)
graph export "coef_dyn_ins_wave_country.png", replace

* 3) Nếu muốn, tách riêng hệ số INS by wave cho VNM và THA bằng lincom
*    Ví dụ: hệ số INS at wave k for VNM = coefficient of i.wave#i.INS_dummy (when THAI_dummy==0)
*    Hệ số INS at wave k for THA = sum of i.wave#i.INS_dummy + i.wave#i.INS_dummy#i.THAI_dummy
*    Dùng loop để compute lincoms và lưu kết quả
matrix results = J(0,4,.)
local waveslist : levelsof wave
foreach w of local waveslist {
    * name of coefficient for VNM: _b[1.wave#1.INS_dummy] pattern depends on factor coding
    * Use lincom to compute difference: INS at wave w for THA minus INS at wave w for VNM
    capture noisily lincom (1.wave#1.INS_dummy) if false
    * Safer approach: use margins after marginsplot (but margins with interactions and absorb may be tricky)
}

* -------------------------
* E. Bổ sung: bảng tóm tắt kết quả theo country (esttab)
* -------------------------
display ">>> E. Country-specific summary tables <<<"

esttab m_vnm m_tha using "Table_CountrySpecific.rtf", replace ///
    b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
    keep(INS_dummy BYPASSED HH_SIZE Health_shock) ///
    coeflabels(INS_dummy "BHYT (Chung)" BYPASSED "Vượt tuyến" HH_SIZE "Quy mô hộ" Health_shock "Cú sốc sức khỏe") ///
    mtitles("Việt Nam" "Thái Lan") ///
    title("So sánh tác động BHYT và Vượt tuyến: VN vs THA") ///
    addnotes("FE: id_panel + wave (nếu có). Cluster: village.")

* -------------------------
* F. Lưu các đồ thị và kết thúc phần bổ sung
* -------------------------
display ">>> Supplementary analysis complete. Check generated PNG and RTF files. <<<"

* ==============================================================================
* END ADD-ON
* ==============================================================================
* ==============================================================================
* FILE: TVSEP_Panel_Analysis_Final_Expanded.do
* DATA: TVSEP_Panel_Clean_CPI_Labelled.dta
* MỤC TIÊU: Đánh giá hiệu ứng bảo vệ của BHYT và Cơ chế Vượt tuyến (VN vs THA)
*         + Phân tích mở rộng, robustness checks, và đồ thị minh họa
* TÁC GIẢ: (Bạn / Nhóm nghiên cứu)
* NGÀY: (Điền ngày)
* ==============================================================================

*-------------------------------------------------------------------------------
* 0. Thiết lập môi trường
*-------------------------------------------------------------------------------
clear all
set more off
set linesize 120
capture log close
log using "bhyt_oop_2024_Final_expanded.log", replace text

* Đặt thư mục làm việc (sửa theo máy của bạn nếu cần)
local dir `c(pwd)'
cd "`dir'"

* ------------------------------------------------------------------------------
* 0.1 Kiểm tra và cài đặt các gói cần thiết
* ------------------------------------------------------------------------------
capture which reghdfe
if _rc {
    display "Installing reghdfe and dependencies..."
    ssc install ftools, replace
    ssc install reghdfe, replace
    ssc install boottest, replace
    ssc install require, replace
}

capture which esttab
if _rc {
    display "Installing estout (esttab)..."
    ssc install estout, replace
}

capture which coefplot
if _rc {
    display "Installing coefplot..."
    ssc install coefplot, replace
}

* rifhdreg không có sẵn trên SSC phổ biến; chúng ta sẽ cung cấp 2 lựa chọn:
* 1) dùng qreg (conditional quantile)
* 2) tự tạo biến RIF trong Stata (approximate) và chạy reghdfe trên rif_q90
* (Nếu bạn có rifhdreg từ nguồn khác, có thể thay thế trực tiếp.)

* ------------------------------------------------------------------------------
* 1. Load dữ liệu và thiết lập panel
* ------------------------------------------------------------------------------
use "TVSEP_Panel_Clean_CPI_Labelled.dta", clear

* Tạo ID panel duy nhất
egen id_panel = group(hhid country_code)
xtset id_panel wave

* Tạo biến Thái Lan dummy và tương tác
gen THAI_dummy = (country_code == "THA")
* Nếu INS_x_THAI chưa tồn tại hoặc muốn chắc chắn:
gen INS_x_THAI = INS_dummy * THAI_dummy

* Tạo tương tác vượt tuyến x Thái Lan
gen BYPASS_x_THAI = BYPASSED * THAI_dummy

* Gom nhóm biến kiểm soát
global X "age_head SEX_HEAD HH_SIZE Health_shock"

* ------------------------------------------------------------------------------
* 2. Mô hình 1 - Baseline TWFE (Mean effects)
* ------------------------------------------------------------------------------
display ">>> RUNNING MODEL 1: BHYT VÀ HIỆU ỨNG BẢO VỆ TỔNG THỂ (TWFE) <<<"

reghdfe ln_OOP_real INS_dummy INS_x_THAI $X, ///
    absorb(id_panel wave) vce(cluster village)
estimates store m1_baseline

* ------------------------------------------------------------------------------
* 3. Mô hình 2 - Mechanism: BYPASSED (Gatekeeping)
* ------------------------------------------------------------------------------
display ">>> RUNNING MODEL 2: CƠ CHẾ VƯỢT TUYẾN (TWFE) <<<"

reghdfe ln_OOP_real INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI $X, ///
    absorb(id_panel wave) vce(cluster village)
estimates store m2_bypass

* ------------------------------------------------------------------------------
* 4A. Mô hình 3 - Conditional Quantile Regression (Q90) bằng qreg
* ------------------------------------------------------------------------------
display ">>> RUNNING MODEL 3A: CONDITIONAL QUANTILE REGRESSION (Q90) - qreg <<<"

qreg ln_OOP_real INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI $X, quantile(0.9)
estimates store m3_qreg90

* ------------------------------------------------------------------------------
* 4B. (TÙY CHỌN) Tạo biến RIF cho Q90 trong Stata (approximate) và chạy RIF-TWFE
* Ghi chú: ước lượng mật độ f(q) bằng kernel density và lấy giá trị gần nhất
* ------------------------------------------------------------------------------
display ">>> OPTION: TẠO BIẾN RIF Q90 TRONG STATA (approximate) <<<"

* Tính giá trị phân vị 90
summarize ln_OOP_real, detail
local q90 = r(p90)
display "q90 = " `q90'

* Tạo kernel density grid (lưu vào biến tạm)
preserve
keep ln_OOP_real
kdensity ln_OOP_real, generate(kx ky)
gen absdiff = abs(kx - `q90')
egen minabs = min(absdiff)
keep if absdiff == minabs
graph export "kernel density estimates.png", replace

* Lấy mật độ tại điểm gần nhất
scalar f_q90 = ky[1]
display "Estimated density at q90 (f_q90) = " scalar(f_q90)
restore

* Nếu f_q90 quá nhỏ hoặc missing, cảnh báo
if scalar(f_q90) <= 0 | missing(scalar(f_q90)) {
    display as error "Warning: estimated f_q90 is missing or non-positive. RIF variable will not be created."
}
else {
    * Tạo biến RIF theo công thức: RIF(y; q) = q + (tau - 1{y <= q}) / f(q)
    gen rif_q90 = `q90' + (0.9 - (ln_OOP_real <= `q90')) / scalar(f_q90)

    * Kiểm tra phân phối rif_q90
    summarize rif_q90, detail

    * Chạy TWFE trên rif_q90
    reghdfe rif_q90 INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI $X, ///
        absorb(id_panel wave) vce(cluster village)
    estimates store m3_rif90
}

* ------------------------------------------------------------------------------
* 5. Robustness checks
* ------------------------------------------------------------------------------
display ">>> ROBUSTNESS CHECKS <<<"

* 5.1 Cluster theo id_panel (hộ) thay vì village
reghdfe ln_OOP_real INS_dummy INS_x_THAI $X, absorb(id_panel wave) vce(cluster id_panel)
estimates store m1_cluster_hhid

* 5.2 Cluster theo wave
reghdfe ln_OOP_real INS_dummy INS_x_THAI $X, absorb(id_panel wave) vce(cluster wave)
estimates store m1_cluster_wave

* 5.3 FE đơn giản (xtreg, fe) để so sánh (chay lỗi)
xtset id_panel wave
xtreg ln_OOP_real INS_dummy INS_x_THAI $X, fe vce(cluster village)
estimates store m1_xtfe

* ------------------------------------------------------------------------------
* 6. Phân tích riêng theo quốc gia (Việt Nam vs Thái Lan)
* ------------------------------------------------------------------------------
display ">>> COUNTRY-SPECIFIC ESTIMATES <<<"

* Việt Nam
reghdfe ln_OOP_real INS_dummy BYPASSED $X if country_code=="VNM", ///
    absorb(id_panel wave) vce(cluster village)
estimates store m_vnm

* Thái Lan
reghdfe ln_OOP_real INS_dummy BYPASSED $X if country_code=="THA", ///
    absorb(id_panel wave) vce(cluster village)
estimates store m_tha

* ------------------------------------------------------------------------------
* 7. Xuất bảng kết quả (esttab)
* ------------------------------------------------------------------------------
display ">>> EXPORTING TABLES (esttab) <<<"

* Chọn mô hình để xuất: nếu m3_rif90 tồn tại thì dùng, nếu không dùng m3_qreg90
capture confirm estimate m3_rif90
if _rc {
    * m3_rif90 không tồn tại -> dùng m3_qreg90
    esttab m1_baseline m2_bypass m3_qreg90 using "Table_Results_TVSEP.rtf", replace ///
        b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
        keep(INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI Health_shock) ///
        coeflabels(INS_dummy "BHYT (Chung)" ///
                   INS_x_THAI "BHYT x Thái Lan (Hiệu ứng chênh lệch BHYT)" ///
                   BYPASSED "Vượt tuyến (Chung)" ///
                   BYPASS_x_THAI "Vượt tuyến x Thái Lan (Hiệu ứng gác cổng)" ///
                   Health_shock "Cú sốc sức khỏe") ///
        mtitles("Baseline (Mean)" "Mechanism (Mean)" "Q90 (qreg)") ///
        title("Tác động của BHYT và Vượt tuyến đến Chi tiêu y tế (VN vs THA)") ///
        addnotes("Chi phí phụ thuộc: Log(OOP PPP USD Real). FE: Hộ và Wave. Cluster: village.")
}
else {
    esttab m1_baseline m2_bypass m3_rif90 using "Table_Results_TVSEP.rtf", replace ///
        b(3) se(3) star(* 0.10 ** 0.05 *** 0.01) ///
        keep(INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI Health_shock) ///
        coeflabels(INS_dummy "BHYT (Chung)" ///
                   INS_x_THAI "BHYT x Thái Lan (Hiệu ứng chênh lệch BHYT)" ///
                   BYPASSED "Vượt tuyến (Chung)" ///
                   BYPASS_x_THAI "Vượt tuyến x Thái Lan (Hiệu ứng gác cổng)" ///
                   Health_shock "Cú sốc sức khỏe") ///
        mtitles("Baseline (Mean)" "Mechanism (Mean)" "RIF Q90") ///
        title("Tác động của BHYT và Vượt tuyến đến Chi tiêu y tế (VN vs THA)") ///
        addnotes("Chi phí phụ thuộc: Log(OOP PPP USD Real). FE: Hộ và Wave. Cluster: village.")
}

* ------------------------------------------------------------------------------
* 8. ĐỒ THỊ MINH HỌA (LƯU HÌNH ẢNH)
* ------------------------------------------------------------------------------
display ">>> PLOTTING GRAPHS <<<"

* 8.1 Boxplot ln_OOP_real theo BHYT và quốc gia
graph box ln_OOP_real, over(INS_dummy) over(country_code) ///
    title("Chi phí ngoài túi theo BHYT và quốc gia") ///
    ytitle("Log(OOP Real)") ///
    name(gbox_ins_country, replace)
graph export "gbox_ins_country.png", replace

* 8.2 Xu hướng trung bình ln_OOP_real theo wave cho mỗi quốc gia
preserve
collapse (mean) ln_OOP_real (count) N = ln_OOP_real, by(wave country_code)
twoway (line ln_OOP_real wave if country_code=="VNM", lcolor(red) lpattern(solid) ///
        lwidth(medthick) ) ///
       (line ln_OOP_real wave if country_code=="THA", lcolor(blue) lpattern(dash) ///
        lwidth(medthick) ), ///
       legend(order(1 "Việt Nam" 2 "Thái Lan")) ///
       title("Xu hướng trung bình Log(OOP) theo thời gian") ///
       ytitle("Mean Log(OOP Real)") ///
       xtitle("Wave") ///
       name(gtrend_wave, replace)
graph export "gtrend_wave.png", replace
restore

* 8.3 Phân phối (CDF) ln_OOP_real theo quốc gia (chay lỗi)
preserve
keep ln_OOP_real country_code
sort ln_OOP_real
by country_code: gen rank = _n
by country_code: gen N = _N
gen cdf = rank / N
twoway (line cdf ln_OOP_real if country_code=="VNM", lcolor(red)) ///
       (line cdf ln_OOP_real if country_code=="THA", lcolor(blue)), ///
       legend(order(1 "Việt Nam" 2 "Thái Lan")) ///
       title("CDF của Log(OOP) theo quốc gia") ///
       ytitle("Cumulative probability") ///
       name(gcdf_country, replace)
graph export "gcdf_country.png", replace
restore

* 8.4 Coefficient plot: so sánh hệ số chính giữa các mô hình (dùng coefplot)
* Lưu ý: coefplot cần các estimates đã lưu
capture which coefplot
if _rc {
    display "coefplot not installed; skipping coefficient plot."
}
else {
    * Chọn các mô hình có tồn tại
    local models ""
    capture confirm estimate m1_baseline
    if !_rc local models "`models' m1_baseline"
    capture confirm estimate m2_bypass
    if !_rc local models "`models' m2_bypass"
    capture confirm estimate m3_rif90
    if !_rc local models "`models' m3_rif90"
    capture confirm estimate m3_qreg90
    if !_rc local models "`models' m3_qreg90"

    * Nếu có ít nhất 2 mô hình, vẽ
    tokenize "`models'"
    local n = `: word count `models''
    if `n' >= 2 {
        coefplot `models', keep(INS_dummy INS_x_THAI BYPASSED BYPASS_x_THAI Health_shock) ///
            xline(0) vertical ///
            title("So sánh hệ số chính giữa các mô hình") ///
            name(gcoef_models, replace)
        graph export "gcoef_models.png", replace
    }
}

* 8.5 Scatter + fitted values: ln_OOP_real vs HH_SIZE, theo BHYT
* Tạo fitted values từ baseline model
predict double fitted_m1, xb
twoway (scatter ln_OOP_real HH_SIZE if INS_dummy==0, mcolor(gs10)) ///
       (scatter ln_OOP_real HH_SIZE if INS_dummy==1, mcolor(blue)) ///
       (line fitted_m1 HH_SIZE, lcolor(red)), ///
       legend(order(1 "No BHYT" 2 "BHYT" 3 "Fitted (Baseline)")) ///
       title("Log(OOP) vs HH_SIZE, theo BHYT") ///
       name(gscatter_fitted, replace)
graph export "gscatter_fitted.png", replace

* ------------------------------------------------------------------------------
* 9. Lưu workspace và kết thúc
* ------------------------------------------------------------------------------
save "TVSEP_Panel_Clean_CPI_Labelled_processed.dta", replace

display ">>> ALL DONE. Check log and generated PNG files for figures. <<<"

* ==============================================================================
* END OF DO-FILE
* ==============================================================================	
* ==============================================================================
* DỰ ÁN: THE GRASSROOTS DILEMMA AND FINANCIAL PROTECTION (VIETNAM VS THAILAND)
* MASTER DO-FILE: DATA SETUP, MAIN MODELS, DYNAMIC ANALYSIS & VISUALIZATION
* DATA: TVSEP Panel (2007 - 2024)
* ==============================================================================

* ------------------------------------------------------------------------------
* PHẦN 0: THIẾT LẬP MÔI TRƯỜNG VÀ ĐƯỜNG DẪN
* ------------------------------------------------------------------------------
clear all
set more off
set linesize 120

* >>> ĐIỀU CHỈNH ĐƯỜNG DẪN TẠI ĐÂY <<<
local datadir "D:\01. HOC HANH\13. THAC SI UEH\05. MON HOC\HOC KY 2\04. KINH TE SUC KHOE\04. De tai Bao hiem y te\02. De tai cuoi ky\00. FILE LOG-DO-DATABASE 02 - TVSEP"
global figdir "D:\01. HOC HANH\13. THAC SI UEH\05. MON HOC\HOC KY 2\04. KINH TE SUC KHOE\04. De tai Bao hiem y te\02. De tai cuoi ky\01. Bai viet LATEX 02\figures"

cd "`datadir'"
capture log close
log using "Master_TVSEP_Analysis.log", replace text

* Đặt scheme nền trắng tinh chuẩn học thuật
set scheme s1color 

use "TVSEP_Panel_Clean_CPI_Labelled.dta", clear

* code lại tuổi: 
gen age = .
replace age = age_head if age_head >=15 & age_head <=100
replace age = wave - age_head if age_head > 1900 & age_head <= wave
replace age = . if age <15 | age >100
sum age, detail
hist age
gen age2 = age^2
* 1. Thay thế age_head bằng biến age đã làm sạch
replace age_head = age if age != .
* 2. Xóa biến age tạm
drop age
* 3. Kiểm tra lại nhanh
sum age_head
* 4. Lưu đè file dataset
save "TVSEP_Panel_Clean_CPI_Labelled_Final.dta", replace

* ------------------------------------------------------------------------------
* PHẦN 1: THIẾT LẬP PANEL VÀ BIẾN SỐ
* ------------------------------------------------------------------------------
* Tạo định danh Panel duy nhất và khai báo thời gian
egen id_panel = group(hhid country_code)
xtset id_panel wave

* Đảm bảo biến giả (Dummy)
gen THAI_dummy = (country_code == "THA")
replace INS_x_THAI = INS_dummy * THAI_dummy 
gen BYPASS_x_THAI = BYPASSED * THAI_dummy

* Gom nhóm biến kiểm soát
global X "age_head SEX_HEAD HH_SIZE Health_shock"

* ------------------------------------------------------------------------------
* PHẦN 2: THỐNG KÊ MÔ TẢ VÀ ĐỒ THỊ XU HƯỚNG TỔNG QUAN
* ------------------------------------------------------------------------------
display ">>> XUẤT ĐỒ THỊ XU HƯỚNG CHI PHÍ OOP TỔNG THỂ <<<"

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
display ">>> CHẠY CÁC MÔ HÌNH KINH TẾ LƯỢNG CỐT LÕI <<<"

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

* Sau đó tạo bảng:
Table: Quantile Regression Results for OOP Expenditure


* ------------------------------------------------------------------------------
* PHẦN 4: PHÂN TÍCH ĐỘNG (DYNAMIC ANALYSIS) - SỰ THAY ĐỔI THEO THỜI GIAN
* ------------------------------------------------------------------------------
display ">>> MÔ HÌNH ĐỘNG: TÁC ĐỘNG BHYT THEO TỪNG LÀN SÓNG (EVENT-STUDY) <<<"

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
	
* ==============================================================================
* KẾT THÚC
********************************************************************************
log close